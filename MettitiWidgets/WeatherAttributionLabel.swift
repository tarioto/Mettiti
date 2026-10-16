import SwiftUI

/// Widgets can't load Apple's remote logo image, so credit the source with text.
struct WeatherAttributionLabel: View {
    let provider: WeatherProvider

    var body: some View {
        Text(provider.attributionText)
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}
