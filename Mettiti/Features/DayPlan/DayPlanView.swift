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
        // Wider than any iPhone, so this only holds the columns in on a large iPad.
        .readableColumn(maxWidth: 1200)
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
                    Text(weather.localizedConditionDescription)
                        .font(.title2.bold())
                    Text(temperaturePreference.unit.formattedSummary(highFahrenheit: details.highF, lowFahrenheit: details.lowF, precipitationProbability: details.precipitationProbability, uvIndex: details.uvIndex))
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
            crossfading {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .cardBackground()
    }

    private var wearAndBringCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(type: .wearAndBring)
            progressCaption(for: .wearAndBring)

            crossfading {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .cardBackground()
    }

    private func itemList(_ items: [RecommendedItem]) -> some View {
        VStack(spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                ItemRow(item: item)
            }
        }
    }

    /// Lets a card's skeleton, outfit or notice crossfade into the next as the recommendation
    /// changes, including a refresh swapping in a new outfit. Stacked in a ZStack so the old and
    /// new content don't both take up height while they fade.
    private func crossfading<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack(alignment: .top) {
            content()
                .id(recommendation.crossfadeID)
                .transition(.opacity)
        }
        .animation(Self.crossfade, value: recommendation.crossfadeID)
    }

    static let crossfade = Animation.easeInOut(duration: 0.3)

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

/// The city the plan is for, on a map with a pin; until there is one, a desaturated map of
/// roughly where the device is.
private struct LocationCard: View {
    let location: PlanLocation?
    @ScaledMetric(relativeTo: .body) private var mapHeight: CGFloat = 160
    @State private var placeholderRegion: MKCoordinateRegion?

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

    /// The placeholder crossfades into the real map and pin when the location arrives.
    private var map: some View {
        ZStack {
            if let location {
                let region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 12_000, longitudinalMeters: 12_000)
                Map(position: .constant(.region(region)), interactionModes: []) {
                    Marker("",systemImage: "mappin", coordinate: location.coordinate)
                }
                .transition(.opacity)
            } else {
                placeholderMap
                    .transition(.opacity)
            }
        }
        .animation(DayPlanView.crossfade, value: location != nil)
    }

    /// Roughly where the device is, desaturated and without a pin, shimmering like the rest of the
    /// Skeleton.
    private var placeholderMap: some View {
        Group {
            if let placeholderRegion {
                Map(position: .constant(.region(placeholderRegion)), interactionModes: [])
                    .saturation(0)
            } else {
                Rectangle()
                    .fill(.quaternary)
            }
        }
        .animation(DayPlanView.crossfade, value: placeholderRegion != nil)
        .modifier(ShimmeringPlaceholder())
        .task {
            placeholderRegion = await PlaceholderMapRegion.resolveForDevice()
        }
    }
}

/// Makes a view shimmer as a placeholder, unless an ancestor's redaction already does.
private struct ShimmeringPlaceholder: ViewModifier {
    @Environment(\.redactionReasons) private var redactionReasons

    func body(content: Content) -> some View {
        if redactionReasons.contains(.placeholder) {
            content
        } else {
            content
                .redacted(reason: .placeholder)
                .modifier(PlaceholderShimmer())
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
