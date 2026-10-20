import Foundation

/// How far ahead from now the outfit advice covers, chosen in Settings.
enum PlanWindow: String, Codable, CaseIterable, Identifiable, Sendable {
    case oneHour
    case threeHours
    case sixHours
    case twelveHours
    case restOfDay

    var id: String { rawValue }

    /// The Settings default until the user picks one.
    static let settingsDefault: PlanWindow = .restOfDay

    /// The window as a heading, e.g. "Next 3 hours".
    func name(locale: Locale = .autoupdatingCurrent) -> String {
        switch self {
        case .oneHour: return String(localized: "Next hour", table: "Shared", locale: locale, comment: "Plan Window heading for a one-hour window")
        case .threeHours: return String(localized: "Next 3 hours", table: "Shared", locale: locale, comment: "Plan Window heading for a three-hour window")
        case .sixHours: return String(localized: "Next 6 hours", table: "Shared", locale: locale, comment: "Plan Window heading for a six-hour window")
        case .twelveHours: return String(localized: "Next 12 hours", table: "Shared", locale: locale, comment: "Plan Window heading for a twelve-hour window")
        case .restOfDay: return String(localized: "Rest of day", table: "Shared", locale: locale, comment: "Plan Window stop: from now until midnight")
        }
    }

    /// "Rest of day" never covers less than this, so a plan made late in the evening still
    /// covers the next few hours past midnight.
    static let restOfDayMinimumLength: TimeInterval = 3 * 60 * 60

    /// From `now` for the window's length; fixed windows cross midnight freely. "Rest of day"
    /// runs until midnight in `timeZone`, but at least `restOfDayMinimumLength`.
    func span(startingAt now: Date, in timeZone: TimeZone) -> DateInterval {
        let hours: Double
        switch self {
        case .oneHour: hours = 1
        case .threeHours: hours = 3
        case .sixHours: hours = 6
        case .twelveHours: hours = 12
        case .restOfDay:
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let endOfDay = calendar.dateInterval(of: .day, for: now)?.end ?? now
            return DateInterval(start: now, end: max(endOfDay, now.addingTimeInterval(Self.restOfDayMinimumLength)))
        }
        return DateInterval(start: now, duration: hours * 60 * 60)
    }

    /// Automatic refreshes never come closer together than this, whatever the window. Each one
    /// reruns the on-device model.
    static let minimumRefreshInterval: TimeInterval = 30 * 60

    /// How long after its last load a plan for this window goes stale. Short windows run out
    /// quickly and their weather is the next hour or two, so they keep up with the time.
    var staleAfter: TimeInterval {
        let minutes: Double
        switch self {
        case .oneHour: minutes = 30
        case .threeHours: minutes = 60
        case .sixHours: minutes = 120
        case .twelveHours, .restOfDay: minutes = 180
        }
        return max(minutes * 60, Self.minimumRefreshInterval)
    }

    /// Whether a plan last loaded at `lastLoadedAt` should be refreshed at `now`: once it's from
    /// an earlier day in `calendar`, or `staleAfter` has passed.
    func isPlanStale(lastLoadedAt: Date, now: Date, calendar: Calendar) -> Bool {
        !calendar.isDate(lastLoadedAt, inSameDayAs: now) || now.timeIntervalSince(lastLoadedAt) >= staleAfter
    }
}
