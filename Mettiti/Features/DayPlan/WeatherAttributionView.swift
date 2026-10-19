import SwiftUI
import WeatherKit

/// Credits the forecast source. Apple requires apps showing WeatherKit data to display
/// the Apple Weather mark and a link to its legal attribution page; Open-Meteo's
/// CC BY 4.0 license requires a credit linking back to open-meteo.com.
struct WeatherAttributionView: View {
    let provider: WeatherProvider
    /// Whether Open-Meteo data is on screen with Apple Weather's, e.g. the hourly chart's spread.
    var includesOpenMeteoData = false

    var body: some View {
        Group {
            switch provider {
            case .apple:
                VStack(spacing: 4) {
                    AppleWeatherAttribution()
                    if includesOpenMeteoData {
                        OpenMeteoAttribution()
                    }
                }
            case .openMeteo:
                OpenMeteoAttribution()
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct OpenMeteoAttribution: View {
    var body: some View {
        Link(WeatherProvider.openMeteo.attributionText, destination: WeatherProvider.openMeteo.attributionURL)
            .font(.caption2)
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
