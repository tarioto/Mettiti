import Foundation

/// The stretch of the hourly forecast that a plan covers, summarized for the outfit advice.
struct ForecastWindow {
    static let minimumLength: TimeInterval = 3 * 60 * 60
    /// From this UV index on, sun protection is worth bringing up (the WHO's "moderate").
    static let meaningfulUVIndex: Double = 3

    let span: DateInterval
    let timeZone: TimeZone
    /// The hours that overlap the span, including the ones in progress at its start and end.
    let hours: [HourlyTemperaturePoint]
    /// The sunrises and sunsets within the span, in order.
    let sunEvents: [SunEvent]
    /// Whether the sun is up at the span's start: after a sunrise and before the next sunset,
    /// or failing those, the first hour's own daylight flag. Nil when the source didn't say.
    let isDaylightAtStart: Bool?

    init(forecast: HourlyForecast, span: DateInterval) {
        self.span = span
        timeZone = forecast.timeZone
        hours = forecast.points.filter { $0.date < span.end && $0.date.addingTimeInterval(60 * 60) > span.start }
        let allSunEvents = (forecast.sunEvents ?? []).sorted { $0.date < $1.date }
        sunEvents = allSunEvents.filter { span.contains($0.date) }
        if let lastEvent = allSunEvents.last(where: { $0.date <= span.start }) {
            isDaylightAtStart = lastEvent.kind == .sunrise
        } else {
            isDaylightAtStart = hours.first?.isDaylight
        }
    }

    /// From `now` until the end of the day in `timeZone`, but at least 3 hours, so a plan made
    /// late in the evening still covers the next few hours past midnight.
    static func span(startingAt now: Date, in timeZone: TimeZone) -> DateInterval {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let endOfDay = calendar.dateInterval(of: .day, for: now)?.end ?? now
        return DateInterval(start: now, end: max(endOfDay, now.addingTimeInterval(minimumLength)))
    }

    var high: HourlyTemperaturePoint? { hours.max { $0.meanF < $1.meanF } }
    var low: HourlyTemperaturePoint? { hours.min { $0.meanF < $1.meanF } }

    /// The hour with the highest chance of rain.
    var wettest: HourlyTemperaturePoint? { Self.peak(of: \.precipitationProbability, in: hours) }

    var windiest: HourlyTemperaturePoint? { Self.peak(of: \.windSpeedMph, in: hours) }

    var hasDaylight: Bool { hours.contains { $0.isDaylight == true } }

    /// The daylight hour with the highest UV index. Hours after dark don't count, whatever
    /// UV they report.
    var peakDaylightUV: HourlyTemperaturePoint? {
        Self.peak(of: \.uvIndex, in: hours.filter { $0.isDaylight == true })
    }

    var hasMeaningfulDaylightUV: Bool {
        (peakDaylightUV?.uvIndex ?? 0) >= Self.meaningfulUVIndex
    }

    /// The first hour with the highest value, skipping hours without one.
    private static func peak<Value: Comparable>(of value: KeyPath<HourlyTemperaturePoint, Value?>, in hours: [HourlyTemperaturePoint]) -> HourlyTemperaturePoint? {
        hours
            .compactMap { hour in hour[keyPath: value].map { (hour, $0) } }
            .max { $0.1 < $1.1 }?
            .0
    }
}
