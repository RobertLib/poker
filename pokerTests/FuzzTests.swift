import Testing
@testable import poker

@Suite("Engine invariants under fuzzing")
@MainActor
struct EngineFuzzTests {

    /// Plays whole games with adversarial input — including illegal requests —
    /// and asserts the properties that must hold no matter what the caller does.
    @Test func gamesStayConsistentUnderRandomPlay() async throws {
        var handsPlayed = 0
        var showdowns = 0, sidePots = 0, splitPots = 0

        for index in 0..<60 {
            let opponents = 1 + index % 5
            let startingChips = [200, 500, 1000, 60][index % 4]
            let blindSpeed: BlindSpeed = [.off, .turbo, .normal, .slow][index % 4]
            let game = makeGame(opponents: opponents, chips: startingChips, blindSpeed: blindSpeed)
            let bank = startingChips * (opponents + 1)
            var fuzz = FuzzActor(seed: UInt64(index) &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407)

            game.actionOverride = { seat, constraints in
                let player = game.players[seat]

                // Whatever is offered has to be playable.
                #expect(constraints.toCall >= 0)
                #expect(constraints.toCall <= player.chips, "cannot be asked for more chips than you have")
                #expect(constraints.minRaiseTo <= constraints.maxRaiseTo)
                #expect(constraints.maxRaiseTo == player.betThisStreet + player.chips)
                #expect(!(constraints.canCheck && constraints.toCall != 0))
                #expect(!(constraints.canRaise && constraints.maxRaiseTo <= game.currentBet))
                #expect(constraints.isOpeningBet == (game.currentBet == 0))
                if game.street != .preflop {
                    #expect(game.currentBet == game.players.map(\.betThisStreet).max() ?? 0)
                }

                // And only someone who can actually act may be asked.
                #expect(player.canAct)
                #expect(!player.hasFolded)
                #expect(!player.isEliminated)

                return fuzz.action(for: constraints)
            }

            var hands = 0
            while game.gameOverHumanWon == nil && hands < 300 {
                await game.playHand()
                hands += 1
                handsPlayed += 1

                #expect(game.players.reduce(0) { $0 + $1.chips } == bank, "chips must be conserved")
                #expect(!game.players.contains { $0.chips < 0 })
                #expect(game.pot == 0, "the pot must be handed out")
                #expect(!game.players.contains { $0.betThisStreet != 0 })
                #expect(game.currentBet == 0)
                #expect(!game.isHandInProgress)

                let result = try #require(game.handResult)
                #expect(!result.headline.isEmpty)
                #expect(result.winnings.values.reduce(0, +) == result.potResults.reduce(0) { $0 + $1.amount },
                        "every chip in a pot must reach a winner")
                for pot in result.potResults {
                    #expect(!pot.winnerSeats.isEmpty)
                    #expect(Set(pot.winnerSeats).isSubset(of: Set(pot.eligibleSeats)),
                            "only eligible players can win a pot")
                }

                let inPlay = game.players.filter { !$0.holeCards.isEmpty }.flatMap(\.holeCards)
                    + game.communityCards
                #expect(Set(inPlay).count == inPlay.count, "no card may be dealt twice")
                #expect(game.communityCards.count <= 5)
                if result.wentToShowdown { #expect(game.communityCards.count == 5) }

                if result.wentToShowdown { showdowns += 1 }
                if result.potResults.count > 1 { sidePots += 1 }
                if result.potResults.contains(where: { $0.winnerSeats.count > 1 }) { splitPots += 1 }
            }
            #expect(game.gameOverHumanWon != nil, "game \(index) never produced a winner")
        }

        // Guard against the suite silently stopping to cover the hard paths.
        #expect(handsPlayed > 300, "only \(handsPlayed) hands were played")
        #expect(showdowns > 50, "showdowns barely exercised (\(showdowns))")
        #expect(sidePots > 5, "side pots barely exercised (\(sidePots))")
        #expect(splitPots > 0, "split pots never exercised")
    }

    /// Blinds bigger than the stacks: every hand is a forced all-in.
    @Test func microStackGamesStillTerminate() async {
        for seed in 0..<15 {
            let game = makeGame(opponents: 2 + seed % 3, chips: 7)
            let bank = 7 * game.players.count
            game.actionOverride = { _, constraints in
                constraints.canRaise ? .raise(to: constraints.maxRaiseTo)
                                     : (constraints.canCheck ? .check : .call)
            }

            var hands = 0
            while game.gameOverHumanWon == nil && hands < 150 {
                await game.playHand()
                hands += 1
                #expect(game.players.reduce(0) { $0 + $1.chips } == bank)
                #expect(!game.players.contains { $0.chips < 0 })
            }
            #expect(game.gameOverHumanWon != nil, "seed \(seed) never finished")
        }
    }

    @Test func blindsFollowTheSchedule() async {
        let turbo = makeGame(opponents: 1, chips: 5_000_000, blindSpeed: .turbo)   // 6 hands a level
        turbo.actionOverride = { _, constraints in constraints.canCheck ? .check : .fold }
        var levels: [Int] = []
        for _ in 0..<20 { await turbo.playHand(); levels.append(turbo.blindLevel.bigBlind) }

        #expect(levels[0] == 10 && levels[5] == 10, "the first six hands share a level")
        #expect(levels[6] == 20)
        #expect(levels[12] == 30)
        #expect(levels == levels.sorted(), "blinds never come back down")

        let fixed = makeGame(opponents: 1, chips: 5_000_000, blindSpeed: .off)
        fixed.actionOverride = { _, constraints in constraints.canCheck ? .check : .fold }
        for _ in 0..<30 { await fixed.playHand() }
        #expect(fixed.blindLevel.bigBlind == 10, "fixed blinds stay put")
    }
}
