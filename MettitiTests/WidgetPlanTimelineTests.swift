import Foundation
import Testing
@testable import Mettiti

struct WidgetPlanTimelineTests {
    @Test func planFromYesterdayIsNotShown() {
        let timeline = WidgetPlanTimeline(
            saved: .generated(at: date("2026-10-07T18:00:00-07:00")),
            now: date("2026-10-08T09:00:00-07:00"),
            calendar: gregorianCalendar(in: pacific)
        )

        #expect(timeline.snapshot == nil)
    }

    @Test func planFromEarlierTodayIsShown() {
        let generatedAt = date("2026-10-08T00:30:00-07:00")
        let timeline = WidgetPlanTimeline(saved: .generated(at: generatedAt), now: date("2026-10-08T09:00:00-07:00"), calendar: gregorianCalendar(in: pacific))

        #expect(timeline.snapshot?.generatedAt == generatedAt)
        #expect(timeline.snapshot?.recommendation != nil)
    }

    @Test func weatherOnlyPlanFromEarlierTodayIsShown() {
        let generatedAt = date("2026-10-08T07:00:00-07:00")
        let timeline = WidgetPlanTimeline(saved: .weatherOnly(at: generatedAt), now: date("2026-10-08T09:00:00-07:00"), calendar: gregorianCalendar(in: pacific))

        #expect(timeline.snapshot?.generatedAt == generatedAt)
        #expect(timeline.snapshot?.recommendation == nil)
    }

    @Test func noSavedPlanShowsNothing() {
        let timeline = WidgetPlanTimeline(saved: nil, now: date("2026-10-08T09:00:00-07:00"), calendar: gregorianCalendar(in: pacific))

        #expect(timeline.snapshot == nil)
    }

    @Test func planFromJustBeforeMidnightIsHiddenJustAfterMidnight() {
        let timeline = WidgetPlanTimeline(
            saved: .generated(at: date("2026-10-07T23:59:00-07:00")),
            now: date("2026-10-08T00:01:00-07:00"),
            calendar: gregorianCalendar(in: pacific)
        )

        #expect(timeline.snapshot == nil)
    }

    @Test func dayIsJudgedInTheDeviceTimeZoneNotUTC() {
        // 08:00 and 20:00 Tokyo are the same local day, but 08:00 is still Oct 7 in UTC.
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let timeline = WidgetPlanTimeline(
            saved: .generated(at: date("2026-10-08T08:00:00+09:00")),
            now: date("2026-10-08T20:00:00+09:00"),
            calendar: gregorianCalendar(in: tokyo)
        )

        #expect(timeline.snapshot != nil)
    }

    @Test func planFromYesterdayInDeviceTimeZoneIsHiddenEvenWhenTodayInUTC() {
        // 23:00 Oct 7 and 01:00 Oct 8 in Pacific time are both Oct 8 in UTC.
        let timeline = WidgetPlanTimeline(
            saved: .generated(at: date("2026-10-07T23:00:00-07:00")),
            now: date("2026-10-08T01:00:00-07:00"),
            calendar: gregorianCalendar(in: pacific)
        )

        #expect(timeline.snapshot == nil)
    }

    @Test func reloadsHourlyDuringTheDay() {
        let now = date("2026-10-08T09:15:00-07:00")
        let timeline = WidgetPlanTimeline(saved: nil, now: now, calendar: gregorianCalendar(in: pacific))

        #expect(timeline.reloadDate == date("2026-10-08T10:15:00-07:00"))
    }

    @Test func reloadsAtMidnightWhenTheNextHourCrossesIt() {
        let timeline = WidgetPlanTimeline(
            saved: .generated(at: date("2026-10-08T09:00:00-07:00")),
            now: date("2026-10-08T23:30:00-07:00"),
            calendar: gregorianCalendar(in: pacific)
        )

        #expect(timeline.reloadDate == date("2026-10-09T00:00:00-07:00"))
    }

    @Test func midnightIsTheDeviceTimeZonesMidnight() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let timeline = WidgetPlanTimeline(saved: nil, now: date("2026-10-08T23:45:00+09:00"), calendar: gregorianCalendar(in: tokyo))

        #expect(timeline.reloadDate == date("2026-10-09T00:00:00+09:00"))
    }
}
