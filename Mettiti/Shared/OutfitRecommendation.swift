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

extension OutfitRecommendation {
    /// Without jackets, coats, sweaters and the like, for when it's warm throughout. Rain gear
    /// stays: a raincoat or rain jacket is about the rain, not the cold.
    func withoutWarmLayers() -> OutfitRecommendation {
        OutfitRecommendation(summary: summary, items: items.filter { !$0.isWarmLayer })
    }
}

extension RecommendedItem {
    /// Singular, as each word of a name is matched without a trailing "s".
    private static let warmLayerWords: Set<String> = [
        "jacket", "coat", "sweater", "hoodie", "fleece", "cardigan", "parka", "sweatshirt", "pullover",
        "jumper", "puffer", "overcoat", "thermal", "layer", "vest",
    ]

    /// Rain gear doesn't always say "rain" as a word of its own, as in "Waterproof jacket" or
    /// "Trench coat". Matched at the start of a word, so "Raincoat" counts but "Training jacket"
    /// doesn't.
    private static let rainGearPrefixes = ["rain", "waterproof", "storm", "trench", "poncho"]

    var isWarmLayer: Bool {
        let words = name.lowercased().split { !$0.isLetter }.map { $0.hasSuffix("s") ? String($0.dropLast()) : String($0) }
        let isRainGear = words.contains { word in Self.rainGearPrefixes.contains { word.hasPrefix($0) } }
        // Long sleeves are a warm layer, short sleeves aren't.
        let hasLongSleeves = zip(words, words.dropFirst()).contains { $0 == "long" && $1.hasPrefix("sleeve") }
        return !isRainGear && (hasLongSleeves || !Set(words).isDisjoint(with: Self.warmLayerWords))
    }
}
