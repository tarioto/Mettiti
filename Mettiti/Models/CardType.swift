import Foundation

enum CardType: String, Codable, CaseIterable, Identifiable {
    case weather
    case plan
    case wearAndBring
    case location

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weather: return String(localized: "Weather")
        case .plan: return String(localized: "Plan")
        case .wearAndBring: return String(localized: "Wear & bring")
        case .location: return String(localized: "Location")
        }
    }

    var icon: String {
        switch self {
        case .weather: return "cloud.sun.fill"
        case .plan: return "text.alignleft"
        case .wearAndBring: return "tshirt.fill"
        case .location: return "mappin.and.ellipse"
        }
    }
}

struct CardConfig: Codable, Identifiable, Equatable {
    var type: CardType
    var isVisible: Bool
    var id: CardType { type }
}
