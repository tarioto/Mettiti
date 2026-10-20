import WidgetKit

typealias PlanEntry = WidgetPlanTimeline.Entry

extension WidgetPlanTimeline.Entry: TimelineEntry {
    /// An entry showing `snapshot`, e.g. for previews.
    init(date: Date, snapshot: PlanSnapshot) {
        self.init(date: date, state: .plan(snapshot))
    }
}

struct PlanTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlanEntry {
        PlanEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (PlanEntry) -> Void) {
        let now = Date.now
        completion(context.isPreview ? PlanEntry(date: now, snapshot: .placeholder) : currentTimeline(now: now).current)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PlanEntry>) -> Void) {
        let timeline = currentTimeline(now: .now)
        completion(Timeline(entries: timeline.entries, policy: .after(timeline.reloadDate)))
    }

    /// Follows the Settings default Plan Window, never the main screen's override.
    private func currentTimeline(now: Date) -> WidgetPlanTimeline {
        WidgetPlanTimeline(saved: SharedStore.load(), window: SharedStore.loadPlanWindow(), now: now, calendar: .current)
    }
}
