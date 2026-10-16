import WidgetKit

struct PlanEntry: TimelineEntry {
    let date: Date
    let snapshot: PlanSnapshot?
}

struct PlanTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlanEntry {
        PlanEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (PlanEntry) -> Void) {
        let snapshot = context.isPreview ? .placeholder : currentTimeline().snapshot
        completion(PlanEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PlanEntry>) -> Void) {
        let now = Date.now
        let timeline = currentTimeline(now: now)
        completion(Timeline(entries: [PlanEntry(date: now, snapshot: timeline.snapshot)], policy: .after(timeline.reloadDate)))
    }

    private func currentTimeline(now: Date = .now) -> WidgetPlanTimeline {
        WidgetPlanTimeline(saved: SharedStore.load(), now: now, calendar: .current)
    }
}
