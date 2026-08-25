import Testing
@testable import poker

@Suite("Betting rules")
@MainActor
struct EngineRulesTests {

    @Test func bestHandTakesThePot() async {
        let game = makeGame(opponents: 2)          // 3 players, blinds 5/10
        game._setDealerForTesting(before: 0)       // dealer 0, sb 1, bb 2, first to act 0
        // Deal order is 1, 2, 0 twice: seat 0 gets AA, seat 1 KK, seat 2 rags.
        game.deckProvider = { Deck(stacked: cards("Kh 7c As Kd 2d Ad 2h 5d 9c Jd 3s")) }

        let script = Script([
            (0, .raise(to: 30)), (1, .call), (2, .fold),
            (1, .check), (0, .check), (1, .check), (0, .check), (1, .check), (0, .check),
        ])
        script.install(on: game)
        await game.playHand()

        #expect(game.players[0].chips == 1040, "aces win the 70 chip pot")
        #expect(game.players[1].chips == 970)
        #expect(game.players[2].chips == 990)
        #expect(game.handResult?.wentToShowdown == true)
        let winningHand = game.handResult?.potResults.first?.winningHandName
        #expect(winningHand?.contains(Rank.ace.name(.pluralPossessive)) == true, "named \(winningHand ?? "nil")")
        #expect(game.players.reduce(0) { $0 + $1.chips } == 3000)
    }

    @Test func uncalledBetIsReturned() async {
        let game = makeGame(opponents: 2)
        game._setDealerForTesting(before: 0)
        game.deckProvider = { Deck(stacked: cards("Kh 7c As Kd 2d Ad 3h 5d 9c Jd 6s")) }
        Script([(0, .raise(to: 250)), (1, .fold), (2, .fold)]).install(on: game)

        await game.playHand()

        #expect(game.players[0].chips == 1015, "only the blinds are won; the rest comes back")
        #expect(game.players[1].chips == 995)
        #expect(game.players[2].chips == 990)
        #expect(game.handResult?.wentToShowdown == false)
    }

    @Test func minimumRaiseTracksTheLastFullRaise() async {
        let game = makeGame(opponents: 3)          // dealer 0, sb 1, bb 2, utg 3
        game._setDealerForTesting(before: 0)
        game.deckProvider = { Deck(stacked: cards("Kh 7c 8d As Kd 7d 8h Ad 3h 5d 9c Jd 6s")) }

        let script = Script([
            (3, .raise(to: 30)),      // opens to 30 — a 20 chip raise
            (0, .raise(to: 50)),      // the minimum re-raise
            (1, .fold), (2, .fold), (3, .call),
            (3, .check), (0, .check), (3, .check), (0, .check), (3, .check), (0, .check),
        ])
        script.install(on: game)
        await game.playHand()

        let utg = script.constraints(forSeat: 3)
        #expect(utg[0].minRaiseTo == 20, "the first raise must at least double the big blind")
        #expect(utg[0].toCall == 10)
        #expect(script.constraints(forSeat: 0)[0].minRaiseTo == 50, "facing 30, the minimum is 50")
        #expect(utg[1].minRaiseTo == 70, "facing 50 after a 20 raise, the minimum is 70")
        #expect(utg[1].canRaise, "a full raise reopens the betting")
    }

    @Test func shortAllInDoesNotReopenTheBetting() async {
        let game = makeGame(opponents: 2)
        game._setDealerForTesting(before: 0)
        // First hand shrinks seat 2 to 45 chips.
        game.deckProvider = { Deck(stacked: cards("7c Kh As 2d Kd Ad 3h 5d 9c Jd 6s")) }
        Script([
            (0, .raise(to: 955)), (1, .fold), (2, .call),
            (2, .check), (0, .check), (2, .check), (0, .check), (2, .check), (0, .check),
        ]).install(on: game)
        await game.playHand()
        #expect(game.players[2].chips == 45)

        // Seat 1 opens to 30; seat 2 shoves 45 — a 15 chip raise, less than a full one.
        game.deckProvider = { Deck(stacked: cards("Kh As Qh Kd Ad Qd 3h 5d 9c Jd 6s")) }
        let script = Script([
            (1, .raise(to: 30)), (2, .raise(to: 45)), (0, .call), (1, .call),
            (0, .check), (1, .check), (0, .check), (1, .check), (0, .check), (1, .check),
        ])
        script.install(on: game)
        await game.playHand()

        let seatOne = script.constraints(forSeat: 1)
        #expect(seatOne.count >= 2)
        #expect(seatOne[1].canRaise == false, "an incomplete all-in must not reopen the action")
        #expect(seatOne[1].toCall == 15)
        #expect(script.constraints(forSeat: 0)[0].canRaise, "a player yet to act keeps full rights")
        #expect(game.players.reduce(0) { $0 + $1.chips } == 3000)
    }

    /// Raising over an all-in that could not even reach the minimum bet only has
    /// to make the minimum bet, not the incomplete bet plus a whole big blind on
    /// top. Regression: a 4 chip shove into a 10 chip game used to demand 14.
    @Test func raisingOverAnIncompleteAllInOnlyHasToReachTheMinimumBet() async {
        let game = makeGame(opponents: 2)          // 3 players, blinds 5/10
        game._setDealerForTesting(before: 0)       // dealer 0, sb 1, bb 2, seat 0 acts first

        // Hand one leaves seat 2 with exactly 14 chips: enough to post the small
        // blind and call, and 4 left over to open with on the flop.
        game.deckProvider = { Deck(stacked: cards("7c Kh As 2d Kd Ad 3h 5d 9c Jd 6s")) }
        Script([
            (0, .call), (1, .fold), (2, .raise(to: 986)), (0, .call),
            (2, .check), (0, .check), (2, .check), (0, .check), (2, .check), (0, .check),
        ]).install(on: game)
        await game.playHand()
        #expect(game.players[2].chips == 14, "seat 2 should be left with 14")

        // Hand two: seat 2 is the small blind, limps to 10 with 4 behind, then
        // opens the flop all-in for 4 — less than the 10 chip minimum bet.
        game.deckProvider = { Deck(stacked: cards("2c 7d 9h 3s 8c Jh Kd Qs 4h 5c 6d")) }
        let script = Script([
            (1, .call), (2, .call), (0, .check),
            (2, .raise(to: 4)), (0, .call), (1, .call),
            (0, .check), (1, .check),
            (0, .check), (1, .check),
        ])
        script.install(on: game)
        await game.playHand()

        let facingTheShove = script.constraints(forSeat: 0)
        #expect(facingTheShove.count >= 2)
        #expect(facingTheShove[1].toCall == 4)
        #expect(facingTheShove[1].minRaiseTo == 10,
                "the minimum is the 10 chip bet, not 4 + 10; got \(facingTheShove[1].minRaiseTo)")
        #expect(game.players.reduce(0) { $0 + $1.chips } == 3000)
    }

    @Test func headsUpOrderAndBlinds() async {
        let game = makeGame(opponents: 1)
        game._setDealerForTesting(before: 0)       // seat 0 is the button and small blind
        game.deckProvider = { Deck(stacked: cards("As Kh Ad Kd 3h 5d 9c Jd 6s")) }
        let script = Script([
            (0, .call), (1, .check),
            (1, .check), (0, .check), (1, .check), (0, .check), (1, .check), (0, .check),
        ])
        script.install(on: game)
        await game.playHand()

        #expect(script.history[0].seat == 0, "the button acts first before the flop")
        #expect(script.history[1].seat == 1)
        #expect(script.history[2].seat == 1, "the big blind acts first after the flop")
        #expect(script.history[0].constraints.toCall == 5, "the button completes the small blind")
        #expect(game.players[1].holeCards == cards("As Ad"), "dealing starts left of the button")
        #expect(game.players[0].holeCards == cards("Kh Kd"))
    }

    @Test func splitPotGivesTheOddChipLeftOfTheButton() async {
        let game = makeGame(opponents: 2)
        game._setDealerForTesting(before: 0)       // dealer 0, sb 1, bb 2
        // A royal flush on the board: seats 0 and 2 split.
        game.deckProvider = { Deck(stacked: cards("7c 3d 3c 8c 2s 2h Ah Kh Qh Jh Th")) }
        Script([
            (0, .raise(to: 20)), (1, .fold), (2, .call),
            (2, .check), (0, .check), (2, .check), (0, .check), (2, .check), (0, .check),
        ]).install(on: game)

        await game.playHand()

        #expect(game.players.reduce(0) { $0 + $1.chips } == 3000)
        #expect(game.players[1].chips == 995, "the folder still loses the small blind")
        #expect(game.players[2].chips == 1003, "45 splits as 23/22, odd chip left of the button")
        #expect(game.players[0].chips == 1002)
        let main = game.handResult?.potResults.first
        #expect(main?.winnerSeats.count == 2, "the pot is shared, not won outright")
        #expect(Set(main?.winnerSeats ?? []) == [0, 2])
    }

    @Test func sidePotGoesToTheDeeperStack() async throws {
        let game = makeGame(opponents: 2)
        game._setDealerForTesting(before: 0)
        // Hand one leaves seat 2 short.
        game.deckProvider = { Deck(stacked: cards("7c Kh As 2d Kd Ad 3h 5d 9c Jd 6s")) }
        Script([
            (0, .raise(to: 600)), (1, .fold), (2, .call),
            (2, .check), (0, .check), (2, .check), (0, .check), (2, .check), (0, .check),
        ]).install(on: game)
        await game.playHand()
        #expect(game.players[2].chips == 400)

        // Hand two: the short stack shoves with aces and wins only the main pot.
        game.deckProvider = { Deck(stacked: cards("As Kh Qh Ad Kd Qd 3h 5d 9c Jd 6s")) }
        Script([
            (1, .call), (2, .raise(to: 400)), (0, .call), (1, .call),
            (0, .raise(to: 300)), (1, .call),
            (0, .check), (1, .check), (0, .check), (1, .check),
        ]).install(on: game)
        await game.playHand()

        #expect(game.players[2].chips == 1200, "aces take the 1200 main pot")
        #expect(game.players[0].chips == 1505, "kings take the 600 side pot")
        #expect(game.players[1].chips == 295)
        #expect(game.handResult?.potResults.count == 2)
        #expect(game.players.reduce(0) { $0 + $1.chips } == 3000)

        // Regression: `winningCards` carried only the main pot winner's best
        // five, so the side pot winner's own cards were dimmed as if they had
        // lost. Every pot winner's hand counts.
        let winning = try #require(game.handResult?.winningCards)
        #expect(winning.isSuperset(of: cards("As Ad")), "the main pot winner's aces")
        #expect(winning.isSuperset(of: cards("Kh Kd")), "the side pot winner's kings")
        #expect(!winning.contains(card("Qh")), "a beaten hand is not highlighted")

        // The banner is the only thing that says a side pot went somewhere else:
        // its winner is highlighted like the main pot's, so without a word about
        // it the table shows two winners and explains one.
        let headline = try #require(game.handResult?.headline)
        #expect(headline.contains(600.chipText),
                "the side pot has to be announced, not just highlighted: \(headline)")
        #expect(headline.contains(game.players[0].name),
                "and it has to name who took it: \(headline)")
    }

    /// Regression: a street whose entire bet was refunded used to leave the old
    /// price behind in `currentBet`.
    @Test func priceResetsEvenWhenTheWholeBetIsRefunded() async {
        var stale = 0, played = 0
        for seed in 0..<40 {
            let game = makeGame(opponents: 1 + seed % 4, chips: 400, blindSpeed: .normal)
            var fuzz = FuzzActor(seed: UInt64(seed) &* 99_991 &+ 3)
            game.actionOverride = { _, constraints in fuzz.action(for: constraints) }

            var hands = 0
            while game.gameOverHumanWon == nil && hands < 80 {
                await game.playHand()
                hands += 1
                played += 1
                if game.currentBet != 0 { stale += 1 }
            }
        }
        #expect(played > 0)
        #expect(stale == 0, "currentBet must be clear after every one of \(played) hands")
    }
}
