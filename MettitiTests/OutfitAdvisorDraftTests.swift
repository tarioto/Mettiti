import FoundationModels
import Testing
@testable import Mettiti

struct OutfitAdvisorDraftTests {
    @Test func draftShowsTheSummarySoFarAndOnlyItemsWithAnEmojiAndName() throws {
        let partial = try OutfitRecommendation.PartiallyGenerated(GeneratedContent(properties: [
            "summary": "Grab a light",
            "items": [
                GeneratedContent(properties: ["emoji": "🧥", "name": "Light jacket", "reason": "Cool morning"]),
                GeneratedContent(properties: ["emoji": "🕶️", "name": "Sungl"]),
                GeneratedContent(properties: ["emoji": "☂️"]),
            ],
        ]))

        let draft = OutfitAdvisor.draft(from: partial)

        #expect(draft.summary == "Grab a light")
        #expect(draft.items.map(\.name) == ["Light jacket", "Sungl"])
        #expect(draft.items.map(\.reason) == ["Cool morning", ""])
    }

    @Test func warmDraftHidesItemsUntilTheirNameIsWrittenAndDropsWarmLayers() throws {
        let partial = try OutfitRecommendation.PartiallyGenerated(GeneratedContent(properties: [
            "summary": "Warm all evening",
            "items": [
                GeneratedContent(properties: ["emoji": "☂️", "name": "Umbrella", "reason": "Showers"]),
                GeneratedContent(properties: ["emoji": "🧥", "name": "Light jacket", "reason": ""]),
                GeneratedContent(properties: ["emoji": "🧥", "name": "Heavy"]),
            ],
        ]))

        let draft = OutfitRequest(prompt: "", isWarmThroughout: true).draft(from: partial)

        #expect(draft.items.map(\.name) == ["Umbrella"])
    }

    @Test func draftThatIsntWarmThroughoutShowsNamesAsTheyreWritten() throws {
        let partial = try OutfitRecommendation.PartiallyGenerated(GeneratedContent(properties: [
            "items": [GeneratedContent(properties: ["emoji": "🧥", "name": "Heavy"])],
        ]))

        let draft = OutfitRequest(prompt: "", isWarmThroughout: false).draft(from: partial)

        #expect(draft.items.map(\.name) == ["Heavy"])
    }

    @Test func draftBeforeAnythingIsWrittenIsEmpty() throws {
        let partial = try OutfitRecommendation.PartiallyGenerated(GeneratedContent(properties: [:]))

        let draft = OutfitAdvisor.draft(from: partial)

        #expect(draft.summary.isEmpty)
        #expect(draft.items.isEmpty)
    }
}
