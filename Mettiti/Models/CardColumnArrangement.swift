import Foundation

/// How the Wide layout places the visible cards, given in the user's order: a lone card sits in a
/// centered column; otherwise the cards split evenly in order, left column first, with the left
/// column taking the extra card when the count is odd.
enum CardColumnArrangement: Equatable {
    case empty
    case centered(CardType)
    case columns(left: [CardType], right: [CardType])

    init(cards: [CardType]) {
        switch cards.count {
        case 0:
            self = .empty
        case 1:
            self = .centered(cards[0])
        default:
            let leftCount = (cards.count + 1) / 2
            self = .columns(left: Array(cards.prefix(leftCount)), right: Array(cards.dropFirst(leftCount)))
        }
    }
}
