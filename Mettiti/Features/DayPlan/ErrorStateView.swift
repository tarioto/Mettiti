import SwiftUI

struct ErrorStateView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(action: onRetry) {
                Label("Try Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
