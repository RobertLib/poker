import Testing
@testable import poker

@Suite("Hand evaluator")
struct HandEvaluatorTests {

    private func value(_ hand: String) -> HandValue { HandEvaluator.evaluate(cards(hand)) }

    // MARK: Categories

    @Test func recognisesEveryCategory() {
        #expect(value("As Ks Qs Js Ts").category == .royalFlush)
        #expect(value("9h 8h 7h 6h 5h").category == .straightFlush)
        #expect(value("7h 7d 7c 7s Kh").category == .fourOfAKind)
        #expect(value("Jc Jh Js 9d 9c").category == .fullHouse)
        #expect(value("Ad Jd 8d 6d 2d").category == .flush)
        #expect(value("Tc 9h 8s 7d 6c").category == .straight)
        #expect(value("8s 8d 8h Kc 4s").category == .threeOfAKind)
        #expect(value("Ac Ah 9s 9d 5h").category == .twoPair)
        #expect(value("Th Ts Ad 7c 3h").category == .pair)
        #expect(value("As Qd 9c 6h 3s").category == .highCard)
    }

    @Test func scoreIsMonotoneAcrossCategories() {
        let weakest = [
            "Ah Kd 9c 7s 4h", "2h 2d 9c 7s 4h", "2h 2d 3c 3s 4h", "2h 2d 2c 7s 4h",
            "2h 3d 4c 5s 6h", "2h 5h 7h 9h Jh", "2h 2d 2c 3s 3h", "2h 2d 2c 2s 3h",
            "2h 3h 4h 5h 6h", "Ah Kh Qh Jh Th",
        ]
        let scores = weakest.map { value($0).score }
        #expect(scores == scores.sorted(), "each category must outscore the one below it")
    }

    // MARK: Straights

    @Test func theWheelIsFiveHigh() {
        let wheel = value("Ac 2d 3h 4s 5c")
        #expect(wheel.category == .straight)
        #expect(wheel.name.contains(Rank.five.name(.singularTarget)), "named \(wheel.name)")
        #expect(!wheel.name.contains(Rank.ace.name(.singularTarget)), "the ace plays low: \(wheel.name)")
        #expect(wheel.score < value("6c 2d 3h 4s 5c").score, "the wheel is the weakest straight")
        #expect(wheel.score > value("Kc Kd Kh 4s 5c").score, "but it still beats trips")
    }

    @Test func steelWheelIsAStraightFlushNotRoyal() {
        let steel = value("As 2s 3s 4s 5s")
        #expect(steel.category == .straightFlush)
        #expect(steel.name.contains(Rank.five.name(.singularTarget)), "named \(steel.name)")
        #expect(steel.name != HandCategory.royalFlush.displayName)
    }

    @Test func picksTheHighestStraightFromSeven() {
        let hand = value("Ac 2d 3h 4s 5c 6d 7h")
        #expect(hand.category == .straight)
        #expect(hand.name.contains(Rank.seven.name(.singularTarget)), "named \(hand.name)")
    }

    // MARK: Seven-card selection

    @Test func threePairsPlayTheTopTwoWithTheBestKicker() {
        let hand = value("Ah Ad Kh Kd Qh Qd 2c")
        #expect(hand.category == .twoPair)
        #expect(hand.name.contains(Rank.ace.name(.plural)), "named \(hand.name)")
        #expect(hand.name.contains(Rank.king.name(.plural)), "named \(hand.name)")
        #expect(!hand.name.contains(Rank.queen.name(.plural)), "the queens are only a kicker: \(hand.name)")
        #expect(hand.bestFive.contains { $0.rank == .queen }, "the queen outkicks the deuce")
        #expect(!hand.bestFive.contains(card("2c")))
    }

    @Test func twoTripsMakeTheBetterFullHouse() {
        let hand = value("9h 9d 9c 5h 5d 5c 2s")
        #expect(hand.category == .fullHouse)
        #expect(hand.name.contains(Rank.nine.name(.plural)), "named \(hand.name)")
        #expect(hand.name.contains(Rank.five.name(.plural)), "named \(hand.name)")
    }

    @Test func sixCardFlushTakesTheTopFive() {
        let hand = value("As Ks 9s 7s 4s 2s 3h")
        #expect(hand.category == .flush)
        #expect(Set(hand.bestFive) == Set(cards("As Ks 9s 7s 4s")))
    }

    @Test func straightFlushBeatsTheAceHighFlushInTheSameHand() {
        #expect(value("9s 8s 7s 6s 5s As 2h").category == .straightFlush)
    }

    @Test func quadsTakeTheHighestKicker() {
        let hand = value("7h 7d 7c 7s Kh Kd 2c")
        #expect(hand.category == .fourOfAKind)
        #expect(hand.bestFive.contains { $0.rank == .king })
    }

    // MARK: Reference check

    /// The fast 7-card evaluator has to agree with the obvious-but-slow
    /// definition: the best of all twenty-one 5-card subsets.
    @Test func matchesBruteForceOverManyRandomHands() {
        func bruteForceBest(_ seven: [Card]) -> HandValue {
            var best: HandValue?
            for a in 0..<7 { for b in (a+1)..<7 { for c in (b+1)..<7 {
                for d in (c+1)..<7 { for e in (d+1)..<7 {
                    let candidate = HandEvaluator.evaluate([seven[a], seven[b], seven[c], seven[d], seven[e]])
                    if best == nil || candidate.score > best!.score { best = candidate }
                }}}}}
            return best!
        }

        var rng = SplitMix64(seed: 0x5EED_5EED)
        var deck = Card.fullDeck
        for _ in 0..<20_000 {
            for i in 0..<7 {
                deck.swapAt(i, i + Int(rng.next(upperBound: UInt64(deck.count - i))))
            }
            let seven = Array(deck.prefix(7))
            let fast = HandEvaluator.evaluate(seven)
            let slow = bruteForceBest(seven)

            #expect(fast.score == slow.score, "\(describe(seven)): \(fast.name) vs \(slow.name)")
            #expect(fast.category == slow.category, "\(describe(seven))")
            #expect(fast.bestFive.count == 5)
            #expect(Set(fast.bestFive).count == 5, "best five must be distinct: \(describe(fast.bestFive))")
            #expect(Set(fast.bestFive).isSubset(of: Set(seven)), "best five must come from the hand")
            #expect(HandEvaluator.evaluate(fast.bestFive).score == fast.score,
                    "best five must re-evaluate to the same score")
        }
    }

    @Test func everyHandHasAReadableName() {
        var rng = SplitMix64(seed: 7)
        var deck = Card.fullDeck
        for _ in 0..<5_000 {
            for i in 0..<7 {
                deck.swapAt(i, i + Int(rng.next(upperBound: UInt64(deck.count - i))))
            }
            #expect(!HandEvaluator.evaluate(Array(deck.prefix(7))).name.isEmpty)
        }
    }

    /// `StatsStore` keeps the record hand as its encoded score rather than as
    /// the finished sentence, because that sentence is localised and a record
    /// set on a Czech device would otherwise still read in Czech after the
    /// phone was switched to English. That only works while the score is
    /// enough to say the name again — category included, and without the five
    /// cards, which are not stored.
    @Test func aHandValueRebuiltFromItsScoreAloneKeepsItsName() throws {
        var rng = SplitMix64(seed: 90_210)
        var deck = Card.fullDeck
        for _ in 0..<2_000 {
            for i in 0..<7 {
                deck.swapAt(i, i + Int(rng.next(upperBound: UInt64(deck.count - i))))
            }
            let original = HandEvaluator.evaluate(Array(deck.prefix(7)))
            // The category rides in the bits above the tiebreakers, which is
            // what lets one stored integer stand in for the whole record.
            let category = try #require(HandCategory(rawValue: Int(original.score >> 20)))
            #expect(category == original.category)

            let rebuilt = HandValue(category: category, score: original.score, bestFive: [])
            #expect(rebuilt.name == original.name,
                    "\(describe(original.bestFive)): \"\(original.name)\" came back as \"\(rebuilt.name)\"")
        }
    }
}

@Suite("Deck")
struct DeckTests {

    @Test func dealsFiftyTwoDistinctCards() {
        var deck = Deck()
        #expect(Set(deck.deal(52)).count == 52)
    }

    @Test func stackedDeckDealsInTheGivenOrder() {
        var deck = Deck(stacked: cards("As Kd 2c"))
        #expect(deck.deal() == card("As"))
        #expect(deck.deal() == card("Kd"))
        #expect(deck.deal() == card("2c"))
    }

    @Test func stackedDeckStillHoldsAWholePack() {
        var deck = Deck(stacked: cards("As Kd"))
        #expect(Set(deck.deal(52)).count == 52)
    }
}
