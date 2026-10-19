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
        (PlanWindow.oneHour, "Next hour · 2:20 – 3:20 PM"),
        (PlanWindow.threeHours, "Next 3 hours · 2:20 – 5:20 PM"),
        (PlanWindow.twelveHours, "Next 12 hours · 2:20 PM – 2:20 AM"),
        (PlanWindow.restOfDay, "Rest of day · 2:20 PM – 12:00 AM"),
    ])
    func titleNamesTheWindowAndItsLocalTimes(window: PlanWindow, title: String) {
        let span = PlanSpan(window: window, startingAt: afternoon, timeZone: pacific)

        #expect(normalized(span.title(locale: us)) == title)
    }

    @Test func titleUsesTheForecastLocationsTimeZone() throws {
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
        let span = PlanSpan(window: .oneHour, startingAt: afternoon, timeZone: berlin)

        #expect(normalized(span.title(locale: us)) == "Next hour · 11:20 PM – 12:20 AM")
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
