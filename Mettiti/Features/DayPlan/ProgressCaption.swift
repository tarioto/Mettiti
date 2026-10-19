import SwiftUI

/// What's loading right now, shown above the placeholder content it's filling in.
struct ProgressCaption: View {
    private let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ProgressCaption("Checking today's weather…")
        .padding()
}
