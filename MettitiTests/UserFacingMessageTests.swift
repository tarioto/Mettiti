import Foundation
import FoundationModels
import Testing
@testable import Mettiti

private let context = LanguageModelSession.GenerationError.Context(debugDescription: "Raw system text")

struct UserFacingMessageTests {
    @Test(arguments: [URLError.Code.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed])
    func offlineErrorsSayYoureOffline(code: URLError.Code) {
        #expect(UserFacingMessage.describing(URLError(code)) == "You're offline. Check your connection and try again.")
    }

    @Test func timeoutSaysTheWeatherServiceIsSlow() {
        #expect(UserFacingMessage.describing(URLError(.timedOut)) == "The weather service is taking too long to respond. Try again in a moment.")
    }

    @Test(arguments: [URLError.Code.cannotFindHost, .cannotConnectToHost, .badServerResponse, .secureConnectionFailed])
    func otherNetworkErrorsSayTheWeatherServiceIsUnreachable(code: URLError.Code) {
        #expect(UserFacingMessage.describing(URLError(code)) == "Couldn't reach the weather service. Check your connection and try again.")
    }

    @Test(arguments: [
        LanguageModelSession.GenerationError.guardrailViolation(context),
        .exceededContextWindowSize(context),
        .decodingFailure(context),
        .unsupportedGuide(context),
        .refusal(.init(transcriptEntries: []), context)
    ])
    func generationFailuresSayNoSuggestionsThisTime(error: LanguageModelSession.GenerationError) {
        #expect(UserFacingMessage.describing(error) == "Couldn't come up with outfit suggestions this time.")
    }

    @Test(arguments: [LanguageModelSession.GenerationError.rateLimited(context), .concurrentRequests(context)])
    func busyModelSaysTryAgainInAMoment(error: LanguageModelSession.GenerationError) {
        #expect(UserFacingMessage.describing(error) == "Apple Intelligence is busy right now. Try again in a moment.")
    }

    @Test func missingModelAssetsSayAppleIntelligenceIsGettingReady() {
        #expect(UserFacingMessage.describing(LanguageModelSession.GenerationError.assetsUnavailable(context)) == "Apple Intelligence is still getting ready. Try again soon.")
    }

    @Test func unsupportedLanguageSaysSo() {
        #expect(UserFacingMessage.describing(LanguageModelSession.GenerationError.unsupportedLanguageOrLocale(context)) == "Outfit suggestions aren't available in your language yet.")
    }

    // MARK: iOS 27 model errors, which replace GenerationError

    // Only the iOS 27 SDK (Swift 6.4, Xcode 27) has these types; see UserFacingMessage.
    #if compiler(>=6.4)
    @Test @available(iOS 27, *)
    func iOS27ModelFailuresSayNoSuggestionsThisTime() {
        let errors: [any Error] = [
            LanguageModelError.guardrailViolation(.init(debugDescription: "Raw system text")),
            LanguageModelError.contextSizeExceeded(.init(contextSize: 4096, tokenCount: 5000, debugDescription: "Raw system text")),
            LanguageModelError.refusal(.init(explanation: "Raw explanation", debugDescription: "Raw system text")),
            LanguageModelError.unsupportedGenerationGuide(.init(schemaName: nil, debugDescription: "Raw system text")),
            LanguageModelError.unsupportedCapability(.init(capability: .toolCalling, debugDescription: "Raw system text")),
            LanguageModelError.unsupportedTranscriptContent(.init(unsupportedContent: [], debugDescription: "Raw system text")),
            LanguageModelError.timeout(.init(debugDescription: "Raw system text")),
            LanguageModelSession.Error.transcriptMutationWhileResponding,
            GeneratedContent.ParsingError(rawContent: "{", debugDescription: "Raw system text")
        ]
        for error in errors {
            #expect(UserFacingMessage.describing(error) == "Couldn't come up with outfit suggestions this time.")
        }
    }

    @Test @available(iOS 27, *)
    func iOS27BusyModelSaysTryAgainInAMoment() {
        let errors: [any Error] = [
            LanguageModelError.rateLimited(.init(resetDate: nil, debugDescription: "Raw system text")),
            LanguageModelSession.Error.concurrentRequests
        ]
        for error in errors {
            #expect(UserFacingMessage.describing(error) == "Apple Intelligence is busy right now. Try again in a moment.")
        }
    }

    @Test @available(iOS 27, *)
    func iOS27MissingModelAssetsSayAppleIntelligenceIsGettingReady() {
        let error = SystemLanguageModel.Error.assetsUnavailable(.init(debugDescription: "Raw system text"))
        #expect(UserFacingMessage.describing(error) == "Apple Intelligence is still getting ready. Try again soon.")
    }

    @Test @available(iOS 27, *)
    func iOS27UnsupportedLanguageSaysSo() {
        let error = LanguageModelError.unsupportedLanguageOrLocale(.init(languageCode: .french, debugDescription: "Raw system text"))
        #expect(UserFacingMessage.describing(error) == "Outfit suggestions aren't available in your language yet.")
    }
    #endif

    @Test func appErrorsKeepTheirOwnMessage() {
        #expect(UserFacingMessage.describing(WeatherServiceError.decodingFailed) == "Received an unexpected response from the weather service.")
        #expect(UserFacingMessage.describing(AppleWeatherServiceError.missingForecast) == "Apple Weather didn't return a forecast for today.")
        #expect(UserFacingMessage.describing(OutfitAdvisorError.modelUnavailable("This device doesn't support Apple Intelligence.")) == "This device doesn't support Apple Intelligence.")
    }

    @Test func unknownSystemErrorsGetAGenericMessage() {
        let error = NSError(domain: "SomeFramework", code: 42, userInfo: [NSLocalizedDescriptionKey: "Internal failure 0x2a"])
        #expect(UserFacingMessage.describing(error) == "Something went wrong. Try again.")
        #expect(UserFacingMessage.describing(CocoaError(.fileReadCorruptFile)) == "Something went wrong. Try again.")
    }
}
