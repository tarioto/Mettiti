import Foundation

/// How the Wide layout places the visible cards, given in the user's order: a lone card sits in a
/// centered column; otherwise the last card takes the right column and the rest stack on the left.
enum CardColumnArrangement: Equatable {
    case empty
    case centered(CardType)
    case columns(left: [CardType], right: [CardType])

    init(cards: [CardType]) {
        guard let last = cards.last else {
            self = .empty
            return
        }
        let rest = Array(cards.dropLast())
        self = rest.isEmpty ? .centered(last) : .columns(left: rest, right: [last])
    }
}
