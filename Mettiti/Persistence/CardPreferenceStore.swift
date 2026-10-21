import Foundation
import Observation

@MainActor
@Observable
final class CardPreferenceStore {
    var cards: [CardConfig] {
        didSet { storedCards.save(cards) }
    }

    private let storedCards: StoredPreference<[CardConfig]>
    private static let defaultOrder: [CardType] = [.plan, .weather, .location, .wearAndBring]

    /// A stored layout keeps its order and choices; a card type added since it was saved goes in
    /// at its default position, shown. One that lists a card twice is replaced by the default.
    init(defaults: UserDefaults = .standard) {
        storedCards = .json("cardConfiguration", in: defaults)
        if let stored = storedCards.load(), Set(stored.map(\.type)).count == stored.count {
            var merged = stored
            for (index, type) in Self.defaultOrder.enumerated() where !merged.contains(where: { $0.type == type }) {
                merged.insert(CardConfig(type: type, isVisible: true), at: min(index, merged.count))
            }
            cards = merged
        } else {
            cards = Self.defaultOrder.map { CardConfig(type: $0, isVisible: true) }
        }
    }

    var visibleOrderedTypes: [CardType] {
        cards.filter(\.isVisible).map(\.type)
    }
}
