import Foundation
import Testing
@testable import Mettiti

struct PlanWindowTests {
    private let afternoon = date("2026-10-09T21:20:00Z") // 2:20 PM PDT

    @Test(arguments: [
        (PlanWindow.oneHour, "2026-10-09T22:20:00Z"),     // 3:20 PM
        (PlanWindow.threeHours, "2026-10-10T00:20:00Z"),  // 5:20 PM
        (PlanWindow.sixHours, "2026-10-10T03:20:00Z"),    // 8:20 PM
        (PlanWindow.twelveHours, "2026-10-10T09:20:00Z"), // 2:20 AM, past midnight
        (PlanWindow.restOfDay, "2026-10-10T07:00:00Z"),   // midnight
    ])
    func eachWindowStartsNowAndRunsItsLength(window: PlanWindow, end: String) {
        let span = window.span(startingAt: afternoon, in: pacific)

        #expect(span.start == afternoon)
        #expect(span.end == date(end))
    }

    @Test func fixedWindowsCrossMidnight() {
        let lateEvening = date("2026-10-10T06:00:00Z") // 11 PM PDT

        let span = PlanWindow.threeHours.span(startingAt: lateEvening, in: pacific)

        #expect(span.end == date("2026-10-10T09:00:00Z")) // 2 AM PDT
    }

    @Test func restOfDayLateInTheEveningLastsThreeHoursAndCrossesMidnight() {
        let now = date("2026-10-10T05:30:00Z") // 10:30 PM PDT

        let span = PlanWindow.restOfDay.span(startingAt: now, in: pacific)

        #expect(span.end == date("2026-10-10T08:30:00Z")) // 1:30 AM PDT
    }

    @Test func restOfDayEndsAtMidnightInTheGivenTimeZone() throws {
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))

        let span = PlanWindow.restOfDay.span(startingAt: afternoon, in: berlin) // 11:20 PM CEST

        #expect(span.end == date("2026-10-10T00:20:00Z")) // 3 hours on, at 2:20 AM CEST
    }

    // MARK: Staleness (#98)

    @Test(arguments: [
        (PlanWindow.oneHour, 30),
        (PlanWindow.threeHours, 60),
        (PlanWindow.sixHours, 120),
        (PlanWindow.twelveHours, 180),
        (PlanWindow.restOfDay, 180),
    ])
    func aPlanGoesStaleItsWindowsThresholdAfterItsLastLoad(window: PlanWindow, minutes: Int) {
        let loadedAt = date("2026-10-19T15:00:00Z") // 8 AM PDT
        let calendar = gregorianCalendar(in: pacific)

        let justBefore = loadedAt.addingTimeInterval(TimeInterval(minutes * 60 - 1))
        let atThreshold = loadedAt.addingTimeInterval(TimeInterval(minutes * 60))

        #expect(!window.isPlanStale(lastLoadedAt: loadedAt, now: justBefore, calendar: calendar))
        #expect(window.isPlanStale(lastLoadedAt: loadedAt, now: atThreshold, calendar: calendar))
    }

    @Test func noWindowRefreshesMoreOftenThanEveryThirtyMinutes() {
        let loadedAt = date("2026-10-19T15:00:00Z")
        let calendar = gregorianCalendar(in: pacific)

        for window in PlanWindow.allCases {
            #expect(!window.isPlanStale(lastLoadedAt: loadedAt, now: loadedAt.addingTimeInterval(29 * 60 + 59), calendar: calendar))
        }
    }

    @Test func aPlanFromAnEarlierDayIsStaleEvenMinutesLater() {
        let loadedAt = date("2026-10-20T06:55:00Z") // 11:55 PM PDT
        let afterMidnight = date("2026-10-20T07:05:00Z") // 12:05 AM PDT

        for window in PlanWindow.allCases {
            #expect(window.isPlanStale(lastLoadedAt: loadedAt, now: afterMidnight, calendar: gregorianCalendar(in: pacific)))
        }
    }

    @Test func settingsListTheStopsInOrder() {
        #expect(PlanWindow.allCases == [.oneHour, .threeHours, .sixHours, .twelveHours, .restOfDay])
    }
}
