import Foundation

@testable import AskCore

/// A host's row carrying a number, the kind of row that can decode and still
/// not encode: a default `JSONEncoder` throws on a `rating` that isn't finite,
/// and this row reads one saved before it had a rating as `.nan`, as a host's
/// type that added the field might. `refuses` makes its own `encode(to:)`
/// throw an error of the row's own.
nonisolated struct RatedRow: AskRow {
    /// What `encode(to:)` throws for a row that `refuses`.
    struct Refusal: Error {}

    let id: String
    let displayTitle: String
    let rating: Double
    var refuses = false

    init(_ id: String, _ displayTitle: String, rating: Double = 4, refuses: Bool = false) {
        self.id = id
        self.displayTitle = displayTitle
        self.rating = rating
        self.refuses = refuses
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayTitle, rating
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayTitle = try container.decode(String.self, forKey: .displayTitle)
        rating = try container.decodeIfPresent(Double.self, forKey: .rating) ?? .nan
    }

    func encode(to encoder: any Encoder) throws {
        if refuses { throw Refusal() }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayTitle, forKey: .displayTitle)
        try container.encode(rating, forKey: .rating)
    }
}
