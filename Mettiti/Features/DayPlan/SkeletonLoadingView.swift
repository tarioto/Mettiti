import SwiftUI

struct SkeletonLoadingView: View {
    var body: some View {
        DayPlanView(weather: .placeholder, recommendation: .ready(Self.recommendation), hourly: Self.hourly)
            .redacted(reason: .placeholder)
            .disabled(true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading")
    }
}

// Sized to match a typical loaded plan (hourly chart, three-line summary, three items with two-line reasons)
// so the cards don't jump in height when real data arrives. Kept separate from the shared
// `.placeholder` values, which also back the widget gallery previews.
extension SkeletonLoadingView {
    static let recommendation = OutfitRecommendation(
        summary: "With showers and cool temps, stay dry and comfortable with smart layers and some sun protection for the brighter breaks.",
        items: [
            RecommendedItem(emoji: "☂️", name: "Umbrella", reason: "Rain showers are likely, so keep dry with a reliable umbrella."),
            RecommendedItem(emoji: "🧥", name: "Light jacket", reason: "Cool temps this morning call for a breathable outer layer."),
            RecommendedItem(emoji: "🕶️", name: "Sunglasses", reason: "UV is low, but the sun can still peek through the showers.")
        ]
    )

    static let hourly: HourlyForecast = {
        let start = Calendar.current.dateInterval(of: .hour, for: .now)?.start ?? .now
        let points = (0..<24).map { hour in
            let date = start.addingTimeInterval(Double(hour) * 3600)
            let mean = 65 + 7 * sin(Double(hour) / 24 * 2 * .pi)
            return HourlyTemperaturePoint(
                date: date,
                meanF: mean,
                minF: mean - 2,
                maxF: mean + 2,
                precipitationProbability: 20
            )
        }
        return HourlyForecast(timeZone: .current, points: points)
    }()
}

// Shimmers placeholder-redacted content. Applied inside each card, beneath its background,
// so the card itself stays solid while its placeholders shimmer. With Reduce Motion on, the
// placeholders are a still dim instead.
struct PlaceholderShimmer: ViewModifier {
    @Environment(\.redactionReasons) private var redactionReasons
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.previewReduceMotion) private var previewReduceMotion
    @State private var phase: CGFloat = -0.5

    func body(content: Content) -> some View {
        if redactionReasons.contains(.placeholder) {
            if systemReduceMotion || previewReduceMotion {
                content.opacity(0.6)
            } else {
                content
                    .modifier(ShimmerMask(phase: phase))
                    .onAppear(perform: startShimmer)
            }
        } else {
            content
        }
    }

    private func startShimmer() {
        withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
            phase = 1.5
        }
    }
}

private extension EnvironmentValues {
    /// Stands in for Reduce Motion, which SwiftUI doesn't let a preview set.
    @Entry var previewReduceMotion = false
}

extension View {
    /// Redacts a view as a placeholder and shimmers it, unless an ancestor's redaction already does.
    /// The shimmer sits outside the redaction, where it can see it.
    func shimmeringPlaceholder() -> some View {
        modifier(ShimmeringPlaceholder())
    }
}

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

private struct ShimmerMask: ViewModifier, Animatable {
    var phase: CGFloat

    nonisolated var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func body(content: Content) -> some View {
        content.mask(
            LinearGradient(
                colors: [.black.opacity(0.4), .black, .black.opacity(0.4)],
                startPoint: UnitPoint(x: phase - 0.3, y: 0.5),
                endPoint: UnitPoint(x: phase + 0.3, y: 0.5)
            )
        )
    }
}

#Preview {
    SkeletonLoadingView()
        .padding()
        .environment(TemperaturePreferenceStore())
        .environment(CardPreferenceStore())
}

#Preview("Loaded plan, outfit skeleton") {
    ScrollView {
        DayPlanView(weather: .placeholder, recommendation: .loading, hourly: SkeletonLoadingView.hourly)
            .padding()
    }
    .environment(TemperaturePreferenceStore())
    .environment(CardPreferenceStore())
}

#Preview("Reduce Motion") {
    SkeletonLoadingView()
        .padding()
        .environment(\.previewReduceMotion, true)
        .environment(TemperaturePreferenceStore())
        .environment(CardPreferenceStore())
}
