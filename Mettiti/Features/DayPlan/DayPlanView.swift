import MapKit
import SwiftUI

struct DayPlanView: View {
    let weather: DailyWeather
    let recommendation: RecommendationState
    var hourly: HourlyForecast? = nil
    /// What the plan covers; nil in previews.
    var span: PlanSpan? = nil
    var provider: WeatherProvider = .openMeteo
    /// Where the plan is for; nil while Current Location waits for a fix, and in previews.
    var location: PlanLocation? = nil
    var onRetryRecommendation: () -> Void = {}
    @Environment(TemperaturePreferenceStore.self) private var temperaturePreference
    @Environment(CardPreferenceStore.self) private var cardPreference
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ScaledMetric(relativeTo: .largeTitle) private var conditionSymbolSize: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: Self.cardSpacing) {
            cards

            WeatherAttributionView(provider: provider, includesOpenMeteoData: hourly?.hasSpread == true)
                .modifier(PlaceholderShimmer())
        }
    }

    private static let cardSpacing: CGFloat = 20

    /// The Wide layout wherever the width is regular, such as iPhone Duo's open display; one column elsewhere.
    @ViewBuilder
    private var cards: some View {
        if horizontalSizeClass == .regular {
            WideLayoutColumns(arrangement: CardColumnArrangement(cards: cardPreference.visibleOrderedTypes), spacing: Self.cardSpacing) { type in
                card(for: type)
            }
        } else {
            ForEach(cardPreference.visibleOrderedTypes) { type in
                card(for: type)
            }
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
        case .location:
            LocationCard(location: location)
        }
    }

    private var weatherCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardTitle(type: .weather)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(weather.conditionDescription)
                        .font(.title2.bold())
                    Text("\(temperaturePreference.unit.formattedHighLow(highFahrenheit: details.highF, lowFahrenheit: details.lowF))  •  \((Double(details.precipitationProbability) / 100).formatted(.percent)) rain  •  UV \(Int(details.uvIndex.rounded()))", comment: "Weather card details: high/low, chance of rain, UV index")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: WMOWeatherCode.symbolName(for: weather.conditionCode))
                    .font(.system(size: conditionSymbolSize))
                    .symbolRenderingMode(.multicolor)
                    .accessibilityHidden(true)
            }

            if let hourly {
                HourlyTemperatureChart(hourly: hourly, span: span)
            }
        }
        .padding()
        .cardBackground()
    }

    /// The hourly forecast over the plan's span, or nil without one (or with no hours in it),
    /// when the weather card falls back to the whole day.
    private var forecastWindow: ForecastWindow? {
        guard let hourly, let span else { return nil }
        let window = ForecastWindow(forecast: hourly, span: span.interval)
        return window.hours.isEmpty ? nil : window
    }

    /// The weather card's numbers: the plan's span when there's an hourly forecast for it,
    /// otherwise the whole day.
    private var details: (highF: Double, lowF: Double, precipitationProbability: Int, uvIndex: Double) {
        guard let window = forecastWindow, let high = window.high, let low = window.low else {
            return (weather.highTemperatureF, weather.lowTemperatureF, weather.precipitationProbability, weather.uvIndex)
        }
        return (high.meanF, low.meanF, window.wettest?.precipitationProbability ?? 0, window.peakDaylightUV?.uvIndex ?? 0)
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(
                type: .plan,
                title: span.map { String(localized: "planCard.title", defaultValue: "\(String(localized: CardType.plan.title)) · \($0.timeRange())", comment: "Plan card title: the card's name, then the times it covers, e.g. Plan · 2:20 – 5:20 PM") },
                accessibilityLabel: span.map { String(localized: "planCard.accessibilityLabel", defaultValue: "\(String(localized: CardType.plan.title)), \($0.accessibilityLabel())", comment: "VoiceOver label for the plan card title: the card's name, then its Plan Window and times") }
            )
            if let city = location?.name {
                Text(city)
                    .font(.title2.bold())
            }
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
        .cardBackground()
    }

    private var wearAndBringCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(type: .wearAndBring)
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
        .cardBackground()
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
        cardPreference.visibleOrderedTypes.first(where: \.showsSuggestion)
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
        .environment(TemperaturePreferenceStore())
        .environment(CardPreferenceStore())
    }
}

/// A card's title, in the style of the Weather app's card headers: the card's symbol and a small
/// secondary label at the leading edge.
private struct CardTitle: View {
    let type: CardType
    var title: String? = nil
    var accessibilityLabel: String? = nil

    var body: some View {
        Label(title ?? String(localized: type.title), systemImage: type.icon)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(accessibilityLabel ?? title ?? String(localized: type.title))
            .accessibilityAddTraits(.isHeader)
    }
}

/// The city the plan is for, on a map with a pin.
private struct LocationCard: View {
    let location: PlanLocation?
    @ScaledMetric(relativeTo: .body) private var mapHeight: CGFloat = 160

    /// The map runs to the card's edges, so only the title is padded and the card clips the map
    /// to its corners.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardTitle(type: .location)
                .padding()

            map
                .frame(height: mapHeight)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
        .clipShape(.rect(cornerRadius: 16))
    }

    @ViewBuilder
    private var map: some View {
        if let location {
            let region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 12_000, longitudinalMeters: 12_000)
            Map(position: .constant(.region(region)), interactionModes: []) {
                Marker(location.name ?? "", systemImage: "mappin", coordinate: location.coordinate)
            }
        } else {
            Rectangle()
                .fill(.quaternary)
        }
    }
}

private struct ItemRow: View {
    let item: RecommendedItem
    @ScaledMetric(relativeTo: .title) private var emojiSize: CGFloat = 34
    @ScaledMetric(relativeTo: .title) private var emojiColumnWidth: CGFloat = 44

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(item.emoji)
                .font(.system(size: emojiSize))
                .frame(width: emojiColumnWidth)
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

extension View {
    /// Cards are content, so they sit on a material rather than Liquid Glass, which the HIG keeps
    /// for the controls floating above content.
    func cardBackground() -> some View {
        modifier(PlaceholderShimmer())
            .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }
}
