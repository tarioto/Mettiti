import SwiftUI
import WidgetKit

/// Shown when the app saved today's weather but Apple Intelligence couldn't suggest an outfit.
struct WeatherOnlyPlanView: View {
    let weather: DailyWeather
    let provider: WeatherProvider?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: WMOWeatherCode.symbolName(for: weather.conditionCode))
                .font(.title2)
                .symbolRenderingMode(.multicolor)
            Text(weather.conditionDescription)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            let unit = SharedStore.loadTemperatureUnit()
            Text("H:\(unit.displayString(fromFahrenheit: weather.highTemperatureF)) L:\(unit.displayString(fromFahrenheit: weather.lowTemperatureF))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            NoSuggestionsNote()
            if let provider {
                WeatherAttributionLabel(provider: provider)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

/// One-line note for widgets whose snapshot has weather but no outfit suggestions.
struct NoSuggestionsNote: View {
    var body: some View {
        Text("No outfit suggestions right now.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(2)
    }
}

extension PlanSnapshot {
    static let weatherOnlyPlaceholder = PlanSnapshot(
        weather: .placeholder,
        recommendation: nil,
        generatedAt: .now,
        provider: .apple
    )
}
