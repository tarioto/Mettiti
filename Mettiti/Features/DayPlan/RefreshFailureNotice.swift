import SwiftUI

/// Shown above today's Saved Plan when refreshing it failed, so the plan stays usable offline (#22).
struct RefreshFailureNotice: View {
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Showing the plan saved earlier today.")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    RefreshFailureNotice(message: "Couldn't reach the weather service. Check your connection and try again.")
        .padding()
}
