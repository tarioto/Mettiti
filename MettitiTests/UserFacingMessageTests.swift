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
        .unsupportedGuide(context)
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
