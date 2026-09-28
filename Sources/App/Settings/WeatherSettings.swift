import SwiftUI

/// Settings › Droplets › Weather.
@MainActor
public final class WeatherSettings: SettingsStore {
    public static let shared = WeatherSettings()

    /// The UserDefaults keys behind this store's properties.
    nonisolated static let keys: [String] = [
        "weatherStyle", "weatherLocationMode", "weatherPlaceName", "weatherPlaceLatitude",
        "weatherPlaceLongitude", "weatherRefreshMinutes", "weatherShowsAQI", "weatherShowsSun"
    ]

    @AppStorage("weatherStyle") public var style: WeatherStyle = .liquidGlass
    @AppStorage("weatherLocationMode") public var locationMode: WeatherLocationMode = .automatic {
        didSet { WeatherService.shared.locationSettingsChanged() }
    }
    @AppStorage("weatherPlaceName") public var placeName: String = ""
    @AppStorage("weatherPlaceLatitude") public var placeLatitude: Double = 0
    @AppStorage("weatherPlaceLongitude") public var placeLongitude: Double = 0
    /// Minutes between refreshes.
    @AppStorage("weatherRefreshMinutes") public var refreshMinutes: Int = 30 {
        didSet { WeatherService.shared.intervalChanged() }
    }
    @AppStorage("weatherShowsAQI") public var showsAQI: Bool = true
    @AppStorage("weatherShowsSun") public var showsSun: Bool = true

    private init() { super.init(keys: Self.keys) }
}
