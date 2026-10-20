import Foundation
import Testing
@testable import Mettiti

struct WindowSummaryTests {
    // MARK: Summing up the weather

    @Test func summarizesTheHourlyForecastOverTheSpan() {
        let forecast = HourlyForecast(
            timeZone: pacific,
            points: [
                hour("2026-10-09T22:00:00Z", temperature: 90, rain: 90, uv: 9, condition: 95, daylight: true), // 3 PM, before the span
                hour("2026-10-09T23:00:00Z", temperature: 66, rain: 10, uv: 5, condition: 2, daylight: true),  // 4 PM
                hour("2026-10-10T00:00:00Z", temperature: 64, rain: 40, uv: 3, condition: 61, daylight: true), // 5 PM
                hour("2026-10-10T01:00:00Z", temperature: 60, rain: 20, uv: 1, condition: 3, daylight: true),  // 6 PM
                hour("2026-10-10T02:00:00Z", temperature: 57, rain: 0, uv: 7, condition: 63, daylight: false), // 7 PM, UV after dark
            ],
            sunEvents: [
                SunEvent(kind: .sunrise, date: date("2026-10-09T14:10:00Z")),
                SunEvent(kind: .sunset, date: date("2026-10-10T01:30:00Z")), // 6:30 PM
            ]
        )
        let span = PlanSpan(window: .threeHours, startingAt: date("2026-10-09T23:10:00Z"), timeZone: pacific) // 4:10 – 7:10 PM

        let summary = WindowSummary(weather: .sunnyDay, hourly: forecast, span: span)

        #expect(summary == WindowSummary(
            window: .threeHours,
            coversHours: true,
            highF: 66,
            lowF: 57,
            precipitationProbability: 40,
            uvIndex: 5,
            conditionCode: 61, // two rainy hours outnumber each other kind
            isDaylightAtStart: true,
            sunEvents: [.sunset]
        ))
    }

    @Test(arguments: [
        ("2026-10-09T23:10:00Z", true), // 4:10 PM
        ("2026-10-10T03:10:00Z", false), // 8:10 PM
    ])
    func withoutAnHourlyForecastSummarizesTheWholeDayAndAssumesItsDarkAtNight(start: String, isDaylight: Bool) {
        let span = PlanSpan(window: .threeHours, startingAt: date(start), timeZone: pacific)

        let summary = WindowSummary(weather: .sunnyDay, hourly: nil, span: span)

        #expect(summary == WindowSummary(
            window: .threeHours,
            coversHours: false,
            highF: 75,
            lowF: 55,
            precipitationProbability: 5,
            uvIndex: 7,
            conditionCode: 0,
            isDaylightAtStart: isDaylight,
            sunEvents: []
        ))
    }

    // MARK: Comparing summaries

    @Test func identicalWeatherIsNotAMeaningfulChange() {
        #expect(!baseline.differsMeaningfully(from: baseline))
    }

    @Test(arguments: [5.4, -5.4])
    func highMovingByThreeDegreesCelsiusIsAMeaningfulChange(delta: Double) {
        var changed = baseline
        changed.highF += delta
        #expect(changed.differsMeaningfully(from: baseline))
    }

    @Test(arguments: [5.4, -5.4])
    func lowMovingByThreeDegreesCelsiusIsAMeaningfulChange(delta: Double) {
        var changed = baseline
        changed.lowF += delta
        #expect(changed.differsMeaningfully(from: baseline))
    }

    @Test(arguments: [5.3, -5.3])
    func highAndLowMovingByJustUnderThreeDegreesCelsiusIsNot(delta: Double) {
        var changed = baseline
        changed.highF += delta
        changed.lowF += delta
        #expect(!changed.differsMeaningfully(from: baseline))
    }

    @Test(arguments: [
        (29, 30), (30, 29), // about 30%
        (59, 60), (60, 59), // about 60%
        (10, 75),           // across both
    ])
    func chanceOfRainCrossingThirtyOrSixtyPercentIsAMeaningfulChange(before: Int, after: Int) {
        var old = baseline
        old.precipitationProbability = before
        var new = baseline
        new.precipitationProbability = after
        #expect(new.differsMeaningfully(from: old))
    }

    @Test(arguments: [(0, 29), (30, 59), (60, 100), (29, 0)])
    func chanceOfRainMovingWithoutCrossingThirtyOrSixtyPercentIsNot(before: Int, after: Int) {
        var old = baseline
        old.precipitationProbability = before
        var new = baseline
        new.precipitationProbability = after
        #expect(!new.differsMeaningfully(from: old))
    }

    @Test(arguments: [
        (2.9, 3.0), (3.0, 2.9), // low / moderate
        (5.9, 6.0), (6.0, 5.9), // moderate / high
        (1.0, 9.0),
    ])
    func uvChangingBandIsAMeaningfulChange(before: Double, after: Double) {
        var old = baseline
        old.uvIndex = before
        var new = baseline
        new.uvIndex = after
        #expect(new.differsMeaningfully(from: old))
    }

    @Test(arguments: [(0.0, 2.9), (3.0, 5.9), (6.0, 11.0)])
    func uvMovingWithinItsBandIsNot(before: Double, after: Double) {
        var old = baseline
        old.uvIndex = before
        var new = baseline
        new.uvIndex = after
        #expect(!new.differsMeaningfully(from: old))
    }

    @Test func conditionChangingIsAMeaningfulChange() {
        var changed = baseline
        changed.conditionCode = 61 // rain
        #expect(changed.differsMeaningfully(from: baseline))
    }

    @Test func conditionChangingWithinTheSameKindOfWeatherIsNot() {
        var old = baseline
        old.conditionCode = 0 // clear sky
        var new = baseline
        new.conditionCode = 1 // mainly clear
        #expect(!new.differsMeaningfully(from: old))
    }

    @Test func windowNowCrossingSunsetIsAMeaningfulChange() {
        var changed = baseline
        changed.sunEvents = [.sunset]
        #expect(changed.differsMeaningfully(from: baseline))
        #expect(baseline.differsMeaningfully(from: changed))
    }

    @Test func windowNowCrossingSunriseIsAMeaningfulChange() {
        var old = baseline
        old.isDaylightAtStart = false
        var new = old
        new.sunEvents = [.sunrise]
        #expect(new.differsMeaningfully(from: old))
    }

    @Test func dayTurningToNightIsAMeaningfulChange() {
        var night = baseline
        night.isDaylightAtStart = false
        #expect(night.differsMeaningfully(from: baseline))
        #expect(baseline.differsMeaningfully(from: night))
    }

    @Test func gainingOrLosingTheHourlyForecastIsAMeaningfulChange() {
        var wholeDay = baseline
        wholeDay.coversHours = false
        #expect(wholeDay.differsMeaningfully(from: baseline))
    }

    @Test func anotherPlanWindowIsAMeaningfulChange() {
        var changed = baseline
        changed.window = .sixHours
        #expect(changed.differsMeaningfully(from: baseline))
    }
}

/// Mild, dry, low UV, partly cloudy, sun up all window.
private let baseline = WindowSummary(
    window: .threeHours,
    coversHours: true,
    highF: 64,
    lowF: 58,
    precipitationProbability: 10,
    uvIndex: 2,
    conditionCode: 2,
    isDaylightAtStart: true,
    sunEvents: []
)

private extension DailyWeather {
    static let sunnyDay = DailyWeather(
        date: sunnyDayDate,
        highTemperatureF: 75,
        lowTemperatureF: 55,
        precipitationProbability: 5,
        uvIndex: 7,
        windSpeedMph: 4,
        conditionCode: 0,
        conditionDescription: "Clear sky"
    )
}

private func hour(_ iso: String, temperature: Double, rain: Int, uv: Double, condition: Int, daylight: Bool) -> HourlyTemperaturePoint {
    HourlyTemperaturePoint(
        date: date(iso),
        meanF: temperature,
        minF: temperature,
        maxF: temperature,
        precipitationProbability: rain,
        uvIndex: uv,
        conditionCode: condition,
        isDaylight: daylight
    )
}

private let sunnyDayDate = date("2026-10-09T07:00:00Z")
