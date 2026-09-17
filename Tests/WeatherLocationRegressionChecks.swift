import Foundation

private let tokyo = WeatherLocation(name: "Tokyo", country: "Japan", admin1: "Tokyo", latitude: 35.68, longitude: 139.69)
private let london = WeatherLocation(name: "London", country: "United Kingdom", admin1: "England", latitude: 51.51, longitude: -0.13)

private struct SearchFixture: WeatherLocationSearching {
    func search(_ query: String) async throws -> [WeatherLocation] {
        if query == "offline" { throw URLError(.notConnectedToInternet) }
        if query == "slow" {
            // Deliberately ignore cancellation to test stale-result protection.
            try? await Task.sleep(for: .milliseconds(100))
            return [.seoul]
        }
        return [tokyo]
    }
}

private final class GeocodingFixture: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        let term = query.first { $0.name == "name" }!.value!
        precondition(query.contains { $0.name == "language" && $0.value == "en" })
        let body: String
        switch term {
        case "empty": body = "{}"
        case "broken": body = "not json"
        default:
            body = #"{"results":[{"name":"London","country":"United Kingdom","admin1":"England","latitude":51.51,"longitude":-0.13},{"name":"London","country":"Canada","admin1":"Ontario","latitude":42.98,"longitude":-81.25},{"name":"London","latitude":51.51,"longitude":-0.13},{"name":"Invalid","latitude":100,"longitude":20}]}"#
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: term == "offline" ? 503 : 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private actor WeatherFixture: WeatherProviding {
    struct Request { let id: UUID; let latitude: Double; let longitude: Double }
    private var pending: [UUID: CheckedContinuation<WeatherSnapshot, Error>] = [:]
    private var requests: [Request] = []
    private var waiters: [CheckedContinuation<Request, Never>] = []
    func fetch(latitude: Double, longitude: Double) async throws -> WeatherSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            let request = Request(id: UUID(), latitude: latitude, longitude: longitude)
            pending[request.id] = continuation
            if waiters.isEmpty { requests.append(request) }
            else { waiters.removeFirst().resume(returning: request) }
        }
    }
    func nextRequest() async -> Request {
        if !requests.isEmpty { return requests.removeFirst() }
        return await withCheckedContinuation { waiters.append($0) }
    }
    func complete(_ request: Request, temperature: Double?) {
        let continuation = pending.removeValue(forKey: request.id)!
        if let temperature {
            continuation.resume(returning: WeatherSnapshot(temperature: temperature, high: temperature + 2, low: temperature - 2, precipitationProbability: 0, weatherCode: 0, updatedAt: .now))
        } else {
            continuation.resume(throwing: URLError(.notConnectedToInternet))
        }
    }
}

@main
struct WeatherLocationRegressionChecks {
    @MainActor static func main() async throws {
        let suite = "DeskBoard.WeatherChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("Paris", forKey: "weatherLocationName")
        let locations = WeatherLocationStore(defaults: defaults)
        precondition(locations.selected == .seoul, "Legacy free text must not mislabel Seoul coordinates")
        precondition(tokyo.displayName == "Tokyo, Japan")
        precondition(london.displayName == "London, England, United Kingdom")
        locations.select(tokyo)
        precondition(WeatherLocationStore(defaults: defaults).selected == tokyo)
        precondition(defaults.double(forKey: "weatherLatitude") == tokyo.latitude)
        locations.select(WeatherLocation(name: "Bad", country: nil, admin1: nil, latitude: 100, longitude: 0))
        precondition(locations.selected == tokyo)
        defaults.removeObject(forKey: "weatherLocation.v1")
        precondition(WeatherLocationStore(defaults: defaults).selected.id == tokyo.id, "Preserve legacy custom coordinates")
        locations.select(.seoul)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GeocodingFixture.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let provider = OpenMeteoLocationProvider(session: session)
        let results = try await provider.search(" London ")
        precondition(results.count == 2 && results[0] == london)
        precondition(results[1].regionDescription == "Ontario, Canada")
        let empty = try await provider.search("empty")
        let short = try await provider.search("a")
        precondition(empty.isEmpty && short.isEmpty)
        for query in ["offline", "broken"] {
            do { _ = try await provider.search(query); preconditionFailure("Expected search failure") }
            catch { /* Errors reach the picker instead of changing the current city. */ }
        }
        let model = WeatherLocationSearchModel(provider: SearchFixture(), debounce: .zero)
        let slow = Task { await model.search("slow") }
        while !model.isSearching { await Task.yield() }
        await model.search("Tokyo")
        await slow.value
        precondition(model.results == [tokyo], "Stale search must not overwrite newer results")
        await model.search("offline")
        precondition(model.errorMessage != nil && !model.isSearching && model.results.isEmpty)
        await model.search("Tokyo")
        precondition(model.errorMessage == nil && model.results == [tokyo])
        let cancelled = Task { await model.search("slow") }
        while !model.isSearching { await Task.yield() }
        cancelled.cancel()
        await cancelled.value
        precondition(model.results.isEmpty && model.errorMessage == nil && !model.isSearching)
        await model.search(" ")
        precondition(model.results.isEmpty)

        let weatherProvider = WeatherFixture()
        let weather = WeatherService(provider: weatherProvider, locations: locations, defaults: defaults)
        let first = Task { await weather.refresh() }
        let firstRequest = await weatherProvider.nextRequest()
        await weatherProvider.complete(firstRequest, temperature: 10)
        await first.value
        precondition(weather.snapshot?.temperature == 10)
        let stale = Task { await weather.refresh() }
        let staleRequest = await weatherProvider.nextRequest()
        locations.select(tokyo)
        precondition(weather.snapshot == nil, "Old city's forecast must disappear immediately")
        let selectedRequest = await weatherProvider.nextRequest()
        precondition(selectedRequest.latitude == tokyo.latitude && selectedRequest.longitude == tokyo.longitude)
        await weatherProvider.complete(selectedRequest, temperature: 22)
        for _ in 0..<100 where weather.snapshot == nil { try await Task.sleep(for: .milliseconds(2)) }
        precondition(weather.snapshot?.temperature == 22)
        await weatherProvider.complete(staleRequest, temperature: 11)
        await stale.value
        precondition(weather.snapshot?.temperature == 22, "Old response must not overwrite the selected city")
        let failedRefresh = Task { await weather.refresh() }
        let failedRequest = await weatherProvider.nextRequest()
        await weatherProvider.complete(failedRequest, temperature: nil)
        await failedRefresh.value
        precondition(weather.snapshot?.temperature == 22 && !weather.isUnavailable)
        do {
            let restored = WeatherService(provider: weatherProvider, locations: locations, defaults: defaults)
            precondition(restored.snapshot?.temperature == 22, "Matching cache should restore")
        }
        locations.select(london)
        let unavailableRequest = await weatherProvider.nextRequest()
        await weatherProvider.complete(unavailableRequest, temperature: nil)
        for _ in 0..<100 where !weather.isUnavailable { try await Task.sleep(for: .milliseconds(2)) }
        precondition(weather.snapshot == nil && weather.isUnavailable)
        let mismatch = WeatherService(provider: weatherProvider, locations: locations, defaults: defaults)
        precondition(mismatch.snapshot == nil, "Another city's cache must not restore")
        print("PASS: migration, name/coordinate persistence, API decoding/errors, search cancellation/races, immediate refresh, stale forecast rejection and location-bound caching")
    }
}
