import Testing
@testable import poker

@Suite("AI equity")
struct EquityTests {

    @Test func matchesKnownHeadsUpNumbers() {
        let aces = AIBrain.equity(hole: cards("As Ah"), board: [], opponents: 1, iterations: 20_000)
        #expect(abs(aces - 0.852) < 0.02, "aces run about 85% heads-up, got \(aces)")

        let trash = AIBrain.equity(hole: cards("7c 2d"), board: [], opponents: 1, iterations: 20_000)
        #expect(abs(trash - 0.354) < 0.03, "seven-deuce runs about 35%, got \(trash)")

        let sixWay = AIBrain.equity(hole: cards("As Ah"), board: [], opponents: 5, iterations: 20_000)
        #expect(abs(sixWay - 0.49) < 0.05, "aces against five runs about 49%, got \(sixWay)")
    }

    @Test func recognisesLocksAndDeadHeats() {
        let nuts = AIBrain.equity(hole: cards("As Ks"), board: cards("Qs Js Ts"),
                                  opponents: 3, iterations: 8_000)
        #expect(nuts > 0.99, "a flopped royal cannot lose, got \(nuts)")

        let boardPlays = AIBrain.equity(hole: cards("2c 3d"), board: cards("As Ks Qs Js Ts"),
                                        opponents: 1, iterations: 8_000)
        #expect(abs(boardPlays - 0.5) < 0.03, "a royal on the board splits, got \(boardPlays)")
    }

    @Test func alwaysReturnsAProbability() {
        var deck = Card.fullDeck
        for _ in 0..<100 {
            deck.shuffle()
            let equity = AIBrain.equity(hole: Array(deck.prefix(2)), board: Array(deck[2..<5]),
                                        opponents: 2, iterations: 300)
            #expect((0...1).contains(equity))
        }
    }

    @Test func startingHandStrengthRanksHandsSensibly() {
        let aces = AIBrain.startingHandStrength(card("As"), card("Ah"))
        let bigSuited = AIBrain.startingHandStrength(card("As"), card("Ks"))
        let bigOffsuit = AIBrain.startingHandStrength(card("As"), card("Kh"))
        let trash = AIBrain.startingHandStrength(card("7c"), card("2d"))

        #expect(aces > bigSuited)
        #expect(bigSuited > bigOffsuit, "suited is worth more than offsuit")
        #expect(bigOffsuit > trash)
        #expect((0...1).contains(trash))
    }

    /// Narrowing the range the opposition is modelled on may only ever cost a
    /// marginal hand equity — never hand it some back.
    @Test func narrowingTheRangeNeverRaisesEquity() {
        var previous = 1.0
        for step in 0...5 {
            let range = Double(step) * 0.2
            let equity = AIBrain.equity(hole: cards("Ks Qs"), board: [], opponents: 1,
                                        iterations: 30_000, opponentRange: range)
            #expect(equity <= previous + 0.015, "equity rose at range \(range): \(equity) > \(previous)")
            previous = equity
        }
    }

    @Test func premiumHandsHoldUpAgainstNarrowRanges() {
        let wide = AIBrain.equity(hole: cards("As Ah"), board: [], opponents: 1,
                                  iterations: 20_000, opponentRange: 0)
        let narrow = AIBrain.equity(hole: cards("As Ah"), board: [], opponents: 1,
                                    iterations: 20_000, opponentRange: 1)
        #expect(narrow > 0.78, "aces stay strong even against a tight range, got \(narrow)")
        #expect(wide - narrow < 0.10, "aces should not lose much to a range read")
    }
}

@Suite("AI decisions")
@MainActor
struct AIDecisionTests {

    private func input(_ hole: String, toCall: Int, currentBet: Int, pot: Int,
                       range: Double, difficulty: Difficulty) -> AIDecisionInput {
        AIDecisionInput(
            holeCards: cards(hole), communityCards: [], street: .preflop,
            potTotal: pot, toCall: toCall, canRaise: true,
            minRaiseTo: currentBet * 2, maxRaiseTo: 1000, myBetThisStreet: 0,
            myChips: 1000, currentBet: currentBet, bigBlind: 10,
            opponentsInHand: 1, positionScore: 0.5, opponentRange: range,
            personality: AIProfile.roster.first { $0.id == "ace" }!.personality,
            difficulty: difficulty)
    }

    private func tally(_ hole: String, toCall: Int, currentBet: Int, pot: Int, range: Double,
                       difficulty: Difficulty = .hard, trials: Int = 200)
    -> (folds: Int, passive: Int, raises: Int) {
        var folds = 0, passive = 0, raises = 0
        for _ in 0..<trials {
            switch AIBrain.decide(input(hole, toCall: toCall, currentBet: currentBet,
                                        pot: pot, range: range, difficulty: difficulty)) {
            case .fold: folds += 1
            case .raise: raises += 1
            case .call, .check: passive += 1
            }
        }
        return (folds, passive, raises)
    }

    @Test func trashFoldsToABigThreeBetButAcesNeverDo() {
        let trash = tally("7c 2d", toCall: 100, currentBet: 100, pot: 115, range: 1)
        #expect(trash.folds >= 190, "seven-deuce folded only \(trash.folds)/200 times")

        let aces = tally("As Ah", toCall: 100, currentBet: 100, pot: 115, range: 1)
        #expect(aces.folds == 0, "aces folded \(aces.folds) times")
        #expect(aces.raises > 60, "aces four-bet only \(aces.raises)/200 times")
    }

    /// A-T suited runs at about 0.65 against any two cards but only 0.46 against
    /// a top-tenth range, so a price of 150-to-win-310 (0.484) sits squarely
    /// between the two: a clear call if the raise means nothing, a clear fold if
    /// it means something. Both sides are pinned with real headroom rather than
    /// compared against each other — the old version counted folds in a spot
    /// where the wide case never folded and the narrow case averaged two per two
    /// hundred, so `narrow > wide` came up false about one run in seven.
    @Test func aMarginalHandRespectsANarrowRange() {
        let againstAnything = tally("Ah Th", toCall: 150, currentBet: 150, pot: 160, range: 0)
        #expect(againstAnything.folds <= 10,
                "a raise that means nothing should not fold A-T suited: \(againstAnything.folds)/200")

        let againstPremiums = tally("Ah Th", toCall: 150, currentBet: 150, pot: 160, range: 1)
        #expect(againstPremiums.folds >= 100,
                "against a top-tenth range A-T suited must fold most of the time: \(againstPremiums.folds)/200")
        #expect(againstPremiums.folds > againstAnything.folds)
    }

    @Test func difficultyGatesHowMuchTheBettingIsRespected() {
        let easy = tally("8c 7d", toCall: 100, currentBet: 100, pot: 115, range: 1, difficulty: .easy)
        let hard = tally("8c 7d", toCall: 100, currentBet: 100, pot: 115, range: 1, difficulty: .hard)
        #expect(hard.folds >= easy.folds, "hard \(hard.folds) vs easy \(easy.folds)")
    }

    /// The engine sanitises illegal actions, but the AI should not be producing
    /// them in the first place — and it should still play a rounded game.
    @Test func playsLegallyAndIsNeitherARockNorAStation() async {
        var decisions = 0, illegal = 0
        var folds = 0, checks = 0, calls = 0, raises = 0

        for index in 0..<8 {
            let game = makeGame(opponents: 4, chips: 1000, blindSpeed: .normal,
                                difficulty: [.easy, .normal, .hard][index % 3])
            game.actionOverride = { seat, constraints in
                let player = game.players[seat]
                let action = AIBrain.decide(AIDecisionInput(
                    holeCards: player.holeCards, communityCards: game.communityCards,
                    street: game.street, potTotal: game.totalPot, toCall: constraints.toCall,
                    canRaise: constraints.canRaise, minRaiseTo: constraints.minRaiseTo,
                    maxRaiseTo: constraints.maxRaiseTo, myBetThisStreet: player.betThisStreet,
                    myChips: player.chips, currentBet: game.currentBet,
                    bigBlind: game.blindLevel.bigBlind,
                    opponentsInHand: game.players.filter(\.isInHand).count - 1,
                    positionScore: 0.5, opponentRange: 0.5,
                    personality: player.personality, difficulty: game.config.difficulty))

                decisions += 1
                switch action {
                case .fold: folds += 1
                case .check:
                    checks += 1
                    if !constraints.canCheck { illegal += 1 }
                case .call:
                    calls += 1
                    if constraints.toCall == 0 { illegal += 1 }
                case .raise(let to):
                    raises += 1
                    if !constraints.canRaise || to < constraints.minRaiseTo || to > constraints.maxRaiseTo {
                        illegal += 1
                    }
                }
                return action
            }

            var hands = 0
            while game.gameOverHumanWon == nil && hands < 200 { await game.playHand(); hands += 1 }
        }

        #expect(decisions > 200)
        #expect(illegal == 0, "\(illegal) of \(decisions) AI actions were out of range")
        let foldRate = Double(folds) / Double(decisions)
        #expect(foldRate < 0.6, "the AI folds \(Int(foldRate * 100))% of the time")
        #expect(raises > decisions / 10, "the AI barely raises (\(raises)/\(decisions))")
        #expect(checks > 0 && calls > 0)
    }
}

// MARK: - Odds HUD

/// The win-probability estimate is the most expensive thing the engine does per
/// hand, and the only thing that reads it is a HUD that is off by default. That
/// makes "is it running at all" a behaviour worth pinning: nothing visible
/// changes if the guard is removed, so nothing but a test would notice.
@Suite("Odds estimation")
@MainActor
struct OddsEstimationTests {

    /// A hand that checks down to the river, with the human on aces.
    ///
    /// Heads-up the button deals to the other seat first, so the stacked deck
    /// reads seat 1, seat 0, seat 1, seat 0 and then the board. Aces on
    /// J-9-7-4-2 of four different suits is a big favourite and nothing like a
    /// lock — a random opponent hand still gets there with two pair or J-high
    /// trips, and 8T makes a straight — which is what keeps the estimate
    /// strictly inside 0…1 rather than pinned to either end.
    private func checkedDownHand(oddsVisible: Bool) -> PokerGame {
        let game = makeGame(opponents: 1)
        game._setDealerForTesting(before: 0)       // dealer 0 posts the small blind
        game.oddsProvider = { oddsVisible }
        game.deckProvider = { Deck(stacked: cards("Kh As Qc Ad 7c 2d 9h 4s Js")) }
        Script([(0, .call), (1, .check),
                (1, .check), (0, .check),
                (1, .check), (0, .check),
                (1, .check), (0, .check)]).install(on: game)
        return game
    }

    /// The estimate arrives from a detached task, so it has to be waited for
    /// rather than read straight after the hand. Bounded, so a number that never
    /// comes fails the test instead of hanging it: a 700-iteration heads-up
    /// simulation is a few milliseconds of work, and this allows a second.
    private func settledEquity(of game: PokerGame) async -> Double? {
        for _ in 0..<100 {
            if let equity = game.humanEquity { return equity }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }

    /// Both sides are pinned in one test on purpose: "no number arrived" is only
    /// evidence of anything if the same wait is long enough to produce one when
    /// the odds are switched on.
    @Test func theOddsAreOnlyEstimatedWhileSomethingShowsThem() async {
        let visible = checkedDownHand(oddsVisible: true)
        await visible.playHand()
        let shown = await settledEquity(of: visible)
        #expect(shown != nil, "with the HUD on, an estimate has to arrive")
        // Aces up on that board is a heavy favourite, so this also says the
        // number is a real estimate rather than a placeholder. No upper bound:
        // an equity of exactly 1 is a legitimate Monte Carlo result, just not
        // one this board can produce.
        if let shown { #expect(shown > 0.6, "aces should be well ahead, not \(shown)") }

        let hidden = checkedDownHand(oddsVisible: false)
        await hidden.playHand()
        #expect(await settledEquity(of: hidden) == nil,
                "with the HUD off, the Monte Carlo must not run at all")
    }

    /// Switching the odds on has to ask for a number, because nothing else will
    /// until the next street — and on the river there is no next street.
    @Test func switchingTheOddsOnAsksForANumber() async {
        var oddsVisible = false
        let game = checkedDownHand(oddsVisible: false)
        game.oddsProvider = { oddsVisible }

        await game.playHand()
        #expect(game.humanEquity == nil)

        oddsVisible = true
        game.refreshHumanEquity()
        #expect(await settledEquity(of: game) != nil, "the HUD would have stayed blank")
    }
}
