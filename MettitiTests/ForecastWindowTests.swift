import Foundation
import Testing
@testable import Mettiti

struct ForecastWindowTests {
    @Test func windowAcrossMidnightCoversTheHoursInProgressThroughTheSpansEnd() {
        let forecast = HourlyForecast(timeZone: pacific, points: [
            hour("2026-10-10T04:00:00Z", temperature: 60, rain: 10), // 9 PM, before the span
            hour("2026-10-10T05:00:00Z", temperature: 58, rain: 20), // 10 PM, in progress
            hour("2026-10-10T06:00:00Z", temperature: 55, rain: 60), // 11 PM
            hour("2026-10-10T07:00:00Z", temperature: 52, rain: 30), // midnight
            hour("2026-10-10T08:00:00Z", temperature: 50, rain: 0),  // 1 AM, in progress at the end
            hour("2026-10-10T09:00:00Z", temperature: 45, rain: 90), // 2 AM, after the span
        ])
        let now = date("2026-10-10T05:30:00Z") // 10:30 PM PDT

        let window = ForecastWindow(forecast: forecast, span: PlanWindow.restOfDay.span(startingAt: now, in: pacific))

        #expect(window.hours.map(\.meanF) == [58, 55, 52, 50])
        #expect(window.high?.date == date("2026-10-10T05:00:00Z"))
        #expect(window.low?.date == date("2026-10-10T08:00:00Z"))
        #expect(window.wettest?.date == date("2026-10-10T06:00:00Z"))
    }

    @Test func windowAcrossSunsetOnlyCountsUVWhileTheSunIsUp() {
        let forecast = HourlyForecast(
            timeZone: pacific,
            points: [
                hour("2026-10-09T23:00:00Z", uv: 5, daylight: true),  // 4 PM
                hour("2026-10-10T00:00:00Z", uv: 3, daylight: true),  // 5 PM
                hour("2026-10-10T01:00:00Z", uv: 1, daylight: true),  // 6 PM
                hour("2026-10-10T02:00:00Z", uv: 6, daylight: false), // 7 PM, a stray reading after dark
            ],
            sunEvents: [
                SunEvent(kind: .sunrise, date: date("2026-10-09T14:10:00Z")),
                SunEvent(kind: .sunset, date: date("2026-10-10T01:30:00Z")),  // 6:30 PM
                SunEvent(kind: .sunrise, date: date("2026-10-10T14:11:00Z")),
            ]
        )
        let span = DateInterval(start: date("2026-10-09T23:10:00Z"), end: date("2026-10-10T03:00:00Z"))

        let window = ForecastWindow(forecast: forecast, span: span)

        #expect(window.isDaylightAtStart == true)
        #expect(window.sunEvents == [SunEvent(kind: .sunset, date: date("2026-10-10T01:30:00Z"))])
        #expect(window.peakDaylightUV?.uvIndex == 5)
        #expect(window.hasMeaningfulDaylightUV)
    }

    @Test func windowAfterSunsetHasNoMeaningfulUV() {
        let forecast = HourlyForecast(timeZone: pacific, points: [
            hour("2026-10-10T02:00:00Z", uv: 0, daylight: false), // 7 PM
            hour("2026-10-10T03:00:00Z", uv: 4, daylight: false), // 8 PM, a stray reading after dark
        ])
        let span = DateInterval(start: date("2026-10-10T02:15:00Z"), end: date("2026-10-10T05:15:00Z"))

        let window = ForecastWindow(forecast: forecast, span: span)

        #expect(window.isDaylightAtStart == false)
        #expect(window.peakDaylightUV == nil)
        #expect(!window.hasMeaningfulDaylightUV)
    }

    @Test(arguments: [
        ("2026-10-10T01:20:00Z", true),  // 6:20 PM, before the 6:30 PM sunset
        ("2026-10-10T01:40:00Z", false), // 6:40 PM, after it, though the 6 PM hour counts as daylight
    ])
    func whetherTheSunIsUpAtTheStartFollowsTheLastSunriseOrSunset(start: String, isUp: Bool) {
        let forecast = HourlyForecast(
            timeZone: pacific,
            points: [hour("2026-10-10T01:00:00Z", uv: 1, daylight: true)],
            sunEvents: [
                SunEvent(kind: .sunrise, date: date("2026-10-09T14:10:00Z")),
                SunEvent(kind: .sunset, date: date("2026-10-10T01:30:00Z")),
            ]
        )
        let span = DateInterval(start: date(start), duration: 3 * 60 * 60)

        let window = ForecastWindow(forecast: forecast, span: span)

        #expect(window.isDaylightAtStart == isUp)
    }

    private func hour(_ iso: String, temperature: Double = 64, rain: Int? = nil, uv: Double? = nil, daylight: Bool? = nil) -> HourlyTemperaturePoint {
        HourlyTemperaturePoint(
            date: date(iso),
            meanF: temperature,
            minF: temperature,
            maxF: temperature,
            precipitationProbability: rain,
            uvIndex: uv,
            isDaylight: daylight
        )
    }
}
