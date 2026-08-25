import Foundation

// MARK: - Suit

nonisolated enum Suit: Int, CaseIterable, Codable, Sendable, Comparable {
    case clubs, diamonds, hearts, spades

    var symbol: String {
        switch self {
        case .clubs: return "♣"
        case .diamonds: return "♦"
        case .hearts: return "♥"
        case .spades: return "♠"
        }
    }

    var isRed: Bool { self == .hearts || self == .diamonds }

    /// Spoken name. Czech turns the suit into an adjective that has to agree
    /// with the rank's gender, so the caller passes the gender it needs.
    func name(agreeingWith gender: GrammaticalGender) -> String {
        localized(.init("suit.\(key).\(gender.rawValue)"))
    }

    var key: String {
        switch self {
        case .clubs: return "clubs"
        case .diamonds: return "diamonds"
        case .hearts: return "hearts"
        case .spades: return "spades"
        }
    }

    static func < (lhs: Suit, rhs: Suit) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - Rank

nonisolated enum Rank: Int, CaseIterable, Codable, Sendable, Comparable {
    case two = 2, three, four, five, six, seven, eight, nine, ten
    case jack, queen, king, ace

    var symbol: String {
        switch self {
        case .ten: return "10"
        case .jack: return "J"
        case .queen: return "Q"
        case .king: return "K"
        case .ace: return "A"
        default: return String(rawValue)
        }
    }

    static func < (lhs: Rank, rhs: Rank) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - Grammatical gender

/// Czech card names are gendered — "pikové eso" but "pikový král".
nonisolated enum GrammaticalGender: String, Sendable {
    case masculine, feminine, neuter
}

// MARK: - Card

nonisolated struct Card: Hashable, Codable, Sendable, Identifiable, CustomStringConvertible {
    let rank: Rank
    let suit: Suit

    var id: Int { suit.rawValue * 13 + (rank.rawValue - 2) }
    var description: String { rank.symbol + suit.symbol }

    /// Read aloud by VoiceOver, e.g. "Ace of Spades" / "pikové eso".
    var spokenName: String {
        String(localized: "card.name \(rank.name(.singular)) \(suit.name(agreeingWith: rank.gender))")
    }

    static let fullDeck: [Card] = Suit.allCases.flatMap { suit in
        Rank.allCases.map { Card(rank: $0, suit: suit) }
    }
}

// MARK: - Deck

nonisolated struct Deck: Sendable {
    private(set) var cards: [Card]

    init() {
        cards = Card.fullDeck
        cards.shuffle()
    }

    /// A rigged deck for tests: `stacked[0]` is dealt first.
    init(stacked: [Card]) {
        var rest = Card.fullDeck.filter { !stacked.contains($0) }
        rest.shuffle()
        cards = (stacked + rest).reversed()
    }

    mutating func deal() -> Card {
        cards.removeLast()
    }

    mutating func deal(_ count: Int) -> [Card] {
        (0..<count).map { _ in cards.removeLast() }
    }
}
