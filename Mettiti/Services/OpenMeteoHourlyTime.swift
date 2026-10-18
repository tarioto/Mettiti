import Foundation

enum OpenMeteoHourlyTime {
    /// Parses Open-Meteo's hourly timestamps ("2026-10-25T03:00"). With `timezone=auto` they're
    /// local times at the response's `utc_offset_seconds`, which stays fixed for the whole
    /// response even past a DST change, so they're read at that offset, not the zone's rules.
    static func parseStrategy(utcOffsetSeconds: Int) -> Date.ParseStrategy {
        Date.ParseStrategy(
            format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)T\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: utcOffsetSeconds) ?? .gmt,
            calendar: Calendar(identifier: .gregorian)
        )
    }
}
