import Testing
@testable import Mettiti

struct CardColumnArrangementTests {
    @Test func noCardsLeavesTheWideLayoutEmpty() {
        #expect(CardColumnArrangement(cards: []) == .empty)
    }

    @Test func aLoneCardSitsCentered() {
        #expect(CardColumnArrangement(cards: [.weather]) == .centered(.weather))
    }

    @Test func twoCardsTakeOneColumnEach() {
        #expect(CardColumnArrangement(cards: [.plan, .weather]) == .columns(left: .plan, right: [.weather]))
    }

    @Test func threeCardsPutTheFirstOnTheLeftAndStackTheRestOnTheRight() {
        #expect(CardColumnArrangement(cards: [.plan, .weather, .wearAndBring]) == .columns(left: .plan, right: [.weather, .wearAndBring]))
    }

    @Test func aCustomOrderIsRespected() {
        #expect(CardColumnArrangement(cards: [.wearAndBring, .weather, .plan]) == .columns(left: .wearAndBring, right: [.weather, .plan]))
    }

    @MainActor
    @Test func hiddenCardsAreLeftOut() {
        let store = CardPreferenceStore(defaults: isolatedDefaults())
        store.cards = [
            CardConfig(type: .plan, isVisible: true),
            CardConfig(type: .weather, isVisible: false),
            CardConfig(type: .wearAndBring, isVisible: true),
        ]

        #expect(CardColumnArrangement(cards: store.visibleOrderedTypes) == .columns(left: .plan, right: [.wearAndBring]))
    }
}
