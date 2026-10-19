import Foundation
import FoundationModels

/// An error whose `errorDescription` is already written for the user, so it's shown as is.
protocol UserFacingError: LocalizedError {}

/// What to tell the user when a plan or its outfit suggestion fails (#29). The app's own errors
/// keep their copy; system errors (networking, the on-device model) never show their raw text.
enum UserFacingMessage {
    static func describing(_ error: any Error) -> String {
        if let error = error as? any UserFacingError, let description = error.errorDescription {
            return description
        }
        if let error = error as? URLError {
            return describing(error)
        }
        if let error = error as? LanguageModelSession.GenerationError {
            return describing(error)
        }
        return String(localized: "Something went wrong. Try again.")
    }

    /// Only the weather fetches go over the network, so a URLError is about the weather service.
    private static func describing(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return String(localized: "You're offline. Check your connection and try again.")
        case .timedOut:
            return String(localized: "The weather service is taking too long to respond. Try again in a moment.")
        default:
            return String(localized: "Couldn't reach the weather service. Check your connection and try again.")
        }
    }

    private static func describing(_ error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .rateLimited, .concurrentRequests:
            return String(localized: "Apple Intelligence is busy right now. Try again in a moment.")
        case .assetsUnavailable:
            return String(localized: "Apple Intelligence is still getting ready. Try again soon.")
        case .unsupportedLanguageOrLocale:
            return String(localized: "Outfit suggestions aren't available in your language yet.")
        case .guardrailViolation, .exceededContextWindowSize, .decodingFailure, .unsupportedGuide, .refusal:
            return String(localized: "Couldn't come up with outfit suggestions this time.")
        @unknown default:
            return String(localized: "Couldn't come up with outfit suggestions this time.")
        }
    }
}
