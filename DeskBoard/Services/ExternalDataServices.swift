import Foundation

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
        let (data, response) = try await URLSession.shared.data(from: url)
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
    private let cacheKey = "weather.cache"

    init(provider: WeatherProviding = OpenMeteoWeatherProvider()) {
        self.provider = provider
        if let data = UserDefaults.standard.data(forKey: cacheKey) {
            snapshot = try? JSONDecoder().decode(WeatherSnapshot.self, from: data)
        }
    }

    func start() {
        Task { await refresh() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        timer?.tolerance = 60
    }

    func refresh() async {
        let defaults = UserDefaults.standard
        let latitude = defaults.object(forKey: "weatherLatitude") as? Double ?? 37.5665
        let longitude = defaults.object(forKey: "weatherLongitude") as? Double ?? 126.9780
        do {
            let value = try await provider.fetch(latitude: latitude, longitude: longitude)
            snapshot = value
            isUnavailable = false
            if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: cacheKey) }
        } catch {
            isUnavailable = snapshot == nil
        }
    }
}

struct MarketQuote: Codable, Identifiable {
    var id: String { symbol }
    let symbol: String
    let name: String
    let value: Double
    let changePercent: Double
    let updatedAt: Date
}

protocol MarketProviding {
    func fetchQuotes() async throws -> [MarketQuote]
}

struct YahooMarketProvider: MarketProviding {
    private struct Instrument { let symbol: String; let name: String }
    private struct Response: Decodable {
        struct Chart: Decodable { let result: [Result]? }
        struct Result: Decodable {
            struct Meta: Decodable {
                let regularMarketPrice: Double?
                let chartPreviousClose: Double?
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

    private let instruments = [Instrument(symbol: "^KS11", name: "KOSPI"), Instrument(symbol: "^GSPC", name: "S&P 500")]

    func fetchQuotes() async throws -> [MarketQuote] {
        try await withThrowingTaskGroup(of: MarketQuote.self) { group in
            for instrument in instruments {
                group.addTask { try await fetch(instrument) }
            }
            var result: [MarketQuote] = []
            for try await quote in group { result.append(quote) }
            return result.sorted { $0.name == "KOSPI" && $1.name != "KOSPI" }
        }
    }

    private func fetch(_ instrument: Instrument) async throws -> MarketQuote {
        let encoded = instrument.symbol.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? instrument.symbol
        var components = URLComponents(string: "https://query2.finance.yahoo.com/v8/finance/chart/\(encoded)")!
        components.queryItems = [.init(name: "range", value: "5d"), .init(name: "interval", value: "1d")]
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("DeskBoard/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let result = decoded.chart.result?.first else { throw URLError(.cannotParseResponse) }
        let closes = result.indicators.quote.first?.close.compactMap { $0 } ?? []
        guard let latest = result.meta.regularMarketPrice ?? closes.last,
              let previous = result.meta.chartPreviousClose ?? closes.dropLast().last,
              previous != 0 else { throw URLError(.cannotParseResponse) }
        return MarketQuote(symbol: instrument.symbol, name: instrument.name, value: latest, changePercent: (latest - previous) / previous * 100, updatedAt: .now)
    }
}

@MainActor
final class MarketService: ObservableObject {
    @Published private(set) var quotes: [MarketQuote] = []
    @Published private(set) var isUnavailable = false
    private let provider: MarketProviding
    private var timer: Timer?
    private let cacheKey = "market.cache"

    init(provider: MarketProviding = YahooMarketProvider()) {
        self.provider = provider
        if let data = UserDefaults.standard.data(forKey: cacheKey) {
            quotes = (try? JSONDecoder().decode([MarketQuote].self, from: data)) ?? []
        }
    }

    func start() {
        schedule()
        Task { await refresh() }
    }

    func schedule() {
        timer?.invalidate()
        let seconds = max(60, UserDefaults.standard.double(forKey: "marketRefreshInterval"))
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        timer?.tolerance = min(30, seconds * 0.1)
    }

    func refresh() async {
        do {
            let values = try await provider.fetchQuotes()
            quotes = values
            isUnavailable = false
            if let data = try? JSONEncoder().encode(values) { UserDefaults.standard.set(data, forKey: cacheKey) }
        } catch {
            isUnavailable = quotes.isEmpty
        }
    }
}
