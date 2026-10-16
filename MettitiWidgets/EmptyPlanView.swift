import SwiftUI
import WidgetKit

struct EmptyPlanView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "tshirt")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Open Mettiti")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}
