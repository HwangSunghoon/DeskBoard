import Foundation

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

        let suite = "DeskBoard.NetworkResilience.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date()

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
        print("PASS: offline weather cache, conservative delay thresholds, retry backoff, service stop")
    }
}
