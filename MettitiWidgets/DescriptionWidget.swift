import SwiftUI
import WidgetKit

struct DescriptionWidgetEntryView: View {
    var entry: PlanEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            VStack(alignment: .leading, spacing: 6) {
                Text(snapshot.weather.conditionDescription)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                if let recommendation = snapshot.recommendation {
                    Text(recommendation.summary)
                        .font(.subheadline)
                        .lineLimit(6)
                        .minimumScaleFactor(0.8)
                } else {
                    let unit = SharedStore.loadTemperatureUnit()
                    Text("H:\(unit.displayString(fromFahrenheit: snapshot.weather.highTemperatureF)) L:\(unit.displayString(fromFahrenheit: snapshot.weather.lowTemperatureF))")
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
        } else {
            EmptyPlanView()
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
}
