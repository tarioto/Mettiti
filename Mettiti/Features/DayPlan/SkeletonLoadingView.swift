import SwiftUI

struct SkeletonLoadingView: View {
    var body: some View {
        DayPlanView(weather: .placeholder, recommendation: .ready(Self.recommendation), hourly: Self.hourly)
            .redacted(reason: .placeholder)
            .disabled(true)
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
        let labelFormatter = DateFormatter()
        labelFormatter.dateFormat = "h a"
        let points = (0..<24).map { hour in
            let date = start.addingTimeInterval(Double(hour) * 3600)
            let mean = 65 + 7 * sin(Double(hour) / 24 * 2 * .pi)
            return HourlyTemperaturePoint(
                date: date,
                hourLabel: labelFormatter.string(from: date),
                meanF: mean,
                minF: mean - 2,
                maxF: mean + 2,
                precipitationProbability: 20
            )
        }
        return HourlyForecast(timeZone: .current, points: points)
    }()
}

// Shimmers placeholder-redacted content. Applied inside each card, beneath its glass:
// masking the glass itself renders it offscreen, which flattens its diffuse shadow.
struct PlaceholderShimmer: ViewModifier {
    @Environment(\.redactionReasons) private var redactionReasons
    @State private var phase: CGFloat = -0.5

    func body(content: Content) -> some View {
        if redactionReasons.contains(.placeholder) {
            content
                .modifier(ShimmerMask(phase: phase))
                .onAppear {
                    withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                        phase = 1.5
                    }
                }
        } else {
            content
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
        .environmentObject(TemperaturePreferenceStore())
        .environmentObject(CardPreferenceStore())
}
