import SwiftUI
import WidgetKit

struct EmojiWidgetEntryView: View {
    var entry: PlanEntry
    @ScaledMetric(relativeTo: .title) private var emojiSize: CGFloat = 34

    var body: some View {
        PlanStateView(state: entry.state) { snapshot in
            if let recommendation = snapshot.recommendation {
                VStack(spacing: 4) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(recommendation.displayedItems(limit: 4)) { row in
                            Text(row.item.emoji)
                                .font(.system(size: emojiSize))
                        }
                    }
                    PlanWindowTimesLabel(span: snapshot.span)
                }
                // Cap growth so four emoji and the window's times still fit a small widget.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .padding(4)
                .containerBackground(.fill.tertiary, for: .widget)
            } else {
                WeatherOnlyPlanView(weather: snapshot.weather, span: snapshot.span, provider: snapshot.provider)
            }
        }
    }
}

struct EmojiWidget: Widget {
    let kind = "EmojiWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PlanTimelineProvider()) { entry in
            EmojiWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Today's Emojis")
        .description("A quick emoji glance at what to wear and bring today.")
        .supportedFamilies([.systemSmall])
    }
}

#Preview(as: .systemSmall) {
    EmojiWidget()
} timeline: {
    PlanEntry(date: .now, snapshot: .placeholder)
    PlanEntry(date: .now, snapshot: .weatherOnlyPlaceholder)
    PlanEntry(date: .now, state: .needsUpdate)
}
