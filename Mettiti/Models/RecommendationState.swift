import Foundation

/// The outfit suggestion's progress for weather that has already loaded.
enum RecommendationState {
    case loading
    case ready(OutfitRecommendation)
    case unavailable(UnavailableReason)
    case failed(String)

    /// Why the on-device model can't make suggestions right now.
    enum UnavailableReason: Equatable, Sendable {
        case deviceNotEligible
        case appleIntelligenceNotEnabled
        case modelNotReady
    }

    /// Whether the model is still working on the suggestion.
    var isInProgress: Bool {
        switch self {
        case .loading: return true
        case .ready, .unavailable, .failed: return false
        }
    }

    /// Changes whenever what a card shows for this state changes, so the card can crossfade:
    /// skeleton, notice, or a particular outfit.
    var crossfadeID: String {
        switch self {
        case .loading: return "loading"
        case .ready(let outfit): return "ready:" + outfit.summary + outfit.items.map { "\($0.emoji)\($0.name)\($0.reason)" }.joined(separator: "|")
        case .unavailable, .failed: return "notice"
        }
    }

    var outfit: OutfitRecommendation? {
        if case .ready(let recommendation) = self { return recommendation }
        return nil
    }

    /// Why there's no suggestion, for the user; nil while there is or will be one.
    var problemMessage: String? {
        switch self {
        case .unavailable(.deviceNotEligible):
            return String(localized: "Outfit suggestions need a device that supports Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return String(localized: "Turn on Apple Intelligence to get outfit suggestions.")
        case .unavailable(.modelNotReady):
            return String(localized: "Apple Intelligence is still getting ready. Try again soon.")
        case .failed(let message):
            return message
        case .loading, .ready:
            return nil
        }
    }
}

/// Whether the on-device model can make outfit suggestions right now.
enum RecommendationAvailability: Equatable, Sendable {
    case available
    case unavailable(RecommendationState.UnavailableReason)
}
