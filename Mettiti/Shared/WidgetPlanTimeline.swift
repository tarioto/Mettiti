import Foundation

/// What the widgets show and when they next reload, decided from the saved plan.
/// A plan from an earlier day is never shown as today's: the widgets show their empty state instead.
struct WidgetPlanTimeline {
    /// How often the widgets reload during the day to pick up a plan saved by the app or background refresh.
    static let reloadInterval: TimeInterval = 60 * 60

    /// The plan to show, or nil for the empty state.
    let snapshot: PlanSnapshot?
    /// An hour from now, or the next local midnight if sooner, so today's plan flips to the empty state on time.
    let reloadDate: Date

    init(saved: PlanSnapshot?, now: Date, calendar: Calendar) {
        if let saved, saved.isFromToday(now: now, calendar: calendar) {
            snapshot = saved
        } else {
            snapshot = nil
        }
        let nextMidnight = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now)!)
        reloadDate = min(now.addingTimeInterval(Self.reloadInterval), nextMidnight)
    }
}
