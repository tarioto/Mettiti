import SwiftUI

struct DayPlanView: View {
    let weather: DailyWeather
    let recommendation: RecommendationState
    var hourly: HourlyForecast? = nil
    var provider: WeatherProvider = .openMeteo
    var onRetryRecommendation: () -> Void = {}
    @EnvironmentObject private var temperaturePreference: TemperaturePreferenceStore
    @EnvironmentObject private var cardPreference: CardPreferenceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(cardPreference.visibleOrderedTypes) { type in
                card(for: type)
            }

            WeatherAttributionView(provider: provider)
                .modifier(PlaceholderShimmer())
        }
    }

    @ViewBuilder
    private func card(for type: CardType) -> some View {
        switch type {
        case .weather:
            weatherCard
        case .plan:
            planCard
        case .wearAndBring:
            wearAndBringCard
        }
    }

    private var weatherCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Weather")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(weather.conditionDescription)
                        .font(.title2.bold())
                    Text("H:\(temperaturePreference.unit.displayString(fromFahrenheit: weather.highTemperatureF)) L:\(temperaturePreference.unit.displayString(fromFahrenheit: weather.lowTemperatureF))  •  \(weather.precipitationProbability)% rain  •  UV \(Int(weather.uvIndex.rounded()))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: WMOWeatherCode.symbolName(for: weather.conditionCode))
                    .font(.system(size: 44))
                    .symbolRenderingMode(.multicolor)
            }

            if let hourly {
                HourlyTemperatureChart(hourly: hourly)
            }
        }
        .padding()
        .cardGlass()
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today's plan")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
            Divider()
            switch recommendation {
            case .ready(let outfit):
                Text(outfit.summary)
                    .font(.body)
                    .foregroundStyle(.secondary)
            case .loading:
                Text(SkeletonLoadingView.recommendation.summary)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .redacted(reason: .placeholder)
            case .unavailable, .failed:
                recommendationNotice(for: .plan)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .cardGlass()
    }

    private var wearAndBringCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Wear & bring")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
            Divider()

            switch recommendation {
            case .ready(let outfit):
                itemList(outfit.items)
            case .loading:
                itemList(SkeletonLoadingView.recommendation.items)
                    .redacted(reason: .placeholder)
            case .unavailable, .failed:
                recommendationNotice(for: .wearAndBring)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .cardGlass()
    }

    private func itemList(_ items: [RecommendedItem]) -> some View {
        VStack(spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                ItemRow(item: item)
            }
        }
    }

    /// The full explanation and action go in the first visible suggestion card; any later one
    /// just notes there are no suggestions, so the message and button aren't repeated.
    @ViewBuilder
    private func recommendationNotice(for card: CardType) -> some View {
        let firstSuggestionCard = cardPreference.visibleOrderedTypes.first { $0 != .weather }
        if card == firstSuggestionCard {
            RecommendationNoticeView(recommendation: recommendation, onRetry: onRetryRecommendation)
        } else {
            Text("No outfit suggestions right now.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

/// Explains why there's no outfit suggestion and offers the matching fix.
private struct RecommendationNoticeView: View {
    let recommendation: RecommendationState
    let onRetry: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            action
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var symbolName: String {
        switch recommendation {
        case .unavailable(.modelNotReady): return "arrow.down.circle"
        case .failed: return "exclamationmark.triangle"
        default: return "apple.intelligence"
        }
    }

    private var message: String {
        switch recommendation {
        case .unavailable(.deviceNotEligible):
            return "Outfit suggestions need a device that supports Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence to get outfit suggestions."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still getting ready. Try again soon."
        case .failed:
            return "Couldn't come up with outfit suggestions this time."
        case .loading, .ready:
            return ""
        }
    }

    @ViewBuilder
    private var action: some View {
        switch recommendation {
        case .unavailable(.appleIntelligenceNotEnabled):
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                Label("Open Settings", systemImage: "gear")
            }
            .buttonStyle(.bordered)
        case .unavailable(.modelNotReady), .failed:
            Button(action: onRetry) {
                Label("Try Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        case .unavailable(.deviceNotEligible), .loading, .ready:
            EmptyView()
        }
    }
}

#Preview("Apple Intelligence off") {
    DayPlanPreview(recommendation: .unavailable(.appleIntelligenceNotEnabled))
}

#Preview("Device not eligible") {
    DayPlanPreview(recommendation: .unavailable(.deviceNotEligible))
}

#Preview("Model downloading") {
    DayPlanPreview(recommendation: .unavailable(.modelNotReady))
}

#Preview("Generation failed") {
    DayPlanPreview(recommendation: .failed("The model couldn't respond."))
}

#Preview("Suggestions loading") {
    DayPlanPreview(recommendation: .loading)
}

private struct DayPlanPreview: View {
    let recommendation: RecommendationState

    var body: some View {
        ScrollView {
            DayPlanView(weather: .placeholder, recommendation: recommendation)
                .padding()
        }
        .environmentObject(TemperaturePreferenceStore())
        .environmentObject(CardPreferenceStore())
    }
}

private struct ItemRow: View {
    let item: RecommendedItem

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(item.emoji)
                .font(.system(size: 34))
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                Text(item.reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

private extension View {
    func cardGlass() -> some View {
        modifier(PlaceholderShimmer())
            .glassEffect(in: .rect(cornerRadius: 16))
    }
}
