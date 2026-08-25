import Foundation

// MARK: - Street

nonisolated enum Street: Int, Sendable, Comparable, CaseIterable {
    case preflop, flop, turn, river

    var displayName: String {
        switch self {
        case .preflop: return localized("street.preflop")
        case .flop: return localized("street.flop")
        case .turn: return localized("street.turn")
        case .river: return localized("street.river")
        }
    }

    var communityCardCount: Int {
        switch self {
        case .preflop: return 0
        case .flop: return 3
        case .turn: return 4
        case .river: return 5
        }
    }

    static func < (lhs: Street, rhs: Street) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - Actions

nonisolated enum PlayerAction: Sendable, Equatable {
    case fold
    case check
    case call
    /// Bet or raise TO the given total for this street (not the increment).
    case raise(to: Int)
}

/// What a player is allowed to do right now — drives both the AI and the action bar UI.
nonisolated struct ActionConstraints: Sendable, Equatable {
    var toCall: Int          // additional chips needed to call (already capped by stack)
    var canCheck: Bool
    var canRaise: Bool       // false when betting is not reopened or no chips to raise with
    var minRaiseTo: Int      // minimum legal total (already capped at maxRaiseTo)
    var maxRaiseTo: Int      // all-in total
    var isOpeningBet: Bool   // true when currentBet == 0 (UI shows "Bet" instead of "Raise")
}

/// Last visible action, shown in a bubble next to the seat.
nonisolated enum ActionLabel: Sendable, Equatable {
    case smallBlind(Int)
    case bigBlind(Int)
    case fold
    case check
    case call(Int)
    case bet(Int)
    case raise(Int)
    case allIn(Int)

    var text: String {
        switch self {
        case .smallBlind(let n): return String(localized: "bubble.smallBlind \(n.chipText)")
        case .bigBlind(let n): return String(localized: "bubble.bigBlind \(n.chipText)")
        case .fold: return localized("action.fold")
        case .check: return localized("action.check")
        case .call(let n): return String(localized: "bubble.call \(n.chipText)")
        case .bet(let n): return String(localized: "bubble.bet \(n.chipText)")
        case .raise(let n): return String(localized: "bubble.raise \(n.chipText)")
        case .allIn(let n): return String(localized: "bubble.allIn \(n.chipText)")
        }
    }

    var isAggressive: Bool {
        switch self {
        case .bet, .raise, .allIn: return true
        default: return false
        }
    }
}

// MARK: - Player

nonisolated struct Player: Identifiable, Sendable {
    let id: Int                    // seat index, stable for the whole game
    var name: String
    var emoji: String
    var isHuman: Bool
    var chips: Int
    var personality: AIPersonality

    // Per-hand state
    var holeCards: [Card] = []
    var betThisStreet: Int = 0
    var totalInvested: Int = 0
    var hasFolded = false
    var isEliminated = false
    var revealedCards = false
    var lastAction: ActionLabel?

    var isInHand: Bool { !hasFolded && !isEliminated && !holeCards.isEmpty }
    var isAllIn: Bool { isInHand && chips == 0 }
    var canAct: Bool { isInHand && chips > 0 }

    mutating func resetForNewHand() {
        holeCards = []
        betThisStreet = 0
        totalInvested = 0
        hasFolded = false
        revealedCards = false
        lastAction = nil
    }

    /// Commits chips to the current street (capped by stack). Returns the amount actually paid.
    @discardableResult
    mutating func commit(_ amount: Int) -> Int {
        let paid = min(amount, chips)
        chips -= paid
        betThisStreet += paid
        totalInvested += paid
        return paid
    }
}

// MARK: - AI Personality

nonisolated struct AIPersonality: Sendable {
    /// 0 = plays everything, 1 = only premium hands.
    var tightness: Double
    /// 0 = never raises, 1 = raises constantly.
    var aggression: Double
    /// How often it fires with nothing.
    var bluffFrequency: Double
    /// How often it slow-plays monsters.
    var trapFrequency: Double

    static let human = AIPersonality(tightness: 0.5, aggression: 0.5, bluffFrequency: 0, trapFrequency: 0)
}

nonisolated struct AIProfile: Sendable, Identifiable, Equatable {
    let id: String
    let name: String
    let emoji: String
    let personality: AIPersonality

    /// Table-talk one-liner, looked up by profile id so it can be translated.
    var tagline: String { localized(.init("opponent.\(id).tagline")) }

    static func == (lhs: AIProfile, rhs: AIProfile) -> Bool { lhs.id == rhs.id }

    static let roster: [AIProfile] = [
        AIProfile(id: "viktor", name: "Viktor", emoji: "🦊",
                  personality: AIPersonality(tightness: 0.45, aggression: 0.75, bluffFrequency: 0.30, trapFrequency: 0.25)),
        AIProfile(id: "rosa", name: "Rosa", emoji: "🦉",
                  personality: AIPersonality(tightness: 0.75, aggression: 0.65, bluffFrequency: 0.12, trapFrequency: 0.35)),
        AIProfile(id: "moose", name: "Moose", emoji: "🐻",
                  personality: AIPersonality(tightness: 0.20, aggression: 0.25, bluffFrequency: 0.08, trapFrequency: 0.10)),
        AIProfile(id: "rex", name: "Rex", emoji: "🐯",
                  personality: AIPersonality(tightness: 0.15, aggression: 0.90, bluffFrequency: 0.45, trapFrequency: 0.05)),
        AIProfile(id: "greta", name: "Greta", emoji: "🐺",
                  personality: AIPersonality(tightness: 0.85, aggression: 0.40, bluffFrequency: 0.05, trapFrequency: 0.20)),
        AIProfile(id: "ace", name: "Ace", emoji: "🦅",
                  personality: AIPersonality(tightness: 0.55, aggression: 0.60, bluffFrequency: 0.20, trapFrequency: 0.20)),
    ]
}

// MARK: - Difficulty

nonisolated enum Difficulty: String, Sendable, CaseIterable, Codable, Identifiable {
    case easy = "Easy"
    case normal = "Normal"
    case hard = "Hard"

    var id: String { rawValue }

    var displayName: String { localized(.init("difficulty.\(rawValue.lowercased())")) }

    /// Random noise added to the AI's equity estimate.
    var equityNoise: Double {
        switch self {
        case .easy: return 0.16
        case .normal: return 0.07
        case .hard: return 0.025
        }
    }

    var monteCarloIterations: Int {
        switch self {
        case .easy: return 160
        case .normal: return 420
        case .hard: return 900
        }
    }

    /// How much the AI lets the betting narrow what opponents can hold.
    /// Easy opponents barely read the action; hard ones take it at face value.
    var rangeAwareness: Double {
        switch self {
        case .easy: return 0.35
        case .normal: return 0.75
        case .hard: return 1.0
        }
    }
}

// MARK: - Blinds

nonisolated struct BlindLevel: Sendable, Equatable {
    let smallBlind: Int
    let bigBlind: Int

    static let schedule: [BlindLevel] = [
        BlindLevel(smallBlind: 5, bigBlind: 10),
        BlindLevel(smallBlind: 10, bigBlind: 20),
        BlindLevel(smallBlind: 15, bigBlind: 30),
        BlindLevel(smallBlind: 25, bigBlind: 50),
        BlindLevel(smallBlind: 40, bigBlind: 80),
        BlindLevel(smallBlind: 60, bigBlind: 120),
        BlindLevel(smallBlind: 100, bigBlind: 200),
        BlindLevel(smallBlind: 150, bigBlind: 300),
        BlindLevel(smallBlind: 250, bigBlind: 500),
        BlindLevel(smallBlind: 400, bigBlind: 800),
        BlindLevel(smallBlind: 600, bigBlind: 1200),
        BlindLevel(smallBlind: 1000, bigBlind: 2000),
    ]
}

nonisolated enum BlindSpeed: String, Sendable, CaseIterable, Codable, Identifiable {
    case off = "Fixed"
    case slow = "Slow"
    case normal = "Normal"
    case turbo = "Turbo"

    var id: String { rawValue }

    var displayName: String { localized(.init("blindSpeed.\(rawValue.lowercased())")) }

    /// Hands per blind level; nil = blinds never increase.
    var handsPerLevel: Int? {
        switch self {
        case .off: return nil
        case .slow: return 15
        case .normal: return 10
        case .turbo: return 6
        }
    }
}

// MARK: - Game Config

nonisolated struct GameConfig: Sendable {
    var opponents: [AIProfile]
    var startingChips: Int
    var difficulty: Difficulty
    var blindSpeed: BlindSpeed
    /// Test hook: overrides only the human's starting stack.
    var humanStartingChips: Int?

    static let `default` = GameConfig(
        opponents: Array(AIProfile.roster.prefix(4)),
        startingChips: 1000,
        difficulty: .normal,
        blindSpeed: .normal)
}

// MARK: - Results

nonisolated struct PotResult: Sendable, Identifiable {
    let id: Int
    let amount: Int
    let eligibleSeats: [Int]
    let winnerSeats: [Int]
    let winningHandName: String?
    let isSidePot: Bool
}

nonisolated struct HandResult: Sendable {
    let potResults: [PotResult]
    /// Chips won per seat.
    let winnings: [Int: Int]
    /// Cards forming the overall best hand (for highlighting).
    let winningCards: Set<Card>
    /// Headline for the banner, e.g. "Viktor wins 340 with Two Pair".
    let headline: String
    let wentToShowdown: Bool
}

// MARK: - Saved game

/// A game snapshot taken at a hand boundary — stacks, button and hand number are
/// all that is needed to deal the next hand, so no mid-hand state is persisted.
nonisolated struct SavedGame: Codable, Sendable {
    var opponentIDs: [String]
    var startingChips: Int
    var difficulty: Difficulty
    var blindSpeed: BlindSpeed
    /// Chip counts by seat id; index 0 is the human.
    var stacks: [Int]
    var eliminated: [Bool]
    var dealerIndex: Int
    var handNumber: Int
    /// Seat that posted the last big blind, so the dead-button cycle survives a
    /// resume. Absent in saves written before dead-button rules existed.
    var bigBlindSeat: Int?
    /// Seat the last small blind fell to, dead or not. The button follows it, so
    /// without this a resume cannot tell where the button belongs. Absent in
    /// saves written before the blind cycle followed the players.
    var smallBlindSeat: Int?

    /// nil when the roster has changed since the snapshot was written.
    var config: GameConfig? {
        let profiles = opponentIDs.compactMap { id in AIProfile.roster.first { $0.id == id } }
        guard profiles.count == opponentIDs.count,
              stacks.count == profiles.count + 1,
              eliminated.count == stacks.count else { return nil }
        return GameConfig(opponents: profiles, startingChips: startingChips,
                          difficulty: difficulty, blindSpeed: blindSpeed)
    }

    var humanChips: Int { stacks.first ?? 0 }
    var opponentsLeft: Int { zip(stacks, eliminated).dropFirst().filter { !$0.1 }.count }
}

// MARK: - Formatting

nonisolated extension Int {
    /// Compact chip formatting. Exact below 10K so stack sizes stay readable
    /// at the table (950, 9999), abbreviated above it (12.5K, 1.1M).
    var chipText: String { chipText(in: .current) }

    /// Takes the locale rather than reading it, so the tests can pin one: the
    /// decimal separator is regional and asserting on it otherwise depends on
    /// how the simulator happens to be set up.
    func chipText(in locale: Locale) -> String {
        // 999_950 rather than 1_000_000: `trim` rounds to one decimal place, so
        // from there up the thousands branch reads "1000K" — a thousand
        // thousands, which is the thing the M form exists to say.
        if self >= 999_950 {
            return trim(Double(self) / 1_000_000, in: locale) + "M"
        }
        if self >= 10_000 {
            return trim(Double(self) / 1_000, in: locale) + "K"
        }
        return String(self)
    }

    private func trim(_ value: Double, in locale: Locale) -> String {
        let rounded = (value * 10).rounded() / 10
        guard rounded != rounded.rounded() else { return String(Int(rounded)) }
        // Czech writes 12,5 — and `String(format:)` with no locale always
        // writes a period, whatever the device is set to.
        return String(format: "%.1f", locale: locale, rounded)
    }
}
