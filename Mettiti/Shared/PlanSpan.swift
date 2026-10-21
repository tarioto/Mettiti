import Foundation

/// The stretch of time a plan covers: its Plan Window, worked out from when the plan was made.
struct PlanSpan: Codable, Sendable, Equatable {
    let window: PlanWindow
    let interval: DateInterval
    /// The forecast location's, so times read as they do there.
    let timeZone: TimeZone

    init(window: PlanWindow, startingAt now: Date, timeZone: TimeZone) {
        self.window = window
        interval = window.span(startingAt: now, in: timeZone)
        self.timeZone = timeZone
    }

    /// The window and its times as VoiceOver should read them, e.g. "Next 3 hours, from 2:20 PM to 5:20 PM".
    func accessibilityLabel(locale: Locale = .autoupdatingCurrent) -> String {
        String(
            localized: "\(window.name(locale: locale)), from \(time(interval.start, locale: locale)) to \(time(interval.end, locale: locale))",
            table: "Shared",
            locale: locale,
            comment: "VoiceOver label for the plan card title; the arguments are the Plan Window, e.g. Next 3 hours, its start time and its end time"
        )
    }

    /// The window's local times, e.g. "2:20 – 5:20 PM": in the plan card's title, under the main
    /// screen's Plan Window menu, which already names the window.
    ///
    /// Within one day the interval format shares what it can ("2:20 – 5:20 PM"); across midnight
    /// it would add both dates, so the two times are written out instead.
    func timeRange(locale: Locale = .autoupdatingCurrent) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // Ending at midnight still counts as crossing it: the end is on the next day.
        guard calendar.isDate(interval.start, inSameDayAs: interval.end) else {
            return String(
                localized: "\(time(interval.start, locale: locale)) – \(time(interval.end, locale: locale))",
                table: "Shared",
                locale: locale,
                comment: "A time range that crosses midnight, e.g. 2:20 PM – 2:20 AM"
            )
        }
        let style = Date.IntervalFormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone)
        return (interval.start..<interval.end).formatted(style)
    }

    private func time(_ date: Date, locale: Locale) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone))
    }
}
