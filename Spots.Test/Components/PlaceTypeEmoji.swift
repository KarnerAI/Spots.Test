import Foundation

enum PlaceTypeEmoji {
    static func emoji(for types: [String]?) -> String? {
        guard let types else { return nil }
        for type in types {
            if let match = mapping[type] { return match }
        }
        return nil
    }

    private static let mapping: [String: String] = [
        // Food & drink
        "restaurant": "🍽", "cafe": "☕", "bar": "🍸", "bakery": "🥐",
        "meal_takeaway": "🥡", "meal_delivery": "🥡",
        // Shopping
        "shopping_mall": "🛍", "clothing_store": "👕", "store": "🛍",
        "supermarket": "🛒", "convenience_store": "🏪",
        // Culture & leisure
        "museum": "🏛", "art_gallery": "🎨", "movie_theater": "🎬",
        "night_club": "🪩", "tourist_attraction": "📸", "park": "🌳",
        // Health
        "hospital": "🏥", "doctor": "🩺", "dentist": "🦷", "pharmacy": "💊",
        // Travel
        "lodging": "🏨", "airport": "✈️", "gas_station": "⛽",
        "subway_station": "🚉", "train_station": "🚉", "transit_station": "🚏",
        // Services
        "bank": "🏦", "atm": "🏧", "gym": "🏋", "school": "🎓",
        "university": "🎓", "library": "📚",
        // Worship
        "church": "⛪", "mosque": "🕌", "synagogue": "🕍", "hindu_temple": "🛕",
    ]
}
