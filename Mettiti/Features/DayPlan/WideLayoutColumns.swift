import SwiftUI

/// The main screen's cards in the Wide layout: two equal columns, or a lone card in a centered
/// column. When the display is half-folded, the gap between the columns covers the fold, so no
/// card sits across the crease.
struct WideLayoutColumns<Card: View>: View {
    let arrangement: CardColumnArrangement
    let spacing: CGFloat
    @ViewBuilder let card: (CardType) -> Card
    /// The fold's horizontal extent in this view's coordinates, while the display is half-folded.
    @State private var fold: ClosedRange<CGFloat>?

    var body: some View {
        switch arrangement {
        case .empty:
            EmptyView()
        case .centered(let type):
            card(type)
                .readableColumn()
        case .columns(let left, let right):
            ColumnsLayout(fold: fold, spacing: spacing) {
                column(left)
                column(right)
            }
            .onGeometryChange(for: ClosedRange<CGFloat>?.self, of: Self.fold(in:)) { fold = $1 }
        }
    }

    private func column(_ types: [CardType]) -> some View {
        VStack(spacing: spacing) {
            ForEach(types) { type in
                card(type)
            }
        }
    }

    /// The first vertical division the system reserves, which on a half-folded iPhone Duo is the fold.
    private nonisolated static func fold(in proxy: GeometryProxy) -> ClosedRange<CGFloat>? {
        guard #available(iOS 27.1, *) else { return nil }
        return proxy.reservedRegions(kind: .division)
            .map(\.frame)
            .first { $0.height >= $0.width }
            .map { $0.minX...$0.maxX }
    }
}

/// Places its two subviews side by side in equal-width columns. The gap between them is centered
/// on the fold and covers it, or is `spacing` wide when there's no fold.
private struct ColumnsLayout: Layout {
    let fold: ClosedRange<CGFloat>?
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let columns = columnFrames(width: width)
        let height = zip(subviews, columns)
            .map { $0.sizeThatFits(ProposedViewSize(width: $1.width, height: nil)).height }
            .max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, column) in zip(subviews, columnFrames(width: bounds.width)) {
            subview.place(
                at: CGPoint(x: bounds.minX + column.minX, y: bounds.minY),
                proposal: ProposedViewSize(width: column.width, height: nil)
            )
        }
    }

    /// The columns' horizontal extents. They stay equal width, so if the fold isn't centered the
    /// columns take the width of the narrower side.
    private func columnFrames(width: CGFloat) -> [(minX: CGFloat, width: CGFloat)] {
        let center = fold.map { ($0.lowerBound + $0.upperBound) / 2 } ?? width / 2
        let gap = max(fold.map { $0.upperBound - $0.lowerBound } ?? 0, spacing)
        let columnWidth = max(min(center - gap / 2, width - center - gap / 2), 0)
        return [
            (center - gap / 2 - columnWidth, columnWidth),
            (center + gap / 2, columnWidth),
        ]
    }
}

extension View {
    /// Centers the view in a column capped at a comfortable reading width, for a lone card or the
    /// error state on a wide display.
    func readableColumn() -> some View {
        frame(maxWidth: 670)
            .frame(maxWidth: .infinity)
    }
}
