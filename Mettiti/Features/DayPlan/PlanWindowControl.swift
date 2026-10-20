import SwiftUI

/// Sets the Window Override from the main screen (#100): the same Plan Window stops as Settings,
/// lasting until the next launch or the next day. The active window in words at the top leading
/// edge, opening a menu of the others, like the Invites app's title menu.
struct PlanWindowControl: View {
    let window: PlanWindow
    let onSelect: @MainActor (PlanWindow) -> Void

    var body: some View {
        Menu {
            Picker("Plan Window", selection: Binding(get: { window }, set: onSelect)) {
                ForEach(PlanWindow.allCases) { window in
                    Text(window.name()).tag(window)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(window.name())
                Image(systemName: "chevron.down")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .font(.title2.bold())
        }
        .accessibilityLabel("Plan Window")
        .accessibilityValue(window.name())
        .accessibilityHint(Text("Changes how far ahead the outfit covers for now. Settings keeps the default.", comment: "VoiceOver hint for the main screen's Plan Window menu, which lasts until the next launch or the next day"))
    }
}

#Preview {
    PlanWindowControl(window: .threeHours) { _ in }
        .padding()
}
