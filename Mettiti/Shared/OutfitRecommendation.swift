import FoundationModels

@Generable
struct OutfitRecommendation: Codable {
    @Guide(description: "A warm, conversational 1-2 sentence summary of what to wear and bring today, based on the weather. Describe temperature in words, never with numbers or units")
    var summary: String

    @Guide(description: "3 to 6 specific items to wear or bring today, ordered by importance", .count(3...6))
    var items: [RecommendedItem]
}

@Generable
struct RecommendedItem: Codable {
    @Guide(description: "A single emoji character that best represents this item, e.g. 🕶️ for sunglasses, ☂️ for an umbrella")
    var emoji: String

    @Guide(description: "Short item name, 1-3 words, e.g. 'Sunglasses' or 'Light jacket'")
    var name: String

    @Guide(description: "One short sentence, under 12 words, explaining why it's recommended today, describing temperature in words rather than numbers")
    var reason: String
}

extension OutfitRecommendation {
    static let placeholder = OutfitRecommendation(
        summary: "Expect mild temperatures with a chance of afternoon showers, so plan for layers and rain protection.",
        items: [
            RecommendedItem(emoji: "🕶️", name: "Sunglasses", reason: "Bright morning sun"),
            RecommendedItem(emoji: "☂️", name: "Umbrella", reason: "Afternoon showers likely"),
            RecommendedItem(emoji: "🧥", name: "Light jacket", reason: "Cooler in the evening")
        ]
    )
}
