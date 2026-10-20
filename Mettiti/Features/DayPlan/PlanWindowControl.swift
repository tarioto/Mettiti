import SwiftUI

/// Sets the Window Override from the main screen (#100): the same Plan Window stops as Settings,
/// lasting until the next launch or the next day. A circular header button beside Refresh, whose
/// menu checks the active window.
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
            HeaderIcon(systemName: "clock")
        }
        .headerIconButtonStyle()
        .accessibilityLabel("Plan Window")
        .accessibilityValue(window.name())
        .accessibilityHint(Text("Changes how far ahead the outfit covers for now. Settings keeps the default.", comment: "VoiceOver hint for the main screen's Plan Window menu, which lasts until the next launch or the next day"))
    }
}

#Preview {
    PlanWindowControl(window: .threeHours) { _ in }
        .padding()
}
