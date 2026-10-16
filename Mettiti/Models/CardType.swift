import Foundation

enum CardType: String, Codable, CaseIterable, Identifiable {
    case weather
    case plan
    case wearAndBring

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weather: return "Weather"
        case .plan: return "Today's plan"
        case .wearAndBring: return "Wear & bring"
        }
    }

    var icon: String {
        switch self {
        case .weather: return "cloud.sun.fill"
        case .plan: return "text.alignleft"
        case .wearAndBring: return "tshirt.fill"
        }
    }
}

struct CardConfig: Codable, Identifiable, Equatable {
    var type: CardType
    var isVisible: Bool
    var id: CardType { type }
}
