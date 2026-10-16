import Foundation

/// A recommended item paired with a positional id, so lists stay unique and
/// ordered even when the language model returns items with the same name.
struct DisplayedItem: Identifiable {
    let id: Int
    let item: RecommendedItem
}

extension OutfitRecommendation {
    func displayedItems(limit: Int) -> [DisplayedItem] {
        items.prefix(limit).enumerated().map { DisplayedItem(id: $0.offset, item: $0.element) }
    }
}
