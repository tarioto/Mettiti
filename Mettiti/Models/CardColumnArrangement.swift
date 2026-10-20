import Foundation

/// How the Wide layout places the visible cards, given in the user's order: a lone card sits in a
/// centered column; otherwise the first card takes the left column and the rest stack on the right.
enum CardColumnArrangement: Equatable {
    case empty
    case centered(CardType)
    case columns(left: CardType, right: [CardType])

    init(cards: [CardType]) {
        guard let first = cards.first else {
            self = .empty
            return
        }
        let rest = Array(cards.dropFirst())
        self = rest.isEmpty ? .centered(first) : .columns(left: first, right: rest)
    }
}
