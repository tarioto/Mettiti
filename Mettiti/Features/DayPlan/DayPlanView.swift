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

            WeatherAttributionView(provider: provider, includesOpenMeteoData: hourly?.hasSpread == true)
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
                    Text("\(temperaturePreference.unit.formattedHighLow(highFahrenheit: weather.highTemperatureF, lowFahrenheit: weather.lowTemperatureF))  •  \((Double(weather.precipitationProbability) / 100).formatted(.percent)) rain  •  UV \(Int(weather.uvIndex.rounded()))", comment: "Weather card details: high/low, chance of rain, UV index")
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
            progressCaption(for: .plan)
            switch recommendation {
            case .ready(let outfit):
                Text(outfit.summary)
                    .font(.body)
                    .foregroundStyle(.secondary)
            case .generating(let partial) where !partial.summary.isEmpty:
                Text(partial.summary)
                    .font(.body)
                    .foregroundStyle(.secondary)
            case .loading, .generating:
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
            progressCaption(for: .wearAndBring)

            switch recommendation {
            case .ready(let outfit):
                itemList(outfit.items)
            case .generating(let partial):
                itemList(partial.items, paddedWithPlaceholders: true)
            case .loading:
                itemList([], paddedWithPlaceholders: true)
            case .unavailable, .failed:
                recommendationNotice(for: .wearAndBring)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .cardGlass()
    }

    /// With `paddedWithPlaceholders`, placeholder rows fill in up to the skeleton's count, so the
    /// card doesn't change height as streamed items arrive.
    private func itemList(_ items: [RecommendedItem], paddedWithPlaceholders: Bool = false) -> some View {
        let placeholders = paddedWithPlaceholders ? Array(SkeletonLoadingView.recommendation.items.dropFirst(items.count)) : []
        return VStack(spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                ItemRow(item: item)
            }
            ForEach(Array(placeholders.enumerated()), id: \.offset) { _, item in
                ItemRow(item: item)
                    .redacted(reason: .placeholder)
            }
        }
    }

    /// While the outfit is on its way, only the first visible suggestion card says so, so it isn't repeated.
    @ViewBuilder
    private func progressCaption(for card: CardType) -> some View {
        if recommendation.isInProgress, card == firstSuggestionCard {
            ProgressCaption("Putting together today's outfit…")
        }
    }

    private var firstSuggestionCard: CardType? {
        cardPreference.visibleOrderedTypes.first { $0 != .weather }
    }

    /// The full explanation and action go in the first visible suggestion card; any later one
    /// just notes there are no suggestions, so the message and button aren't repeated.
    @ViewBuilder
    private func recommendationNotice(for card: CardType) -> some View {
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
        recommendation.problemMessage ?? ""
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
        case .unavailable(.deviceNotEligible), .loading, .generating, .ready:
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

#Preview("Suggestions streaming") {
    DayPlanPreview(recommendation: .generating(OutfitRecommendation(summary: "Expect mild temperatures with a chance", items: [OutfitRecommendation.placeholder.items[0]])))
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
