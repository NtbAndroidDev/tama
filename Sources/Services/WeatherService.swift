import Foundation
import CoreLocation
import AppKit

/// One hour of the forecast row on the weather card.
public struct HourForecast: Sendable, Equatable, Identifiable {
    public var date: Date
    /// Degrees Celsius.
    public var temperature: Double
    public var code: Int
    public var isDay: Bool
    public var id: Date { date }

    public var symbol: String { WeatherSnapshot.symbol(code: code, isDay: isDay) }
    public var temperatureText: String { WeatherSnapshot.format(temperature, unit: false) }
}

/// Current conditions, today's range and the next hours, for the weather
/// card and the lock screen's status row.
public struct WeatherSnapshot: Sendable, Equatable {
    /// Degrees Celsius; formatted in the user's unit at draw time.
    public var temperature: Double
    /// WMO weather interpretation code, as Open-Meteo reports it.
    public var code: Int
    public var isDay: Bool
    /// US AQI; nil when the air-quality lookup failed or is switched off.
    public var aqi: Int?
    /// Today's and tomorrow's, so there's always a next one.
    public var sunrises: [Date]
    public var sunsets: [Date]
    /// Today's high and low, °C.
    public var high: Double?
    public var low: Double?
    /// The next few hours.
    public var hourly: [HourForecast] = []

    public var temperatureText: String { Self.format(temperature, unit: true) }
    /// "19°" in the user's unit, without the letter.
    public var bareTemperatureText: String { Self.format(temperature, unit: false) }

    static func format(_ celsius: Double, unit: Bool) -> String {
        let text = Measurement(value: celsius, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
        guard !unit else { return text }
        // "19°C" → "19°": keep the digits and the degree sign.
        return text.replacingOccurrences(of: "C", with: "").replacingOccurrences(of: "F", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    public var symbol: String { Self.symbol(code: code, isDay: isDay) }

    static func symbol(code: Int, isDay: Bool) -> String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 65, 82: "cloud.heavyrain.fill"
        case 61...67, 80...82: "cloud.rain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    public var summary: String {
        switch code {
        case 0: isDay ? "Sunny" : "Clear"
        case 1: "Mostly clear"
        case 2: "Partly cloudy"
        case 3: "Cloudy"
        case 45, 48: "Fog"
        case 51...57: "Drizzle"
        case 65, 82: "Heavy rain"
        case 80, 81: "Showers"
        case 61...67: "Rain"
        case 71...77, 85, 86: "Snow"
        case 95...99: "Thunderstorm"
        default: "—"
        }
    }

    /// "H:19° L:13°"
    public var rangeText: String? {
        guard let high, let low else { return nil }
        return "H:\(Self.format(high, unit: false)) L:\(Self.format(low, unit: false))"
    }

    /// The US EPA band for the AQI.
    public var aqiLabel: String? {
        guard let aqi else { return nil }
        switch aqi {
        case ..<51: return "Good"
        case ..<101: return "Moderate"
        case ..<151: return "Sensitive groups"
        case ..<201: return "Unhealthy"
        case ..<301: return "Very unhealthy"
        default: return "Hazardous"
        }
    }

    /// Whichever of sunrise or sunset comes next.
    public func nextSunEvent(after now: Date = Date()) -> (isSunset: Bool, date: Date)? {
        let events = sunrises.map { (false, $0) } + sunsets.map { (true, $0) }
        return events.filter { $0.1 > now }.min { $0.1 < $1.1 }.map { (isSunset: $0.0, date: $0.1) }
    }
}

/// A place from the city search (Open-Meteo geocoding).
public struct WeatherPlace: Sendable, Equatable, Identifiable, Decodable {
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var country: String?
    public var admin1: String?
    public var id: String { "\(name)|\(latitude)|\(longitude)" }

    /// "Hanoi, Vietnam" or "Portland, Oregon, United States".
    public var detail: String {
        [admin1, country].compactMap { $0 }.filter { !$0.isEmpty && $0 != name }.joined(separator: ", ")
    }
}

/// Weather and air quality from Open-Meteo (free, no key). Runs only while
/// something asks for it (the lock screen, the Home card, the Weather
/// droplet). Settings › Droplets › Weather picks the place: this Mac's
/// location, rounded to about a kilometre before it leaves the Mac, or a
/// fixed city from the search. Nothing else is sent.
@MainActor
public final class WeatherService: NSObject, ObservableObject {
    public static let shared = WeatherService()

    @Published public private(set) var snapshot: WeatherSnapshot?
    @Published public private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published public private(set) var lastError: String?
    @Published public private(set) var isLoading = false

    private let manager = CLLocationManager()
    private var latitude: Double?
    private var longitude: Double?
    private var timer: Timer?
    /// Who needs the weather right now ("lockScreen", "home"); runs while any does.
    private var holders: Set<String> = []
    private var isRunning: Bool { !holders.isEmpty }
    private var lastFetch: Date?

    /// Settings › Droplets › Weather › Refresh interval.
    private var refreshInterval: TimeInterval {
        TimeInterval(max(AppState.shared.weatherRefreshMinutes, 5)) * 60
    }

    private var usesFixedPlace: Bool {
        let state = AppState.shared
        return state.weatherLocationMode == .fixed && !state.weatherPlaceName.isEmpty
    }

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        authorization = manager.authorizationStatus
    }

    /// Location Services refused, and the weather needs them (automatic place).
    public var isDenied: Bool {
        !usesFixedPlace && (authorization == .denied || authorization == .restricted)
    }
    private var isAuthorized: Bool {
        authorization != .denied && authorization != .restricted && authorization != .notDetermined
    }

    /// "Local" for this Mac's location, else the fixed place's name.
    public var placeTitle: String {
        usesFixedPlace ? AppState.shared.weatherPlaceName : "Local"
    }
    public var isLocal: Bool { !usesFixedPlace }

    /// Starts updating for `holder`; asks for Location the first time.
    public func start(for holder: String) {
        let wasRunning = isRunning
        holders.insert(holder)
        guard !wasRunning else { return refresh() }
        scheduleTimer()
        refresh(force: lastFetch == nil)
    }

    public func stop(for holder: String) {
        holders.remove(holder)
        guard !isRunning else { return }
        timer?.invalidate()
        timer = nil
    }

    /// Settings › Refresh interval changed: restart the clock.
    public func intervalChanged() {
        guard isRunning else { return }
        scheduleTimer()
        refresh()
    }

    /// Automatic ↔ fixed, or a new place: fetch for it straight away.
    public func locationSettingsChanged() {
        latitude = nil
        longitude = nil
        snapshot = nil
        lastError = nil
        guard isRunning else { return }
        refresh(force: true)
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let tick = Timer(timeInterval: refreshInterval, repeats: true) { _ in
            Task { @MainActor in
                guard !PowerStateService.shared.isDormant else { return }
                WeatherService.shared.refresh(force: true)
            }
        }
        tick.tolerance = 60
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
    }

    /// Fetches again unless the last result is still fresh.
    public func refresh(force: Bool = false) {
        guard isRunning else { return }
        if !force, let lastFetch, Date().timeIntervalSince(lastFetch) < refreshInterval - 60 { return }
        if usesFixedPlace {
            let state = AppState.shared
            latitude = state.weatherPlaceLatitude
            longitude = state.weatherPlaceLongitude
            Task { await fetch() }
            return
        }
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if isAuthorized {
            // A laptop moves; take a fresh fix each time rather than reuse the old one.
            manager.requestLocation()
        }
    }

    public func openLocationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    private func located(latitude: Double, longitude: Double) {
        guard !usesFixedPlace else { return }
        // ~1 km: plenty for weather, and all that leaves the Mac.
        self.latitude = (latitude * 100).rounded() / 100
        self.longitude = (longitude * 100).rounded() / 100
        Task { await fetch() }
    }

    private func fetch() async {
        guard let latitude, let longitude else { return }
        let coords = "latitude=\(latitude)&longitude=\(longitude)"
        let wantsAQI = AppState.shared.weatherShowsAQI
        guard let forecastURL = URL(string: "https://api.open-meteo.com/v1/forecast?\(coords)&current=temperature_2m,weather_code,is_day&hourly=temperature_2m,weather_code,is_day&daily=sunrise,sunset,temperature_2m_max,temperature_2m_min&forecast_days=2&timezone=auto&timeformat=unixtime"),
              let airURL = URL(string: "https://air-quality-api.open-meteo.com/v1/air-quality?\(coords)&current=us_aqi")
        else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let forecastData = URLSession.shared.data(from: forecastURL).0
            // Air quality is a bonus: its failure mustn't cost the weather.
            async let airData = wantsAQI ? try? URLSession.shared.data(from: airURL).0 : nil
            let forecast = try JSONDecoder().decode(Forecast.self, from: try await forecastData)
            let aqi = await airData.flatMap { try? JSONDecoder().decode(AirQuality.self, from: $0) }?.current.us_aqi
            let now = Date()
            var hours: [HourForecast] = []
            if let hourly = forecast.hourly {
                for (index, time) in hourly.time.enumerated() where time > now.timeIntervalSince1970 {
                    guard index < hourly.temperature_2m.count, index < hourly.weather_code.count else { break }
                    let isDay = index < hourly.is_day.count ? hourly.is_day[index] == 1 : true
                    hours.append(HourForecast(date: Date(timeIntervalSince1970: time), temperature: hourly.temperature_2m[index],
                                              code: hourly.weather_code[index], isDay: isDay))
                    if hours.count == 4 { break }
                }
            }
            snapshot = WeatherSnapshot(
                temperature: forecast.current.temperature_2m,
                code: forecast.current.weather_code,
                isDay: forecast.current.is_day == 1,
                aqi: aqi.map { Int($0.rounded()) },
                sunrises: forecast.daily.sunrise.map { Date(timeIntervalSince1970: $0) },
                sunsets: forecast.daily.sunset.map { Date(timeIntervalSince1970: $0) },
                high: forecast.daily.temperature_2m_max?.first,
                low: forecast.daily.temperature_2m_min?.first,
                hourly: hours
            )
            lastFetch = Date()
            lastError = nil
        } catch {
            lastError = ConnectivityService.shared.isOnline
                ? "Couldn't load the weather: \(error.localizedDescription)"
                : "No Internet Connection"
        }
    }

    // MARK: City search

    /// Open-Meteo's geocoding: up to eight places matching `query`.
    public nonisolated static func searchPlaces(_ query: String) async throws -> [WeatherPlace] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return [] }
        var comps = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        comps.queryItems = [
            URLQueryItem(name: "name", value: trimmed),
            URLQueryItem(name: "count", value: "8"),
            URLQueryItem(name: "language", value: Locale.current.language.languageCode?.identifier ?? "en"),
            URLQueryItem(name: "format", value: "json"),
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        struct Results: Decodable { let results: [WeatherPlace]? }
        return try JSONDecoder().decode(Results.self, from: data).results ?? []
    }

    /// Settings › Weather location: a fixed place picked from the search.
    public func choose(_ place: WeatherPlace) {
        let state = AppState.shared
        state.weatherPlaceName = place.name
        state.weatherPlaceLatitude = (place.latitude * 100).rounded() / 100
        state.weatherPlaceLongitude = (place.longitude * 100).rounded() / 100
        if state.weatherLocationMode != .fixed {
            state.weatherLocationMode = .fixed
        } else {
            locationSettingsChanged()
        }
    }

    // MARK: Open-Meteo payloads

    private struct Forecast: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
            let is_day: Int
        }
        struct Hourly: Decodable {
            let time: [TimeInterval]
            let temperature_2m: [Double]
            let weather_code: [Int]
            let is_day: [Int]
        }
        struct Daily: Decodable {
            let sunrise: [TimeInterval]
            let sunset: [TimeInterval]
            let temperature_2m_max: [Double]?
            let temperature_2m_min: [Double]?
        }
        let current: Current
        let hourly: Hourly?
        let daily: Daily
    }

    private struct AirQuality: Decodable {
        struct Current: Decodable { let us_aqi: Double? }
        let current: Current
    }
}

extension WeatherService: CLLocationManagerDelegate {
    // CoreLocation calls these on the thread the manager was made on (main);
    // copy out plain values before hopping so nothing non-Sendable crosses.
    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            let service = WeatherService.shared
            service.authorization = status
            if service.isRunning, service.isAuthorized, service.snapshot == nil { service.refresh(force: true) }
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        let lat = coordinate.latitude, lon = coordinate.longitude
        Task { @MainActor in WeatherService.shared.located(latitude: lat, longitude: lon) }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in WeatherService.shared.lastError = "Couldn't find this Mac's location: \(message)" }
    }
}
