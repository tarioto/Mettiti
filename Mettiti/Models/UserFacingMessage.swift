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
        #if compiler(>=6.4)
        if #available(iOS 27, *), let message = modelMessage(for: error) {
            return message
        }
        #endif
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

    /// The on-device model's errors before iOS 27, which replaces `GenerationError` with the
    /// types in `modelMessage(for:)`.
    private static func describing(_ error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .rateLimited, .concurrentRequests:
            return modelBusy
        case .assetsUnavailable:
            return modelNotReady
        case .unsupportedLanguageOrLocale:
            return unsupportedLanguage
        case .guardrailViolation, .exceededContextWindowSize, .decodingFailure, .unsupportedGuide, .refusal:
            return noSuggestion
        @unknown default:
            return noSuggestion
        }
    }

    // The iOS 27 error types only exist in the iOS 27 SDK, which ships with Swift 6.4 (Xcode 27).
    // Older toolchains, such as CI's Xcode 26, compile without them.
    #if compiler(>=6.4)
    /// The on-device model's errors from iOS 27; nil for any other error.
    @available(iOS 27, *)
    private static func modelMessage(for error: any Error) -> String? {
        switch error {
        case let error as LanguageModelError:
            switch error {
            case .rateLimited:
                return modelBusy
            case .unsupportedLanguageOrLocale:
                return unsupportedLanguage
            case .guardrailViolation, .contextSizeExceeded, .refusal, .unsupportedGenerationGuide,
                 .unsupportedCapability, .unsupportedTranscriptContent, .timeout:
                return noSuggestion
            @unknown default:
                return noSuggestion
            }
        case let error as SystemLanguageModel.Error:
            switch error {
            case .assetsUnavailable:
                return modelNotReady
            @unknown default:
                return noSuggestion
            }
        case let error as LanguageModelSession.Error:
            switch error {
            case .concurrentRequests:
                return modelBusy
            case .transcriptMutationWhileResponding:
                return noSuggestion
            @unknown default:
                return noSuggestion
            }
        case is GeneratedContent.ParsingError:
            return noSuggestion
        default:
            return nil
        }
    }
    #endif

    private static var modelBusy: String {
        String(localized: "Apple Intelligence is busy right now. Try again in a moment.")
    }

    private static var modelNotReady: String {
        String(localized: "Apple Intelligence is still getting ready. Try again soon.")
    }

    private static var unsupportedLanguage: String {
        String(localized: "Outfit suggestions aren't available in your language yet.")
    }

    /// The Wear & bring card's message when there's no suggestion and no more specific reason.
    static var noSuggestion: String {
        String(localized: "Couldn't come up with outfit suggestions this time.")
    }
}
