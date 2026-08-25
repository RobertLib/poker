import Foundation

// MARK: - Decision Input

nonisolated struct AIDecisionInput: Sendable {
    let holeCards: [Card]
    let communityCards: [Card]
    let street: Street
    let potTotal: Int
    let toCall: Int
    let canRaise: Bool
    let minRaiseTo: Int
    let maxRaiseTo: Int
    let myBetThisStreet: Int
    let myChips: Int
    let currentBet: Int
    let bigBlind: Int
    let opponentsInHand: Int
    /// 0 = first to act post-flop, 1 = on the button.
    let positionScore: Double
    /// How far the betting so far narrows what opponents can be holding.
    /// 0 = any two cards; higher values simulate them holding stronger hands.
    let opponentRange: Double
    let personality: AIPersonality
    let difficulty: Difficulty
}

// MARK: - AI Brain

/// Equity-driven decision making. Every AI estimates its win probability via
/// Monte Carlo simulation (with difficulty-based noise), compares it against
/// pot odds, and colors the decision with its personality: tightness,
/// aggression, bluffing and trapping.
nonisolated enum AIBrain {

    // MARK: Equity (Monte Carlo)

    /// Rough pre-flop strength of a starting hand, normalised to 0...1.
    /// A Chen-style score — high card, pair, suitedness, connectedness — chosen
    /// because it has to run inside the Monte Carlo loop.
    static func startingHandStrength(_ a: Card, _ b: Card) -> Double {
        let high = max(a.rank.rawValue, b.rank.rawValue)
        let low = min(a.rank.rawValue, b.rank.rawValue)

        var score: Double
        switch high {
        case 14: score = 10
        case 13: score = 8
        case 12: score = 7
        case 11: score = 6
        default: score = Double(high) / 2
        }

        if high == low {
            score = max(score * 2, 5)               // pair
        } else {
            switch high - low {
            case 1: break
            case 2: score -= 1
            case 3: score -= 2
            case 4: score -= 4
            default: score -= 5
            }
            if high - low <= 2 && high < 12 { score += 1 }   // straight potential
        }
        if a.suit == b.suit { score += 2 }

        return min(max((score + 2) / 22, 0), 1)
    }

    /// Every starting hand's strength, sorted ascending. Turns "the top X% of
    /// hands" into a concrete cutoff, so ranges can be expressed the way poker
    /// players think about them rather than in raw Chen points.
    private static let sortedStartingStrengths: [Double] = {
        var values: [Double] = []
        values.reserveCapacity(1326)
        let deck = Card.fullDeck
        for i in 0..<deck.count {
            for j in (i + 1)..<deck.count {
                values.append(startingHandStrength(deck[i], deck[j]))
            }
        }
        return values.sorted()
    }()

    /// Strength cutoff that keeps roughly the strongest `fraction` of all hands.
    static func strengthCutoff(keepingTop fraction: Double) -> Double {
        let clamped = min(max(fraction, 0.10), 1)     // never so tight that
        guard clamped < 1 else { return 0 }           // re-dealing keeps failing
        let index = Int(Double(sortedStartingStrengths.count) * (1 - clamped))
        return sortedStartingStrengths[min(index, sortedStartingStrengths.count - 1)]
    }

    /// Probability of winning at showdown against `opponents` hands.
    /// Ties count as fractional wins.
    ///
    /// - Parameter opponentRange: 0 simulates opponents holding any two cards.
    ///   Higher values reject weak holdings, modelling the fact that a player
    ///   who has put in a big raise is not turning up with seven-deuce.
    static func equity(hole: [Card], board: [Card], opponents: Int, iterations: Int,
                       opponentRange: Double = 0) -> Double {
        guard hole.count == 2, opponents >= 1 else { return 0 }
        let known = Set(hole + board)
        let stub = Card.fullDeck.filter { !known.contains($0) }
        let boardNeeded = 5 - board.count
        let drawCount = opponents * 2 + boardNeeded
        let spare = max(stub.count - drawCount, 0)   // cards left over for re-deals
        // range 0 → any two cards; range 1 → roughly the top tenth of hands.
        let cutoff = opponentRange > 0.01
            ? strengthCutoff(keepingTop: 1 - opponentRange * 0.9)
            : 0

        var rng = SplitMix64(seed: UInt64.random(in: .min ... .max))
        var pool = stub
        var winSum = 0.0

        for _ in 0..<iterations {
            // Partial Fisher–Yates: shuffle only the cards we need.
            for i in 0..<drawCount {
                let j = i + Int(rng.next(upperBound: UInt64(pool.count - i)))
                pool.swapAt(i, j)
            }

            // Re-deal any opponent whose hand is too weak for the range they
            // are representing, swapping with cards this iteration hasn't used.
            if cutoff > 0 && spare > 1 {
                for o in 0..<opponents {
                    let base = boardNeeded + o * 2
                    var attempts = 0
                    while attempts < 24,
                          startingHandStrength(pool[base], pool[base + 1]) < cutoff {
                        pool.swapAt(base, drawCount + Int(rng.next(upperBound: UInt64(spare))))
                        pool.swapAt(base + 1, drawCount + Int(rng.next(upperBound: UInt64(spare))))
                        attempts += 1
                    }
                }
            }

            var fullBoard = board
            for i in 0..<boardNeeded { fullBoard.append(pool[i]) }

            let myScore = HandEvaluator.evaluate(hole + fullBoard).score
            var tiedOpponents = 0
            var lost = false
            for o in 0..<opponents {
                let base = boardNeeded + o * 2
                let opponentHole = [pool[base], pool[base + 1]]
                let score = HandEvaluator.evaluate(opponentHole + fullBoard).score
                if score > myScore { lost = true; break }
                if score == myScore { tiedOpponents += 1 }
            }
            if lost { continue }
            winSum += tiedOpponents == 0 ? 1.0 : 1.0 / Double(tiedOpponents + 1)
        }
        return winSum / Double(iterations)
    }

    // MARK: Decision

    static func decide(_ input: AIDecisionInput) -> PlayerAction {
        let difficulty = input.difficulty

        var equity = equity(
            hole: input.holeCards,
            board: input.communityCards,
            opponents: max(input.opponentsInHand, 1),
            iterations: difficulty.monteCarloIterations,
            opponentRange: input.opponentRange * difficulty.rangeAwareness)
        equity += Double.random(in: -difficulty.equityNoise...difficulty.equityNoise)
        if difficulty == .hard {
            equity += (input.positionScore - 0.5) * 0.05
        }
        equity = min(max(equity, 0.02), 0.98)

        if input.street == .preflop {
            return preflop(input, equity: equity)
        }
        return postflop(input, equity: equity)
    }

    // MARK: Pre-flop

    private static func preflop(_ input: AIDecisionInput, equity: Double) -> PlayerAction {
        let p = input.personality
        let baseline = 1.0 / Double(input.opponentsInHand + 1)
        let edge = equity - baseline
        let stack = input.myChips + input.myBetThisStreet
        let stackInBB = Double(stack) / Double(input.bigBlind)
        let facingRaise = input.currentBet > input.bigBlind
        let toCall = input.toCall

        // Short stack: push or fold.
        if stackInBB < 11 {
            // Facing a raise means facing a stronger range: demand more edge.
            let shoveThreshold = 0.02 + p.tightness * 0.05 + (facingRaise ? 0.03 : 0.0)
            if edge > shoveThreshold && input.canRaise {
                return .raise(to: input.maxRaiseTo)
            }
            if toCall == 0 { return .check }
            let price = price(toCall: toCall, pot: input.potTotal)
            return equity > price + 0.04 ? .call : .fold
        }

        if !facingRaise {
            // Unopened pot (or limps): raise, limp along, check or fold.
            let openThreshold = 0.025 + p.tightness * 0.055 - input.positionScore * 0.02
            if edge > openThreshold && input.canRaise {
                if chance(0.82 + p.aggression * 0.15) {
                    let sizeBB = 2.4 + p.aggression * 1.2 + Double.random(in: 0...0.7)
                    return raiseAction(input, to: Int(sizeBB * Double(input.bigBlind)))
                }
                return toCall > 0 ? .call : .check
            }
            // Occasional loose open as a bluff.
            if input.canRaise && chance(p.bluffFrequency * 0.15 * (0.5 + input.positionScore)) {
                return raiseAction(input, to: Int(2.5 * Double(input.bigBlind)))
            }
            if toCall == 0 { return .check }
            // Limp-in for playable hands (looser players limp more).
            let limpThreshold = -0.015 + p.tightness * 0.05
            if edge > limpThreshold && toCall <= input.bigBlind { return .call }
            return .fold
        }

        // Facing a raise.
        let price = price(toCall: toCall, pot: input.potTotal)
        let threeBetThreshold = 0.11 + p.tightness * 0.05
        if edge > threeBetThreshold && input.canRaise && chance(0.35 + p.aggression * 0.45) {
            let target = Int(Double(input.currentBet) * Double.random(in: 2.4...3.1))
            return raiseAction(input, to: target)
        }
        // Bluff 3-bet.
        if input.canRaise && edge > -0.02 && chance(p.bluffFrequency * 0.12) {
            let target = Int(Double(input.currentBet) * 2.6)
            return raiseAction(input, to: target)
        }
        let callMargin = (0.5 - p.tightness) * 0.07
        // Speculative hands close enough in price can call (implied odds).
        let implied = toCall <= stack / 12 ? 0.03 : 0.0
        if equity + callMargin + implied > price {
            return .call
        }
        return .fold
    }

    // MARK: Post-flop

    private static func postflop(_ input: AIDecisionInput, equity: Double) -> PlayerAction {
        let p = input.personality
        let drawsToCome = input.street != .river
        let headsUp = input.opponentsInHand == 1
        let pot = max(input.potTotal, input.bigBlind * 2)

        if input.toCall <= 0 {
            // Checked to us.
            if equity > 0.80 {
                if drawsToCome && chance(p.trapFrequency) && headsUp {
                    return .check   // slow-play the monster
                }
                return betAction(input, fraction: Double.random(in: 0.6...0.85), pot: pot)
            }
            if equity > 0.55 {
                if chance(0.30 + p.aggression * 0.45) {
                    return betAction(input, fraction: Double.random(in: 0.45...0.65), pot: pot)
                }
                return .check
            }
            if equity > 0.32 && drawsToCome {
                // Semi-bluff with live equity.
                if chance(p.aggression * 0.35) {
                    return betAction(input, fraction: Double.random(in: 0.5...0.7), pot: pot)
                }
                return .check
            }
            // Air: pure bluff sometimes, more often in position and heads-up.
            let bluffChance = p.bluffFrequency * (0.35 + input.positionScore * 0.45) * (headsUp ? 1.0 : 0.35)
            if chance(bluffChance) {
                return betAction(input, fraction: Double.random(in: 0.5...0.75), pot: pot)
            }
            return .check
        }

        // Facing a bet.
        let price = price(toCall: input.toCall, pot: input.potTotal)
        let valueRaiseThreshold = 0.70 + p.tightness * 0.06 - (input.street == .river ? 0.02 : 0.0)

        if equity > valueRaiseThreshold && input.canRaise && chance(0.40 + p.aggression * 0.45) {
            let target = input.myBetThisStreet + input.toCall * 3 + Int(Double(pot) * 0.4)
            return raiseAction(input, to: target)
        }
        // Bluff check-raise / raise.
        if input.canRaise && headsUp && equity < 0.38 && drawsToCome
            && chance(p.bluffFrequency * 0.18) {
            let target = input.myBetThisStreet + input.toCall * 3
            return raiseAction(input, to: target)
        }

        var callMargin = (0.5 - p.tightness) * 0.06
        if drawsToCome && equity > 0.24 && equity < 0.52 {
            callMargin += 0.045   // implied odds on draws
        }
        let facingAllInForMe = input.toCall >= input.myChips
        if facingAllInForMe {
            callMargin -= 0.03 + p.tightness * 0.04
        }
        if equity + callMargin > price {
            return .call
        }
        return .fold
    }

    // MARK: Sizing helpers

    private static func betAction(_ input: AIDecisionInput, fraction: Double, pot: Int) -> PlayerAction {
        raiseAction(input, to: input.myBetThisStreet + Int(Double(pot) * fraction))
    }

    private static func raiseAction(_ input: AIDecisionInput, to target: Int) -> PlayerAction {
        guard input.canRaise else { return input.toCall > 0 ? .call : .check }
        var to = roundToChips(target)
        to = max(input.minRaiseTo, min(to, input.maxRaiseTo))
        // If the raise commits most of the stack, just ship it.
        let stack = input.myChips + input.myBetThisStreet
        if Double(to) > Double(stack) * 0.62 {
            to = input.maxRaiseTo
        }
        return .raise(to: to)
    }

    private static func roundToChips(_ amount: Int) -> Int {
        amount >= 100 ? (amount / 10) * 10 : (amount / 5) * 5
    }

    private static func price(toCall: Int, pot: Int) -> Double {
        Double(toCall) / Double(max(pot + toCall, 1))
    }

    private static func chance(_ probability: Double) -> Bool {
        Double.random(in: 0..<1) < probability
    }
}

// MARK: - Fast RNG

nonisolated struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func next(upperBound: UInt64) -> UInt64 {
        guard upperBound > 0 else { return 0 }
        return next() % upperBound
    }
}
