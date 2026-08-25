import Foundation
import Testing
@testable import poker

// MARK: - Card literals

/// Parses a card written the way people say it: "As", "Th", "2c".
func card(_ text: String) -> Card {
    let suits: [Character: Suit] = ["c": .clubs, "d": .diamonds, "h": .hearts, "s": .spades]
    let ranks: [String: Rank] = [
        "2": .two, "3": .three, "4": .four, "5": .five, "6": .six, "7": .seven,
        "8": .eight, "9": .nine, "T": .ten, "J": .jack, "Q": .queen, "K": .king, "A": .ace,
    ]
    guard let suit = text.last.flatMap({ suits[$0] }),
          let rank = ranks[String(text.dropLast())] else {
        fatalError("Not a card: \(text)")
    }
    return Card(rank: rank, suit: suit)
}

func cards(_ text: String) -> [Card] {
    text.split(separator: " ").map { card(String($0)) }
}

func describe(_ cards: [Card]) -> String {
    cards.map(\.description).joined(separator: " ")
}

// MARK: - Games under test

@MainActor
func makeGame(opponents: Int, chips: Int = 1000, blindSpeed: BlindSpeed = .off,
              difficulty: Difficulty = .easy) -> PokerGame {
    let config = GameConfig(
        opponents: Array(AIProfile.roster.prefix(opponents)),
        startingChips: chips,
        difficulty: difficulty,
        blindSpeed: blindSpeed)
    let game = PokerGame(config: config)
    game.instantMode = true
    return game
}

/// Feeds scripted actions to the engine and records the constraints each seat
/// was offered, so rule questions can be asked of the history afterwards.
@MainActor
final class Script {
    var actions: [(seat: Int, action: PlayerAction)] = []
    private(set) var history: [(seat: Int, constraints: ActionConstraints)] = []
    var fallback: PlayerAction = .fold

    init(_ actions: [(seat: Int, action: PlayerAction)] = []) {
        self.actions = actions
    }

    /// Captures the script strongly: its lifetime should follow the game's, and
    /// a script that quietly died would silently fall back to folding.
    func install(on game: PokerGame) {
        game.actionOverride = { seat, constraints in
            self.history.append((seat, constraints))
            if let index = self.actions.firstIndex(where: { $0.seat == seat }) {
                return self.actions.remove(at: index).action
            }
            return self.fallback
        }
    }

    func constraints(forSeat seat: Int) -> [ActionConstraints] {
        history.filter { $0.seat == seat }.map(\.constraints)
    }
}

/// A player built directly, for pot-splitting tests that don't need an engine.
func testPlayer(_ id: Int, invested: Int, folded: Bool = false, holdsCards: Bool = true) -> Player {
    var player = Player(id: id, name: "P\(id)", emoji: "🙂", isHuman: false,
                        chips: 100, personality: .human)
    player.totalInvested = invested
    player.hasFolded = folded
    if holdsCards { player.holeCards = [card("2c"), card("3d")] }
    return player
}

// MARK: - Deterministic randomness

/// Reproducible pseudo-random action picker for fuzzing.
struct FuzzActor {
    private var rng: SplitMix64

    init(seed: UInt64) { rng = SplitMix64(seed: seed) }

    mutating func roll(_ upperBound: UInt64) -> Int { Int(rng.next(upperBound: upperBound)) }

    /// Mixes legal play with deliberately illegal requests — the engine has to
    /// sanitise those rather than trust its caller.
    mutating func action(for constraints: ActionConstraints) -> PlayerAction {
        switch roll(100) {
        case ..<10: return .fold
        case ..<32: return constraints.canCheck ? .check : .fold
        case ..<58: return .call
        case ..<64: return .check                     // often illegal
        case ..<84:
            let span = max(constraints.maxRaiseTo - constraints.minRaiseTo, 0)
            return .raise(to: constraints.minRaiseTo + roll(UInt64(span + 1)))
        case ..<90: return .raise(to: constraints.maxRaiseTo)
        case ..<95: return .raise(to: -5)             // illegal
        default: return .raise(to: Int.max / 4)       // illegal
        }
    }
}
