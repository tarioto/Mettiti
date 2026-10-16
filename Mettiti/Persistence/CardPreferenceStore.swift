import Foundation

@MainActor
final class CardPreferenceStore: ObservableObject {
    @Published var cards: [CardConfig] {
        didSet { storedCards.save(cards) }
    }

    private let storedCards: StoredPreference<[CardConfig]>
    private static let defaultOrder: [CardType] = [.plan, .weather, .wearAndBring]

    /// A stored layout that doesn't list every card (e.g. after a card type is added) is replaced by the default.
    init(defaults: UserDefaults = .standard) {
        storedCards = .json("cardConfiguration", in: defaults)
        if let stored = storedCards.load(), Set(stored.map(\.type)) == Set(CardType.allCases) {
            cards = stored
        } else {
            cards = Self.defaultOrder.map { CardConfig(type: $0, isVisible: true) }
        }
    }

    var visibleOrderedTypes: [CardType] {
        cards.filter(\.isVisible).map(\.type)
    }
}
