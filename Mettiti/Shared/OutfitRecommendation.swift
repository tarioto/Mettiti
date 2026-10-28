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

    @Guide(description: "What kind of item this is, whatever language the name is in. warmLayer: jackets, coats, sweaters, hoodies, fleeces, long sleeves and similar. rainGear: raincoats, waterproof jackets, ponchos, umbrellas and similar; a waterproof jacket is rainGear, not warmLayer. other: everything else")
    var kind: ItemKind = .other
}

@Generable
enum ItemKind: String, Codable {
    case warmLayer
    case rainGear
    case other
}

extension RecommendedItem {
    /// Saved Plans written before `kind` existed have no such key; they read as `other`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        emoji = try container.decode(String.self, forKey: .emoji)
        name = try container.decode(String.self, forKey: .name)
        reason = try container.decode(String.self, forKey: .reason)
        kind = try container.decodeIfPresent(ItemKind.self, forKey: .kind) ?? .other
    }
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
    /// The Italian ones cover "Impermeabile", "Giacca impermeabile", "Mantella" and "Ombrello".
    private static let rainGearPrefixes = [
        "rain", "waterproof", "storm", "trench", "poncho",
        "impermeabil", "mantell", "ombrell",
    ]

    /// Italian, with plurals, as they end in a vowel rather than "s". Matched alongside the English
    /// words whatever the app's language, as whole words so "pile" isn't found inside other words.
    private static let italianWarmLayerWords: Set<String> = [
        "giacca", "giacche", "giubbotto", "giubbotti", "giubbino", "giubbini", "cappotto", "cappotti",
        "maglione", "maglioni", "felpa", "felpe", "pile", "cardigan", "parka", "piumino", "piumini", "gilet",
    ]

    /// Whether to drop the item when it's warm throughout. Rain gear wins over a warm layer, by the
    /// model's label or by the name, in either language.
    var isWarmLayer: Bool {
        let words = name.lowercased().split { !$0.isLetter }.map(String.init)
        let singular = words.map { $0.hasSuffix("s") ? String($0.dropLast()) : $0 }
        let pairs = Array(zip(words, words.dropFirst()))

        let isRainGearByName = words.contains { word in Self.rainGearPrefixes.contains { word.hasPrefix($0) } }
            || pairs.contains { $0 == "k" && $1 == "way" }
        if kind == .rainGear || isRainGearByName { return false }

        // Long sleeves are a warm layer, short sleeves aren't.
        let hasLongSleeves = zip(singular, singular.dropFirst()).contains { $0 == "long" && $1.hasPrefix("sleeve") }
            || pairs.contains { $0 == "maniche" && $1 == "lunghe" }
        let hasThermalTop = pairs.contains { ($0 == "maglia" || $0 == "maglie") && $1.hasPrefix("termic") }
        let isWarmLayerByName = hasLongSleeves || hasThermalTop
            || !Set(singular).isDisjoint(with: Self.warmLayerWords)
            || !Set(words).isDisjoint(with: Self.italianWarmLayerWords)
        return kind == .warmLayer || isWarmLayerByName
    }
}
