import Foundation

/// What the widgets show and when they next reload, decided from the saved plan and the Settings
/// default Plan Window (never the main screen's override).
/// - A plan is shown while its window runs, past midnight too, then gives way to an entry at
///   the window's end.
/// - A plan from an earlier day whose window has ended is never shown as today's: the widgets
///   show their empty state.
/// - A plan from today whose window has ended, or that's for another window than the default,
///   isn't shown either: the widgets ask to open the app to update it. Background refresh
///   times are only hints, so this is the safety net.
struct WidgetPlanTimeline {
    /// How often the widgets reload during the day to pick up a plan saved by the app or background refresh.
    static let reloadInterval: TimeInterval = 60 * 60

    enum State: Sendable {
        /// No plan for what's ahead, and none from today.
        case empty
        case plan(PlanSnapshot)
        /// Today's plan no longer covers what's ahead; the app needs opening to remake it.
        case needsUpdate
    }

    struct Entry: Sendable {
        let date: Date
        let state: State

        /// The plan shown, if any.
        var snapshot: PlanSnapshot? {
            if case .plan(let snapshot) = state { return snapshot }
            return nil
        }
    }

    /// In date order; the first is for `now`.
    let entries: [Entry]
    /// An hour from now, or the next midnight (the plan's location's, else the device's) if sooner,
    /// so a new day is picked up on time.
    let reloadDate: Date

    /// What to show now.
    var current: Entry { entries[0] }

    /// `calendar` is the device's; a plan that recorded its location's time zone is judged in
    /// that instead, so a city's day, midnight and window end match each other.
    init(saved: PlanSnapshot?, window: PlanWindow, now: Date, calendar deviceCalendar: Calendar) {
        let calendar = saved?.locationCalendar(fallback: deviceCalendar) ?? deviceCalendar
        let nextMidnight = calendar.dateInterval(of: .day, for: now)!.end
        reloadDate = min(now.addingTimeInterval(Self.reloadInterval), nextMidnight)

        guard let saved else {
            entries = [Entry(date: now, state: .empty)]
            return
        }
        /// What to show once the plan is no longer shown at `date`.
        func afterPlan(at date: Date) -> State {
            calendar.isDate(saved.generatedAt, inSameDayAs: date) ? .needsUpdate : .empty
        }
        // Plans saved before Plan Windows have no span; they covered the rest of their day.
        let windowEnd = saved.span?.interval.end
            ?? calendar.dateInterval(of: .day, for: saved.generatedAt)!.end
        guard saved.planWindow == window, now < windowEnd else {
            entries = [Entry(date: now, state: afterPlan(at: now))]
            return
        }
        entries = [
            Entry(date: now, state: .plan(saved)),
            Entry(date: windowEnd, state: afterPlan(at: windowEnd)),
        ]
    }
}
