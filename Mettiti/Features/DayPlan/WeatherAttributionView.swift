import SwiftUI
import WeatherKit

/// Credits the forecast source. Apple requires apps showing WeatherKit data to display
/// the Apple Weather mark and a link to its legal attribution page; Open-Meteo's
/// CC BY 4.0 license requires a credit linking back to open-meteo.com.
struct WeatherAttributionView: View {
    let provider: WeatherProvider

    var body: some View {
        Group {
            switch provider {
            case .apple:
                AppleWeatherAttribution()
            case .openMeteo:
                Link(provider.attributionText, destination: provider.attributionURL)
                    .font(.caption2)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AppleWeatherAttribution: View {
    @State private var attribution: WeatherAttribution?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 4) {
            if let attribution {
                AsyncImage(url: colorScheme == .dark ? attribution.combinedMarkDarkURL : attribution.combinedMarkLightURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Text(WeatherProvider.apple.attributionText)
                        .font(.caption.bold())
                }
                .frame(height: 12)
                .accessibilityLabel(attribution.serviceName)

                Link("Other data sources", destination: attribution.legalPageURL)
                    .font(.caption2)
            }
        }
        .task {
            attribution = try? await WeatherKit.WeatherService.shared.attribution
        }
    }
}
