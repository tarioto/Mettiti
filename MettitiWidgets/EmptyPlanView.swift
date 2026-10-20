import SwiftUI
import WidgetKit

/// Shown instead of a plan: with no plan from today ("Open Mettiti"), or once today's plan no
/// longer covers what's ahead (`needsUpdate`).
struct EmptyPlanView: View {
    var message: LocalizedStringKey = "Open Mettiti"

    /// Today's plan is for another Plan Window, or its window has passed with no refresh.
    static var needsUpdate: EmptyPlanView { EmptyPlanView(message: "Open Mettiti to update") }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "tshirt")
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}
