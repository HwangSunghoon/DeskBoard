import Foundation

private final class ChartFixture: URLProtocol {
    static var body = ""
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        check(request.timeoutInterval == 20)
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        check(query.contains { $0.name == "range" && $0.value == "1d" }, "A 5d chart baseline must never be used for daily changes")
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private actor MarketFixture: MarketProviding {
    var values: [MarketQuote] = []
    func set(_ values: [MarketQuote]) { self.values = values }
    func fetchQuotes(for instruments: [MarketInstrument]) async throws -> [MarketQuote] {
        if values.isEmpty { throw URLError(.notConnectedToInternet) }
        return values
    }
}

private struct OfflineWeather: WeatherProviding {
    func fetch(latitude: Double, longitude: Double) async throws -> WeatherSnapshot {
        throw URLError(.notConnectedToInternet)
    }
}

private func check(_ condition: Bool, _ message: String = "Regression check failed") {
    precondition(condition, message)
}

@main struct NetworkResilienceRegressionChecks {
    @MainActor static func main() async throws {
        var backoff = RefreshBackoff()
        check(backoff.delay(base: 60) == 60)
        backoff.record(success: false)
        check(backoff.delay(base: 60) == 120)
        for _ in 0..<20 { backoff.record(success: false) }
        check(backoff.delay(base: 60) <= 3600)
        backoff.record(success: true)
        check(backoff.delay(base: 60) == 60)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ChartFixture.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let provider = YahooMarketProvider(session: session)
        // The requested range must be 1d: its chart baseline is yesterday's close.
        for closes in ["[100]", "[null]"] {
            ChartFixture.body = """
            {"chart":{"result":[{"meta":{"regularMarketPrice":100,"chartPreviousClose":110,"regularMarketTime":210000},"indicators":{"quote":[{"close":\(closes)}]}}]}}
            """
            let value = try await provider.fetchQuotes(for: [.sp500])[0]
            check(abs(value.changePercent - (-100.0 / 11)) < 0.00001)
        }
        // Provider baselines remain authoritative across weekends and overnight sessions.
        ChartFixture.body = #"{"chart":{"result":[{"meta":{"regularMarketPrice":100,"chartPreviousClose":125,"regularMarketTime":176400,"exchangeTimezoneName":"America/New_York"},"indicators":{"quote":[{"close":[100]}]}}]}}"#
        check(try await provider.fetchQuotes(for: [.sp500])[0].changePercent == -20)
        ChartFixture.body = #"{"chart":{"result":[{"meta":{"regularMarketPrice":100,"previousClose":125},"indicators":{"quote":[{"close":[]}]}}]}}"#
        check(try await provider.fetchQuotes(for: [.sp500])[0].changePercent == -20)
        ChartFixture.body = #"{"chart":{"result":[{"meta":{"regularMarketPrice":100},"indicators":{"quote":[{"close":[90,100]}]}}]}}"#
        do { _ = try await provider.fetchQuotes(for: [.sp500]); preconditionFailure("Ambiguous baseline must not produce a misleading percentage") }
        catch { }

        let suite = "DeskBoard.NetworkResilience.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["sp500", "kospi"], forKey: "marketInstruments.v1")
        let preferences = DashboardPreferences(defaults: defaults)
        let fixture = MarketFixture()
        let service = MarketService(provider: fixture, preferences: preferences, defaults: defaults)
        let now = Date()
        let a = MarketQuote(symbol: "^GSPC", name: "S&P 500", value: 100, changePercent: 1, updatedAt: now)
        let b = MarketQuote(symbol: "^KS11", name: "KOSPI", value: 200, changePercent: 2, updatedAt: now)
        await fixture.set([a, b])
        await service.refresh()
        await fixture.set([MarketQuote(symbol: a.symbol, name: a.name, value: 101, changePercent: 2, updatedAt: now)])
        await service.refresh()
        check(service.quotes.first { $0.symbol == b.symbol }?.value == 200)
        await fixture.set([])
        await service.refresh()
        check(service.quotes.count == 2 && !service.isUnavailable)
        check(!service.isDelayed(a, at: now.addingTimeInterval(1799)))
        check(service.isDelayed(a, at: now.addingTimeInterval(1801)))
        let restored = MarketService(provider: fixture, preferences: preferences, defaults: defaults)
        check(restored.quotes.count == 2)
        service.start()
        check(service.isRunning)
        service.stop()
        check(!service.isRunning)

        struct Cache: Encodable { let locationID: String; let snapshot: WeatherSnapshot }
        let locations = WeatherLocationStore(defaults: defaults)
        let snapshot = WeatherSnapshot(temperature: 22, high: 24, low: 18, precipitationProbability: 5, weatherCode: 1, updatedAt: now)
        defaults.set(try JSONEncoder().encode(Cache(locationID: locations.selected.id, snapshot: snapshot)), forKey: "weather.cache.v2")
        let weather = WeatherService(provider: OfflineWeather(), locations: locations, defaults: defaults)
        await weather.refresh()
        check(weather.snapshot?.temperature == 22 && !weather.isUnavailable)
        check(!weather.isDelayed(at: now.addingTimeInterval(7199)))
        check(weather.isDelayed(at: now.addingTimeInterval(7201)))
        weather.start(); weather.stop()
        check(!weather.isRunning)
        print("PASS: one-session baseline, null bars, overnight sessions, explicit previous close, missing baseline rejection, partial/offline cache, conservative delay thresholds, retry backoff, service stop")
    }
}
