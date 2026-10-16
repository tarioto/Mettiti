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

    var outfit: OutfitRecommendation? {
        if case .ready(let recommendation) = self { return recommendation }
        return nil
    }
}

/// Whether the on-device model can make outfit suggestions right now.
enum RecommendationAvailability: Equatable, Sendable {
    case available
    case unavailable(RecommendationState.UnavailableReason)
}
