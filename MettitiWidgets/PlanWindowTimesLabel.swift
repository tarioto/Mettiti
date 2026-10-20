import SwiftUI

/// The plan's Plan Window as local times, e.g. "2:20 – 5:20 PM". Plans saved before Plan
/// Windows don't record theirs and show nothing.
struct PlanWindowTimesLabel: View {
    let span: PlanSpan?

    var body: some View {
        if let span {
            Text(span.timeRange())
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityLabel(span.accessibilityLabel())
        }
    }
}
