import SwiftUI
import WidgetKit

struct DescriptionWidgetEntryView: View {
    var entry: PlanEntry

    var body: some View {
        PlanStateView(state: entry.state) { snapshot in
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(snapshot.weather.conditionDescription)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    PlanWindowTimesLabel(span: snapshot.span)
                }
                if let recommendation = snapshot.recommendation {
                    Text(recommendation.summary)
                        .font(.subheadline)
                        .lineLimit(5)
                        .minimumScaleFactor(0.8)
                } else {
                    let unit = SharedStore.loadTemperatureUnit()
                    Text(unit.formattedHighLow(highFahrenheit: snapshot.weather.highTemperatureF, lowFahrenheit: snapshot.weather.lowTemperatureF))
                        .font(.subheadline)
                    NoSuggestionsNote()
                }
                if let provider = snapshot.provider {
                    Spacer(minLength: 0)
                    WeatherAttributionLabel(provider: provider)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

struct DescriptionWidget: Widget {
    let kind = "DescriptionWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PlanTimelineProvider()) { entry in
            DescriptionWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Today's Summary")
        .description("A short text summary of what to wear and bring today.")
        .supportedFamilies([.systemSmall])
    }
}

#Preview(as: .systemSmall) {
    DescriptionWidget()
} timeline: {
    PlanEntry(date: .now, snapshot: .placeholder)
    PlanEntry(date: .now, snapshot: .weatherOnlyPlaceholder)
    PlanEntry(date: .now, state: .needsUpdate)
}
