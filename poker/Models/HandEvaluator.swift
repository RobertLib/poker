import Foundation

// MARK: - Hand Category

nonisolated enum HandCategory: Int, Comparable, Sendable, CaseIterable {
    case highCard, pair, twoPair, threeOfAKind, straight, flush
    case fullHouse, fourOfAKind, straightFlush, royalFlush

    var displayName: String {
        switch self {
        case .highCard: return localized("hand.highCard")
        case .pair: return localized("hand.pair")
        case .twoPair: return localized("hand.twoPair")
        case .threeOfAKind: return localized("hand.threeOfAKind")
        case .straight: return localized("hand.straight")
        case .flush: return localized("hand.flush")
        case .fullHouse: return localized("hand.fullHouse")
        case .fourOfAKind: return localized("hand.fourOfAKind")
        case .straightFlush: return localized("hand.straightFlush")
        case .royalFlush: return localized("hand.royalFlush")
        }
    }

    static func < (lhs: HandCategory, rhs: HandCategory) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - Evaluated Hand

/// The value of the best 5-card hand within a set of 5–7 cards.
/// `score` encodes category + tiebreakers so two hands compare with a single integer.
nonisolated struct HandValue: Comparable, Sendable {
    let category: HandCategory
    let score: UInt32
    let bestFive: [Card]

    static func < (lhs: HandValue, rhs: HandValue) -> Bool { lhs.score < rhs.score }
    static func == (lhs: HandValue, rhs: HandValue) -> Bool { lhs.score == rhs.score }

    /// A human-friendly description, e.g. "Kings Full of Nines".
    ///
    /// Each phrase asks the ranks for the grammatical form it needs, because
    /// Czech declines them differently in every one of these sentences.
    var name: String {
        let r = tiebreakRanks
        guard let first = r.first else { return category.displayName }
        let second = r.count > 1 ? r[1] : first

        switch category {
        case .highCard:
            return String(localized: "hand.name.highCard \(first.name(.singular))")
        case .pair:
            return String(localized: "hand.name.pair \(first.name(.pluralPossessive))")
        case .twoPair:
            return String(localized: "hand.name.twoPair \(first.name(.plural)) \(second.name(.plural))")
        case .threeOfAKind:
            return String(localized: "hand.name.threeOfAKind \(first.name(.pluralPossessive))")
        case .straight:
            return String(localized: "hand.name.straight \(first.name(.singularTarget))")
        case .flush:
            return String(localized: "hand.name.flush \(first.name(.singularTarget))")
        case .fullHouse:
            return String(localized: "hand.name.fullHouse \(first.name(.plural)) \(second.name(.plural))")
        case .fourOfAKind:
            return String(localized: "hand.name.fourOfAKind \(first.name(.pluralPossessive))")
        case .straightFlush:
            return String(localized: "hand.name.straightFlush \(first.name(.singularTarget))")
        case .royalFlush:
            return localized("hand.royalFlush")
        }
    }

    /// Tiebreaker ranks decoded from the score, most significant first.
    private var tiebreakRanks: [Rank] {
        var result: [Rank] = []
        for shift in stride(from: 16, through: 0, by: -4) {
            let nibble = Int((score >> UInt32(shift)) & 0xF)
            if let rank = Rank(rawValue: nibble) { result.append(rank) }
        }
        return result
    }
}

// MARK: - Evaluator

nonisolated enum HandEvaluator {

    /// Evaluates the best 5-card poker hand from 5–7 cards.
    static func evaluate(_ cards: [Card]) -> HandValue {
        precondition(cards.count >= 5 && cards.count <= 7, "Need 5–7 cards")

        // Group by rank (descending) and by suit.
        var byRank: [Int: [Card]] = [:]   // rank rawValue -> cards
        var bySuit: [Suit: [Card]] = [:]
        for card in cards {
            byRank[card.rank.rawValue, default: []].append(card)
            bySuit[card.suit, default: []].append(card)
        }

        // Flush / straight flush
        if let (_, suited) = bySuit.first(where: { $0.value.count >= 5 }) {
            let suitedSorted = suited.sorted { $0.rank > $1.rank }
            if let straightCards = straight(in: suitedSorted) {
                let high = straightCards[0].rank
                if high == .ace {
                    return HandValue(category: .royalFlush,
                                     score: encode(.royalFlush, [14]),
                                     bestFive: straightCards)
                }
                return HandValue(category: .straightFlush,
                                 score: encode(.straightFlush, [high.rawValue]),
                                 bestFive: straightCards)
            }
            // Plain flush cannot be beaten by quads/full house only if those don't exist,
            // so keep checking below; stash the flush for later.
            let flushValue = HandValue(category: .flush,
                                       score: encode(.flush, suitedSorted.prefix(5).map(\.rank.rawValue)),
                                       bestFive: Array(suitedSorted.prefix(5)))
            if let strong = quadsOrFullHouse(byRank: byRank) { return strong }
            return flushValue
        }

        if let strong = quadsOrFullHouse(byRank: byRank) { return strong }

        // Straight
        let allSorted = cards.sorted { $0.rank > $1.rank }
        if let straightCards = straight(in: allSorted) {
            return HandValue(category: .straight,
                             score: encode(.straight, [straightCards[0].rank.rawValue]),
                             bestFive: straightCards)
        }

        // Trips / two pair / pair / high card
        let groups = byRank.sorted { a, b in
            a.value.count != b.value.count ? a.value.count > b.value.count : a.key > b.key
        }

        let topGroup = groups[0]
        if topGroup.value.count == 3 {
            let kickers = kickerCards(from: groups.dropFirst(), count: 2)
            return HandValue(
                category: .threeOfAKind,
                score: encode(.threeOfAKind, [topGroup.key] + kickers.map(\.rank.rawValue)),
                bestFive: topGroup.value + kickers)
        }

        if topGroup.value.count == 2 {
            let second = groups[1]
            if second.value.count == 2 {
                // Two pair (with 7 cards there may be a third pair; take the top two, best kicker from the rest)
                let kickers = kickerCards(from: groups.dropFirst(2), count: 1)
                return HandValue(
                    category: .twoPair,
                    score: encode(.twoPair, [topGroup.key, second.key] + kickers.map(\.rank.rawValue)),
                    bestFive: topGroup.value + second.value + kickers)
            }
            let kickers = kickerCards(from: groups.dropFirst(), count: 3)
            return HandValue(
                category: .pair,
                score: encode(.pair, [topGroup.key] + kickers.map(\.rank.rawValue)),
                bestFive: topGroup.value + kickers)
        }

        let bestFive = Array(allSorted.prefix(5))
        return HandValue(category: .highCard,
                         score: encode(.highCard, bestFive.map(\.rank.rawValue)),
                         bestFive: bestFive)
    }

    // MARK: Helpers

    private static func quadsOrFullHouse(byRank: [Int: [Card]]) -> HandValue? {
        let groups = byRank.sorted { a, b in
            a.value.count != b.value.count ? a.value.count > b.value.count : a.key > b.key
        }
        let top = groups[0]

        if top.value.count == 4 {
            let kicker = kickerCards(from: groups.dropFirst(), count: 1)
            return HandValue(category: .fourOfAKind,
                             score: encode(.fourOfAKind, [top.key] + kicker.map(\.rank.rawValue)),
                             bestFive: top.value + kicker)
        }

        if top.value.count == 3 {
            // Best pair to fill the house: another trips counts as a pair too.
            let pairGroup = groups.dropFirst().first { $0.value.count >= 2 }
            if let pair = pairGroup {
                return HandValue(
                    category: .fullHouse,
                    score: encode(.fullHouse, [top.key, pair.key]),
                    bestFive: top.value + pair.value.prefix(2))
            }
        }
        return nil
    }

    /// Finds the highest 5-card straight in cards sorted by rank descending. Handles the wheel (A-5).
    private static func straight(in sorted: [Card]) -> [Card]? {
        // One representative card per rank, descending.
        var unique: [Card] = []
        for card in sorted where unique.last?.rank != card.rank {
            unique.append(card)
        }
        guard unique.count >= 5 else { return wheel(in: unique) }

        for start in 0...(unique.count - 5) {
            let run = Array(unique[start..<(start + 5)])
            if run[0].rank.rawValue - run[4].rank.rawValue == 4 {
                return run
            }
        }
        return wheel(in: unique)
    }

    /// A-2-3-4-5 straight; the five is the high card.
    ///
    /// Returning the five first is also what makes the wheel score *below* a
    /// six-high straight: `encode` reads the run's first card, so no special
    /// case is needed anywhere else.
    private static func wheel(in unique: [Card]) -> [Card]? {
        let needed: [Rank] = [.five, .four, .three, .two, .ace]
        var result: [Card] = []
        for rank in needed {
            guard let card = unique.first(where: { $0.rank == rank }) else { return nil }
            result.append(card)
        }
        return result
    }

    private static func kickerCards<S: Sequence>(from groups: S, count: Int) -> [Card]
    where S.Element == (key: Int, value: [Card]) {
        // Groups are pre-sorted by (count, rank) — for kickers we want pure rank order.
        let singles = groups.flatMap(\.value).sorted { $0.rank > $1.rank }
        return Array(singles.prefix(count))
    }

    private static func encode(_ category: HandCategory, _ ranks: [Int]) -> UInt32 {
        var score = UInt32(category.rawValue) << 20
        var shift: UInt32 = 16
        for rank in ranks.prefix(5) {
            score |= UInt32(rank) << shift
            shift = shift >= 4 ? shift - 4 : 0
        }
        return score
    }
}
