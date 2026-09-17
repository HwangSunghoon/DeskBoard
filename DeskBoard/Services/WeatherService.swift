import Foundation
import Combine
import OSLog

/// Failures slow background retries down; they never clear the last good value.
struct RefreshBackoff {
    private(set) var failures = 0
    mutating func record(success: Bool) { failures = success ? 0 : min(failures + 1, 6) }
    func delay(base: TimeInterval) -> TimeInterval {
        min(3600, base * pow(2, Double(failures)))
    }
}

struct WeatherSnapshot: Codable {
    let temperature: Double
    let high: Double
    let low: Double
    let precipitationProbability: Int
    let weatherCode: Int
    let updatedAt: Date
}

protocol WeatherProviding {
    func fetch(latitude: Double, longitude: Double) async throws -> WeatherSnapshot
}

struct OpenMeteoWeatherProvider: WeatherProviding {
    private struct Response: Decodable {
        struct Current: Decodable { let temperature_2m: Double; let weather_code: Int }
        struct Daily: Decodable {
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
            let precipitation_probability_max: [Int]
        }
        let current: Current
        let daily: Daily
    }

    func fetch(latitude: Double, longitude: Double) async throws -> WeatherSnapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(latitude)),
            .init(name: "longitude", value: String(longitude)),
            .init(name: "current", value: "temperature_2m,weather_code"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "1")
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 20))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let high = decoded.daily.temperature_2m_max.first,
              let low = decoded.daily.temperature_2m_min.first,
              let rain = decoded.daily.precipitation_probability_max.first else { throw URLError(.cannotParseResponse) }
        return WeatherSnapshot(temperature: decoded.current.temperature_2m, high: high, low: low, precipitationProbability: rain, weatherCode: decoded.current.weather_code, updatedAt: .now)
    }
}

@MainActor
final class WeatherService: ObservableObject {
    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var isUnavailable = false
    private let provider: WeatherProviding
    private var timer: Timer?
    private let cacheKey = "weather.cache.v2"
    private let locations: WeatherLocationStore
    private let defaults: UserDefaults
    private var locationObserver: AnyCancellable?
    private var displayedLocationID: String
    private var refreshGeneration = 0
    private(set) var isRunning = false
    private var refreshTask: Task<Void, Never>?
    private var backoff = RefreshBackoff()
    private let logger = Logger(subsystem: "com.local.DeskBoard", category: "weather")

    private struct Cache: Codable {
        let locationID: String
        let snapshot: WeatherSnapshot
    }

    init(provider: WeatherProviding = OpenMeteoWeatherProvider(), locations: WeatherLocationStore? = nil, defaults: UserDefaults = .standard) {
        self.provider = provider
        self.locations = locations ?? .shared
        self.defaults = defaults
        displayedLocationID = self.locations.selected.id
        if let data = defaults.data(forKey: cacheKey),
           let cache = try? JSONDecoder().decode(Cache.self, from: data), cache.locationID == displayedLocationID {
            snapshot = cache.snapshot
        }
        locationObserver = self.locations.$selected.dropFirst().sink { [weak self] location in
            guard let self, location.id != self.displayedLocationID else { return }
            self.displayedLocationID = location.id
            self.refreshGeneration += 1
            self.snapshot = nil
            self.isUnavailable = false
            Task { @MainActor [weak self] in await self?.refresh() }
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        refreshTask = Task { await refresh() }
    }

    func stop() {
        isRunning = false
        refreshGeneration += 1
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    func isDelayed(at now: Date = .now) -> Bool {
        snapshot.map { now.timeIntervalSince($0.updatedAt) > 7200 } ?? false
    }

    var freshnessDescription: String {
        guard let snapshot else { return "Weather is temporarily unavailable. Retrying automatically." }
        return "Last updated \(snapshot.updatedAt.formatted(date: .abbreviated, time: .shortened)). Cached weather is kept while updates retry."
    }

    private func scheduleNextRefresh() {
        guard isRunning else { return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: backoff.delay(base: 900), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.refreshTask = Task { await self?.refresh() } }
        }
        timer?.tolerance = 30
    }

    func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        let location = locations.selected
        do {
            let value = try await provider.fetch(latitude: location.latitude, longitude: location.longitude)
            guard generation == refreshGeneration, location.id == locations.selected.id, !Task.isCancelled else { return }
            snapshot = value
            backoff.record(success: true)
            isUnavailable = false
            let cache = Cache(locationID: location.id, snapshot: value)
            if let data = try? JSONEncoder().encode(cache) { defaults.set(data, forKey: cacheKey) }
        } catch {
            guard generation == refreshGeneration, location.id == locations.selected.id, !Task.isCancelled else { return }
            isUnavailable = snapshot == nil
            backoff.record(success: false)
            logger.notice("Weather refresh failed; retaining cache. Error code: \((error as NSError).code)")
        }
        scheduleNextRefresh()
    }
}
