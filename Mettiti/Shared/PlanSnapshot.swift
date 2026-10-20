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

    /// Whether this plan was generated on the same day as `now` in `calendar`'s time zone.
    /// Production passes the device's current calendar, so "today" is the device's local day.
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

    /// The Plan Window chosen in Settings, stored in `defaults` (the App Group's in production).
    static func storedPlanWindow(in defaults: UserDefaults) -> StoredPreference<PlanWindow> {
        .rawValue("planWindow", in: defaults)
    }

    /// The Settings default Plan Window, which the widgets and background refresh follow.
    static func loadPlanWindow(from defaults: UserDefaults = appGroupDefaults) -> PlanWindow {
        storedPlanWindow(in: defaults).load() ?? .settingsDefault
    }
}
