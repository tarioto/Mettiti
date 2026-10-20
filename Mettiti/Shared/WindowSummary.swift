import Foundation

/// The weather over a plan's span that the outfit advice was based on, kept so a refetch can
/// tell whether the advice is still right (#99). Only changes that would change the advice
/// count: see `differsMeaningfully(from:)`.
struct WindowSummary: Codable, Sendable, Equatable {
    /// About 3°C, in Fahrenheit degrees.
    static let meaningfulTemperatureChangeF: Double = 5.4
    /// Chances of rain at which the advice changes, e.g. from nothing to an umbrella.
    static let rainThresholds = [30, 60]
    /// From this UV index on, it's high or above (the WHO's "high").
    static let highUVIndex: Double = 6
    /// UV indices at which the advice changes: low below the first, moderate, high and above.
    static let uvThresholds = [ForecastWindow.meaningfulUVIndex, highUVIndex]

    var window: PlanWindow
    /// Whether this sums up an hourly forecast for the span, or the whole day without one.
    var coversHours: Bool
    var highF: Double
    var lowF: Double
    /// The highest chance of rain.
    var precipitationProbability: Int
    /// The highest UV index while the sun is up.
    var uvIndex: Double
    /// The WMO code of the window's most common kind of weather.
    var conditionCode: Int
    /// Whether the sun is up at the span's start. Nil when the source didn't say.
    var isDaylightAtStart: Bool?
    /// The sunrises and sunsets within the span, in order.
    var sunEvents: [SunEvent.Kind]

    /// Sums up `span` of the hourly forecast, or without one (or with no hours in the span), the
    /// whole day: the same weather the outfit advice is written from.
    init(weather: DailyWeather, hourly: HourlyForecast?, span: PlanSpan) {
        window = span.window
        let forecastWindow = hourly.map { ForecastWindow(forecast: $0, span: span.interval) }
        guard let forecastWindow, let high = forecastWindow.high, let low = forecastWindow.low else {
            coversHours = false
            highF = weather.highTemperatureF
            lowF = weather.lowTemperatureF
            precipitationProbability = weather.precipitationProbability
            uvIndex = weather.uvIndex
            conditionCode = weather.conditionCode
            isDaylightAtStart = !ForecastWindow.assumesDark(at: span.interval.start, in: span.timeZone)
            sunEvents = []
            return
        }
        coversHours = true
        highF = high.meanF
        lowF = low.meanF
        precipitationProbability = forecastWindow.wettest?.precipitationProbability ?? 0
        uvIndex = forecastWindow.peakDaylightUV?.uvIndex ?? 0
        conditionCode = Self.mostCommonCondition(in: forecastWindow.hours) ?? weather.conditionCode
        isDaylightAtStart = forecastWindow.isDaylightAtStart
        sunEvents = forecastWindow.sunEvents.map(\.kind)
    }

    init(window: PlanWindow, coversHours: Bool, highF: Double, lowF: Double, precipitationProbability: Int, uvIndex: Double, conditionCode: Int, isDaylightAtStart: Bool?, sunEvents: [SunEvent.Kind]) {
        self.window = window
        self.coversHours = coversHours
        self.highF = highF
        self.lowF = lowF
        self.precipitationProbability = precipitationProbability
        self.uvIndex = uvIndex
        self.conditionCode = conditionCode
        self.isDaylightAtStart = isDaylightAtStart
        self.sunEvents = sunEvents
    }

    /// Whether advice based on `other` would be out of date for this weather: the window now
    /// crosses a sunrise or sunset it didn't (or the other way round), day turned to night (or
    /// night to day), the UV band changed, the chance of rain crossed about 30% or 60%, the high
    /// or low moved by about 3°C, or the kind of weather changed. Advice for another Plan Window,
    /// or written with (or without) an hourly forecast when this isn't, is out of date too.
    func differsMeaningfully(from other: WindowSummary) -> Bool {
        window != other.window
            || coversHours != other.coversHours
            || isDaylightAtStart != other.isDaylightAtStart
            || sunEvents != other.sunEvents
            || Self.band(of: uvIndex, at: Self.uvThresholds) != Self.band(of: other.uvIndex, at: Self.uvThresholds)
            || Self.band(of: precipitationProbability, at: Self.rainThresholds) != Self.band(of: other.precipitationProbability, at: Self.rainThresholds)
            || Self.movedMeaningfully(highF, other.highF)
            || Self.movedMeaningfully(lowF, other.lowF)
            || WMOWeatherCode.symbolName(for: conditionCode) != WMOWeatherCode.symbolName(for: other.conditionCode)
    }

    /// The first code of the kind of weather (as its symbol shows it) most hours have; ties go
    /// to the kind that comes first. Nil when no hour has a code.
    private static func mostCommonCondition(in hours: [HourlyTemperaturePoint]) -> Int? {
        let codes = hours.compactMap(\.conditionCode)
        let kinds = codes.map(WMOWeatherCode.symbolName(for:))
        let counts = Dictionary(kinds.map { ($0, 1) }, uniquingKeysWith: +)
        guard let topCount = counts.values.max() else { return nil }
        return zip(codes, kinds).first { counts[$0.1] == topCount }?.0
    }

    /// How many of `thresholds` (in ascending order) `value` is at or above.
    private static func band<Value: Comparable>(of value: Value, at thresholds: [Value]) -> Int {
        thresholds.filter { value >= $0 }.count
    }

    private static func movedMeaningfully(_ temperatureF: Double, _ otherF: Double) -> Bool {
        // A little slack so 3°C written in Fahrenheit still counts after rounding errors.
        abs(temperatureF - otherF) >= meaningfulTemperatureChangeF - 0.001
    }
}
