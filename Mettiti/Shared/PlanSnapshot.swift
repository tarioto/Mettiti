import Foundation

struct PlanSnapshot: Codable, Sendable {
    let weather: DailyWeather
    /// Nil when the on-device model couldn't make suggestions; widgets then show weather only.
    let recommendation: OutfitRecommendation?
    let generatedAt: Date
    /// Optional so snapshots saved before providers existed still decode.
    var provider: WeatherProvider?
    /// The location the plan is for, so the app only shows it on launch for that same
    /// location (#22). Nil for snapshots saved before it was stored.
    var location: LocationSelection?
    /// Nil when saved before it was stored, or when the hourly fetch failed.
    var hourly: HourlyForecast?
    /// What the plan covers. Nil for plans saved before Plan Windows, which all cover the rest
    /// of the day.
    var span: PlanSpan?
    /// The weather over the span that `recommendation` was written for, which a later refresh
    /// compares with its own to decide whether to remake the outfit (#99). It stays as is when a
    /// refresh keeps the outfit, so small changes that add up still count. Nil without a
    /// recommendation, and in plans saved before it was stored, which are always remade.
    var adviceBasis: WindowSummary?
    /// The language `recommendation` was written in (`OutfitAdvisor.responseLanguage()`), so a
    /// refresh remakes the outfit when the app's language has changed since. Nil without a
    /// recommendation, and in plans saved before it was stored, which are remade once.
    var adviceLanguage: String?
    /// Where the plan was made, so a Current Location plan shown at launch has its map and city
    /// before a new fix arrives. Nil when saved before it was stored.
    var place: SavedPlace?
}

/// The coordinate a plan was made for and its city's name, if it was known.
struct SavedPlace: Codable, Equatable, Sendable {
    var name: String?
    var latitude: Double
    var longitude: Double
}

extension PlanSnapshot {
    static let placeholder = PlanSnapshot(
        weather: .placeholder,
        recommendation: .placeholder,
        generatedAt: .now,
        provider: .apple,
        span: PlanSpan(window: .threeHours, startingAt: .now, timeZone: .current)
    )

    /// The plan's Plan Window; plans saved before there was a choice covered the rest of the day.
    var planWindow: PlanWindow {
        span?.window ?? .restOfDay
    }

    /// `calendar` in the forecast location's time zone, so "today", midnight and the hour read as
    /// they do there. Plans that didn't record the time zone keep `calendar`'s.
    func locationCalendar(fallback calendar: Calendar) -> Calendar {
        guard let timeZone = span?.timeZone ?? hourly?.timeZone else { return calendar }
        var locationCalendar = calendar
        locationCalendar.timeZone = timeZone
        return locationCalendar
    }

    /// Whether this plan was generated on the same day as `now` in `calendar`'s time zone.
    /// The app passes the selected location's calendar (the device's when none is selected), and the
    /// background refresh passes `locationCalendar(fallback:)`, so "today" is the location's day.
    func isFromToday(now: Date, calendar: Calendar) -> Bool {
        calendar.isDate(generatedAt, inSameDayAs: now)
    }
}

enum SharedStore {
    /// Read from Info.plist because Debug builds use a separate app group (see project.yml).
    static let appGroupID = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String
        ?? "group.com.timarioto.Mettiti"
    private static let snapshotKey = "latestPlanSnapshot"

    /// The App Group's defaults, shared with the widgets. Falls back to the app's own defaults
    /// if the group isn't available.
    static var appGroupDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func save(_ snapshot: PlanSnapshot) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    static func load() -> PlanSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return nil }
        guard let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(PlanSnapshot.self, from: data)
    }

    static func saveTemperatureUnit(_ unit: TemperatureUnit) {
        storedTemperatureUnit?.save(unit)
    }

    static func loadTemperatureUnit() -> TemperatureUnit {
        storedTemperatureUnit?.load() ?? .system
    }

    private static var storedTemperatureUnit: StoredPreference<TemperatureUnit>? {
        UserDefaults(suiteName: appGroupID).map { .rawValue("temperatureUnit", in: $0) }
    }

    /// A copy of the location chosen in Settings, which the widgets can't read from the app's own
    /// defaults. `LocationPreferenceStore` keeps the original.
    static func storedLocationSelection(in defaults: UserDefaults) -> StoredPreference<LocationSelection> {
        .json("locationSelection", in: defaults)
    }

    static func saveLocationSelection(_ selection: LocationSelection, to defaults: UserDefaults = appGroupDefaults) {
        storedLocationSelection(in: defaults).save(selection)
    }

    /// Nil until the app has shared one.
    static func loadLocationSelection(from defaults: UserDefaults = appGroupDefaults) -> LocationSelection? {
        storedLocationSelection(in: defaults).load()
    }

    /// The Plan Window chosen in Settings, stored in `defaults` (the App Group's in production).
    static func storedPlanWindow(in defaults: UserDefaults) -> StoredPreference<PlanWindow> {
        .rawValue("planWindow", in: defaults)
    }

    /// The Settings default Plan Window, which the widgets and background refresh follow.
    static func loadPlanWindow(from defaults: UserDefaults = appGroupDefaults) -> PlanWindow {
        storedPlanWindow(in: defaults).load() ?? .settingsDefault
    }
}
