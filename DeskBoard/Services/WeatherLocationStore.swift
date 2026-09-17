import Combine
import Foundation

struct WeatherLocation: Codable, Equatable, Identifiable {
    let name: String
    let country: String?
    let admin1: String?
    let latitude: Double
    let longitude: Double

    var id: String { "\(latitude),\(longitude)" }
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && latitude.isFinite && longitude.isFinite
            && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
    var regionDescription: String {
        var parts: [String] = []
        for value in [admin1, country].compactMap({ $0 }) {
            let part = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !part.isEmpty, part.caseInsensitiveCompare(name) != .orderedSame,
               !parts.contains(where: { $0.caseInsensitiveCompare(part) == .orderedSame }) {
                parts.append(part)
            }
        }
        return parts.joined(separator: ", ")
    }
    var displayName: String { regionDescription.isEmpty ? name : "\(name), \(regionDescription)" }

    static let seoul = Self(name: "Seoul", country: "South Korea", admin1: nil, latitude: 37.5665, longitude: 126.9780)
}

@MainActor
final class WeatherLocationStore: ObservableObject {
    static let shared = WeatherLocationStore()
    @Published private(set) var selected: WeatherLocation
    private let defaults: UserDefaults
    private let key = "weatherLocation.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode(WeatherLocation.self, from: data), saved.isValid {
            selected = saved
        } else {
            let latitude = defaults.object(forKey: "weatherLatitude") as? Double ?? WeatherLocation.seoul.latitude
            let longitude = defaults.object(forKey: "weatherLongitude") as? Double ?? WeatherLocation.seoul.longitude
            let legacy = WeatherLocation(name: "Saved location", country: nil, admin1: nil, latitude: latitude, longitude: longitude)
            // The old free-text name never changed coordinates; do not trust it as a city label.
            selected = legacy.isValid && legacy.id != WeatherLocation.seoul.id ? legacy : .seoul
        }
    }

    func select(_ location: WeatherLocation) {
        guard location.isValid, let data = try? JSONEncoder().encode(location) else { return }
        // The single encoded record is authoritative; legacy values remain compatible.
        defaults.set(data, forKey: key)
        defaults.set(location.latitude, forKey: "weatherLatitude")
        defaults.set(location.longitude, forKey: "weatherLongitude")
        defaults.set(location.displayName, forKey: "weatherLocationName")
        selected = location
    }
}

protocol WeatherLocationSearching {
    func search(_ query: String) async throws -> [WeatherLocation]
}

struct OpenMeteoLocationProvider: WeatherLocationSearching {
    let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    private struct Response: Decodable { let results: [WeatherLocation]? }

    func search(_ query: String) async throws -> [WeatherLocation] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return [] }
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            .init(name: "name", value: query), .init(name: "count", value: "10"),
            .init(name: "language", value: "en"), .init(name: "format", value: "json")
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, response) = try await session.data(for: URLRequest(url: url, timeoutInterval: 15))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        var seen: Set<String> = []
        return (decoded.results ?? []).filter { $0.isValid && seen.insert($0.id).inserted }
    }
}

@MainActor
final class WeatherLocationSearchModel: ObservableObject {
    @Published private(set) var results: [WeatherLocation] = []
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?
    private let provider: WeatherLocationSearching
    private let debounce: Duration
    private var generation = 0

    init(provider: WeatherLocationSearching = OpenMeteoLocationProvider(), debounce: Duration = .milliseconds(350)) {
        self.provider = provider
        self.debounce = debounce
    }

    func search(_ text: String) async {
        generation += 1
        let request = generation
        results = []
        errorMessage = nil
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { isSearching = false; return }
        isSearching = true
        do {
            try await Task.sleep(for: debounce)
            let matches = try await provider.search(query)
            try Task.checkCancellation()
            guard request == generation else { return }
            results = matches
            isSearching = false
        } catch {
            guard request == generation else { return }
            isSearching = false
            if !Task.isCancelled && !(error is CancellationError) {
                errorMessage = "Could not search cities. Check your connection and try again."
            }
        }
    }
}
