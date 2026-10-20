import SwiftUI

/// Sets the Window Override from the main screen (#100): the same Plan Window stops as Settings,
/// lasting until the next launch or the next day. A menu rather than segments, so the full window
/// names fit at every text size.
struct PlanWindowControl: View {
    let window: PlanWindow
    let onSelect: (PlanWindow) -> Void

    var body: some View {
        Menu {
            Picker("Plan Window", selection: Binding(get: { window }, set: onSelect)) {
                ForEach(PlanWindow.allCases) { window in
                    Text(window.name()).tag(window)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .accessibilityHidden(true)
                Text(window.name())
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 4)
        }
        .buttonStyle(.glass)
        .accessibilityLabel("Plan Window")
        .accessibilityValue(window.name())
        .accessibilityHint(Text("Changes how far ahead the outfit covers for now. Settings keeps the default.", comment: "VoiceOver hint for the main screen's Plan Window menu, which lasts until the next launch or the next day"))
    }
}

#Preview {
    PlanWindowControl(window: .threeHours) { _ in }
        .padding()
}
