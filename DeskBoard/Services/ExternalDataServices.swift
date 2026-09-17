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

struct MarketQuote: Codable, Identifiable {
    var id: String { symbol }
    let symbol: String
    let name: String
    let value: Double
    let changePercent: Double
    let updatedAt: Date
    var marketTime: Date? = nil
}

private let marketSymbolOrder = MarketInstrument.allCases.map(\.symbol)

protocol MarketProviding {
    func fetchQuotes(for instruments: [MarketInstrument]) async throws -> [MarketQuote]
}

struct YahooMarketProvider: MarketProviding {
    var session: URLSession = .shared
    private struct Response: Decodable {
        struct Chart: Decodable { let result: [Result]? }
        struct Result: Decodable {
            struct Meta: Decodable {
                let regularMarketPrice: Double?
                let chartPreviousClose: Double?
                let previousClose: Double?
                let regularMarketTime: TimeInterval?
            }
            struct Indicators: Decodable {
                struct Quote: Decodable { let close: [Double?] }
                let quote: [Quote]
            }
            let meta: Meta
            let indicators: Indicators
        }
        let chart: Chart
    }

    func fetchQuotes(for instruments: [MarketInstrument]) async throws -> [MarketQuote] {
        let quotes = await withTaskGroup(of: MarketQuote?.self) { group in
            for instrument in instruments {
                group.addTask { try? await fetch(instrument) }
            }
            var result: [MarketQuote] = []
            for await quote in group {
                if let quote { result.append(quote) }
            }
            return result
        }
        guard !quotes.isEmpty else { throw URLError(.cannotLoadFromNetwork) }
        let quotesBySymbol = Dictionary(quotes.map { ($0.symbol, $0) }, uniquingKeysWith: { _, new in new })
        return marketSymbolOrder.compactMap { quotesBySymbol[$0] }
    }

    private func fetch(_ instrument: MarketInstrument) async throws -> MarketQuote {
        let encoded = instrument.symbol.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? instrument.symbol
        var components = URLComponents(string: "https://query2.finance.yahoo.com/v8/finance/chart/\(encoded)")!
        // The one-session range makes chartPreviousClose the previous session's
        // close. A five-day range supplies a five-day baseline instead.
        components.queryItems = [.init(name: "range", value: "1d"), .init(name: "interval", value: "1d")]
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("DeskBoard/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let result = decoded.chart.result?.first else { throw URLError(.cannotParseResponse) }
        // Let the provider define the trading session (indices, FX and futures
        // have different boundaries), rather than guessing from local midnight.
        let marketDate = result.meta.regularMarketTime.map { Date(timeIntervalSince1970: $0) }
        let previous = result.meta.previousClose ?? result.meta.chartPreviousClose
        guard let latest = result.meta.regularMarketPrice, latest.isFinite,
              let previous, previous.isFinite, previous > 0 else { throw URLError(.cannotParseResponse) }
        let change = (latest - previous) / previous * 100
        guard change.isFinite else { throw URLError(.cannotParseResponse) }
        return MarketQuote(symbol: instrument.symbol, name: instrument.name, value: latest, changePercent: change, updatedAt: .now, marketTime: marketDate)
    }
}

@MainActor
final class MarketService: ObservableObject {
    @Published private(set) var quotes: [MarketQuote] = []
    @Published private(set) var isUnavailable = false
    private let provider: MarketProviding
    private var timer: Timer?
    // v1 percentages used the chart range baseline; never present them as daily changes.
    private let cacheKey = "market.cache.v2"
    private let defaults: UserDefaults
    private let preferences: DashboardPreferences
    private var selectionObserver: AnyCancellable?
    private var refreshGeneration = 0
    private(set) var isRunning = false
    private var refreshTask: Task<Void, Never>?
    private var backoff = RefreshBackoff()
    private let logger = Logger(subsystem: "com.local.DeskBoard", category: "market")

    init(provider: MarketProviding = YahooMarketProvider(), preferences: DashboardPreferences? = nil, defaults: UserDefaults = .standard) {
        self.provider = provider
        self.defaults = defaults
        self.preferences = preferences ?? .shared
        if let data = defaults.data(forKey: cacheKey) {
            let cached = (try? JSONDecoder().decode([MarketQuote].self, from: data)) ?? []
            let cachedBySymbol = Dictionary(cached.map { ($0.symbol, $0) }, uniquingKeysWith: { _, new in new })
            quotes = marketSymbolOrder.compactMap { cachedBySymbol[$0] }
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        selectionObserver = preferences.$marketInstruments.dropFirst().sink { [weak self] _ in
            self?.refreshTask?.cancel()
            self?.refreshTask = Task { @MainActor in await self?.refresh() }
        }
        refreshTask = Task { await refresh() }
    }

    func stop() {
        isRunning = false
        refreshGeneration += 1
        selectionObserver = nil
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    func isDelayed(_ quote: MarketQuote?, at now: Date = .now) -> Bool {
        guard let quote else { return false }
        return now.timeIntervalSince(quote.updatedAt) > max(1800, refreshInterval * 2)
    }

    private var refreshInterval: TimeInterval {
        let value = defaults.double(forKey: "marketRefreshInterval")
        return value.isFinite ? max(60, min(900, value)) : 60
    }

    func schedule() {
        guard isRunning else { return }
        timer?.invalidate()
        let seconds = backoff.delay(base: refreshInterval)
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.refreshTask = Task { await self?.refresh() } }
        }
        timer?.tolerance = min(30, seconds * 0.1)
    }

    func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        let selection = preferences.marketInstruments
        do {
            let values = try await provider.fetchQuotes(for: selection)
            guard generation == refreshGeneration, !Task.isCancelled else { return }
            let existingBySymbol = Dictionary(quotes.map { ($0.symbol, $0) }, uniquingKeysWith: { _, new in new })
            let freshBySymbol = Dictionary(values.filter { $0.value.isFinite && $0.changePercent.isFinite }.map { ($0.symbol, $0) }, uniquingKeysWith: { _, new in new })
            backoff.record(success: selection.allSatisfy { freshBySymbol[$0.symbol] != nil })
            quotes = marketSymbolOrder.compactMap { freshBySymbol[$0] ?? existingBySymbol[$0] }
            isUnavailable = !quotes.contains { quote in selection.contains { $0.symbol == quote.symbol } }
            if let data = try? JSONEncoder().encode(quotes) { defaults.set(data, forKey: cacheKey) }
        } catch {
            guard generation == refreshGeneration, !Task.isCancelled else { return }
            isUnavailable = !quotes.contains { quote in selection.contains { $0.symbol == quote.symbol } }
            backoff.record(success: false)
            logger.notice("Market refresh failed; retaining cache. Error code: \((error as NSError).code)")
        }
        schedule()
    }
}
