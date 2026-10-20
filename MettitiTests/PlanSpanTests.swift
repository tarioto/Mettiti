import Foundation
import Testing
@testable import Mettiti

struct PlanSpanTests {
    private let afternoon = date("2026-10-09T21:20:00Z") // 2:20 PM PDT
    private let us = Locale(identifier: "en_US")

    @Test func spanStartsWhenThePlanIsMadeAndRunsTheWindow() {
        let span = PlanSpan(window: .threeHours, startingAt: afternoon, timeZone: pacific)

        #expect(span.interval == PlanWindow.threeHours.span(startingAt: afternoon, in: pacific))
    }

    @Test(arguments: [
        (PlanWindow.oneHour, "2:20 – 3:20 PM"),
        (PlanWindow.threeHours, "2:20 – 5:20 PM"),
        (PlanWindow.twelveHours, "2:20 PM – 2:20 AM"),
        (PlanWindow.restOfDay, "2:20 PM – 12:00 AM"),
    ])
    func timeRangeShowsTheWindowsLocalTimes(window: PlanWindow, range: String) {
        let span = PlanSpan(window: window, startingAt: afternoon, timeZone: pacific)

        #expect(normalized(span.timeRange(locale: us)) == range)
    }

    @Test func timeRangeUsesTheForecastLocationsTimeZone() throws {
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
        let span = PlanSpan(window: .oneHour, startingAt: afternoon, timeZone: berlin)

        #expect(normalized(span.timeRange(locale: us)) == "11:20 PM – 12:20 AM")
    }

    @Test func voiceOverReadsTheRangeAsFromAndTo() {
        let span = PlanSpan(window: .threeHours, startingAt: afternoon, timeZone: pacific)

        #expect(normalized(span.accessibilityLabel(locale: us)) == "Next 3 hours, from 2:20 PM to 5:20 PM")
    }

    /// Plain spaces in place of the thin and narrow no-break spaces the formats use.
    private func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{2009}", with: " ")
    }
}
