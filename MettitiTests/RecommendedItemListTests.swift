import Testing
@testable import Mettiti

struct RecommendedItemListTests {
    private func recommendation(_ names: [String]) -> OutfitRecommendation {
        OutfitRecommendation(
            summary: "",
            items: names.map { RecommendedItem(emoji: "🧥", name: $0, reason: "") }
        )
    }

    @Test func itemsWithRepeatedNamesEachGetADistinctIdAndKeepTheirOrder() {
        let rows = recommendation(["Jacket", "Umbrella", "Jacket"]).displayedItems(limit: 4)

        #expect(rows.map(\.item.name) == ["Jacket", "Umbrella", "Jacket"])
        #expect(Set(rows.map(\.id)).count == 3)
    }

    @Test func limitKeepsOnlyTheFirstItems() {
        let rows = recommendation(["Hat", "Hat", "Scarf", "Gloves", "Boots"]).displayedItems(limit: 4)

        #expect(rows.map(\.item.name) == ["Hat", "Hat", "Scarf", "Gloves"])
        #expect(Set(rows.map(\.id)).count == 4)
    }
}
