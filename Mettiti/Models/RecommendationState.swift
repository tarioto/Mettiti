import Foundation

/// The outfit suggestion's progress for weather that has already loaded.
enum RecommendationState {
    case loading
    /// The suggestion so far while the model is still writing it; fields fill in as it streams.
    case generating(OutfitRecommendation)
    case ready(OutfitRecommendation)
    case unavailable(UnavailableReason)
    case failed(String)

    /// Why the on-device model can't make suggestions right now.
    enum UnavailableReason: Equatable, Sendable {
        case deviceNotEligible
        case appleIntelligenceNotEnabled
        case modelNotReady
    }

    /// Whether the model is still working on the suggestion, before or while it streams in.
    var isInProgress: Bool {
        switch self {
        case .loading, .generating: return true
        case .ready, .unavailable, .failed: return false
        }
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
