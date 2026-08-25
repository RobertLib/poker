import Foundation
import Testing
@testable import poker

@Suite("Button and blinds")
@MainActor
struct DeadButtonTests {

    /// Everyone still seated: the big blind simply walks around the table.
    @Test func bigBlindAdvancesOneSeatPerHand() async {
        let game = makeGame(opponents: 5, chips: 5_000_000)
        var posted: [Int] = []
        game.onEvent = { event in
            guard case .blindsPosted = event else { return }
            posted.append(game.players.firstIndex {
                if case .bigBlind = $0.lastAction { return true } else { return false }
            } ?? -1)
        }
        game.actionOverride = { _, constraints in constraints.canCheck ? .check : .fold }

        for _ in 0..<12 { await game.playHand() }

        let steps = zip(posted, posted.dropFirst()).map { ($1 - $0 + 6) % 6 }
        #expect(steps.allSatisfy { $0 == 1 }, "big blind path was \(posted)")
    }

    /// With players knocked out, the blinds must still move one live seat at a
    /// time — that is what stops anyone being skipped or charged twice.
    @Test func nobodyIsSkippedOverTheBigBlind() async {
        var sawDeadSmallBlind = false
        var sawDeadButton = false

        for seed in 0..<40 {
            let game = makeGame(opponents: 4, chips: 300)
            var fuzz = FuzzActor(seed: UInt64(seed) &* 2_654_435_761 &+ 7)
            game.actionOverride = { _, constraints in
                switch fuzz.roll(10) {
                case ..<3: return constraints.canCheck ? .check : .fold
                case ..<6: return .call
                default: return constraints.canRaise ? .raise(to: constraints.maxRaiseTo) : .call
                }
            }

            var log: [(bigBlind: Int, smallBlind: Int?, live: [Int])] = []
            game.onEvent = { event in
                guard case .blindsPosted = event else { return }
                let big = game.players.firstIndex {
                    if case .bigBlind = $0.lastAction { return true } else { return false }
                }
                let small = game.players.firstIndex {
                    if case .smallBlind = $0.lastAction { return true } else { return false }
                }
                let live = game.players.indices.filter { !game.players[$0].isEliminated }
                if let big { log.append((big, small, live)) }
                if small == nil && live.count > 2 { sawDeadSmallBlind = true }
                if game.players[game.dealerIndex].isEliminated { sawDeadButton = true }
            }

            var hands = 0
            while game.gameOverHumanWon == nil && hands < 150 { await game.playHand(); hands += 1 }

            for (index, entry) in log.enumerated().dropFirst() {
                let previous = log[index - 1].bigBlind
                let live = entry.live
                guard let first = live.first else { continue }
                let expected = live.first { $0 > previous } ?? first
                #expect(entry.bigBlind == expected,
                        "seed \(seed) hand \(index): big blind went \(previous) → \(entry.bigBlind), expected \(expected) of \(live)")
                #expect(live.contains(entry.bigBlind), "the big blind is always a live player")
                // The small blind follows the *players*, not the seats: it goes
                // to whoever held the big blind last hand, and is dead only when
                // that player has just been knocked out. `entry.live` is the
                // table as it stood when these blinds went in, so it is what
                // says whether the previous big blind is still here.
                if live.count > 2 {
                    if live.contains(previous) {
                        #expect(entry.smallBlind == previous,
                                "seed \(seed) hand \(index): the small blind belongs to last hand's big blind (\(previous)), not \(entry.smallBlind.map(String.init) ?? "nobody")")
                    } else {
                        #expect(entry.smallBlind == nil,
                                "seed \(seed) hand \(index): seat \(previous) is out, so the small blind is dead")
                    }
                }
            }
            #expect(game.players.reduce(0) { $0 + $1.chips } == 1500)
        }

        #expect(sawDeadSmallBlind, "the dead small blind rule was never exercised")
        #expect(sawDeadButton, "the dead button rule was never exercised")
    }

    /// Regression: the small blind and the button used to be derived from
    /// absolute seat indices (`bb - 1`, `bb - 2`). That reads the same on a full
    /// table and is wrong on a broken one — the empty seats are never filled
    /// again, so the dead positions came back every single orbit instead of once
    /// per elimination. On a six-seat table down to seats 0, 2 and 5 that cost
    /// two hands in three their small blind outright and seats 0 and 2 never
    /// posted one at all: a permanent half a big blind an orbit handed to
    /// whoever the busted seats happened to leave standing.
    ///
    /// Nothing busts here — the stacks are enormous and the blinds are fixed —
    /// so there is no elimination to excuse a dead position. Every live seat has
    /// to pay each blind exactly once an orbit and take the button once, and
    /// nothing may be dead at all.
    @Test(arguments: [[0, 1, 2], [0, 2, 5], [0, 2, 4, 5], [0, 1, 2, 3, 4]])
    func deadBlindsDoNotOutliveTheEliminationThatCausedThem(live: [Int]) async {
        let config = GameConfig(opponents: Array(AIProfile.roster.prefix(5)),
                                startingChips: 5_000_000, difficulty: .easy, blindSpeed: .off)
        let saved = SavedGame(
            opponentIDs: config.opponents.map(\.id),
            startingChips: 5_000_000, difficulty: .easy, blindSpeed: .off,
            stacks: (0..<6).map { live.contains($0) ? 5_000_000 : 0 },
            eliminated: (0..<6).map { !live.contains($0) },
            dealerIndex: live[0], handNumber: 1)
        let game = PokerGame(config: config, restoring: saved)
        game.instantMode = true
        game.actionOverride = { _, constraints in constraints.canCheck ? .check : .fold }

        let orbits = 4
        var bigBlinds: [Int: Int] = [:], smallBlinds: [Int: Int] = [:], buttons: [Int: Int] = [:]
        var handsWithoutASmallBlind = 0, handsWithADeadButton = 0
        game.onEvent = { event in
            guard case .blindsPosted = event else { return }
            let big = game.players.firstIndex {
                if case .bigBlind = $0.lastAction { return true } else { return false }
            }
            let small = game.players.firstIndex {
                if case .smallBlind = $0.lastAction { return true } else { return false }
            }
            if let big { bigBlinds[big, default: 0] += 1 }
            if let small { smallBlinds[small, default: 0] += 1 } else { handsWithoutASmallBlind += 1 }
            buttons[game.dealerIndex, default: 0] += 1
            if game.players[game.dealerIndex].isEliminated { handsWithADeadButton += 1 }
        }

        for _ in 0..<(live.count * orbits) { await game.playHand() }

        #expect(handsWithoutASmallBlind == 0,
                "live \(live): \(handsWithoutASmallBlind) hands went in without a small blind")
        #expect(handsWithADeadButton == 0, "live \(live): the button landed on an empty seat")
        for seat in live {
            #expect(bigBlinds[seat] == orbits,
                    "live \(live): seat \(seat) posted \(bigBlinds[seat] ?? 0) big blinds, not \(orbits)")
            #expect(smallBlinds[seat] == orbits,
                    "live \(live): seat \(seat) posted \(smallBlinds[seat] ?? 0) small blinds, not \(orbits)")
            #expect(buttons[seat] == orbits,
                    "live \(live): seat \(seat) had the button \(buttons[seat] ?? 0) times, not \(orbits)")
        }
    }
}

@Suite("Saving and resuming")
@MainActor
struct SavedGameTests {

    @Test func snapshotSurvivesJSONAndRestoresTheTable() async throws {
        let game = makeGame(opponents: 3, chips: 800, blindSpeed: .normal)
        game.actionOverride = { _, constraints in constraints.canCheck ? .check : .call }
        for _ in 0..<12 { await game.playHand() }

        let snapshot = game.snapshot()
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SavedGame.self, from: data)

        #expect(decoded.stacks == snapshot.stacks)
        let config = try #require(decoded.config)
        let resumed = PokerGame(config: config, restoring: decoded)
        #expect(resumed.players.map(\.chips) == game.players.map(\.chips))
        #expect(resumed.handNumber == game.handNumber)
        #expect(resumed.blindLevel == game.blindLevel)
        #expect(resumed.dealerIndex == game.dealerIndex)
    }

    /// Regression: leaving the table mid-hand resumed from the previous hand
    /// boundary, so a hand going badly could be undone by quitting and hitting
    /// Continue. What you have already put in has to stay put.
    @Test func abandoningAHandForfeitsWhatTheHumanCommitted() async throws {
        let game = makeGame(opponents: 2)           // 3 players, blinds 5/10
        game._setDealerForTesting(before: 0)        // dealer 0, sb 1, bb 2, seat 0 first
        game.deckProvider = { Deck(stacked: cards("7c Kh As 2d Kd Ad 3h 5d 9c Jd 6s")) }

        var abandoned: SavedGame?
        game.actionOverride = { seat, _ in
            if seat == 0 { return .raise(to: 600) }
            // Seat 0 has 600 in the middle and the hand is still running: this
            // is the state `GameSession.stop()` writes when you walk away.
            if abandoned == nil { abandoned = game.forfeitSnapshot() }
            return .fold
        }
        await game.playHand()

        let saved = try #require(abandoned)
        #expect(saved.humanChips == 400, "the 600 in the middle does not come back")
        #expect(saved.humanChips < 1000, "quitting mid-hand must never beat folding")
        #expect(saved.handNumber == 1, "the abandoned hand is spent, not replayed")

        let config = try #require(saved.config)
        let resumed = PokerGame(config: config, restoring: saved)
        #expect(resumed.players[0].chips == 400)
        #expect(resumed.dealerIndex == saved.dealerIndex)
    }

    /// The mirror image of the rule above, and the reason the forfeit is not
    /// simply "freeze every stack": if the table kept its losses too, you could
    /// wait for an opponent to shove, walk away, and strip them of the lot.
    @Test func abandoningAHandLeavesTheOpponentsWhole() async throws {
        let game = makeGame(opponents: 2)
        game._setDealerForTesting(before: 1)        // dealer 1, sb 2, bb 0 — the human posts
        game.deckProvider = { Deck(stacked: cards("7c Kh As 2d Kd Ad 3h 5d 9c Jd 6s")) }

        var abandoned: SavedGame?
        game.actionOverride = { seat, constraints in
            // Seat 1 acts first and ships its whole stack; the human, in the big
            // blind, has only the 10 it was forced to post. Snapshot once that
            // 1000 is in the middle — walking away must not take it with us.
            if seat == 1 { return .raise(to: constraints.maxRaiseTo) }
            if abandoned == nil, game.players[1].totalInvested == 1000 {
                abandoned = game.forfeitSnapshot()
            }
            return .fold
        }
        await game.playHand()

        let saved = try #require(abandoned)
        #expect(saved.stacks[1] == 1000, "a shoved-in opponent gets its stack back")
        #expect(saved.stacks[2] == 1000, "and so does everyone else at the table")
        #expect(!saved.eliminated[1], "nobody is knocked out by someone else leaving")
        #expect(saved.humanChips < 1000, "only the human pays for walking away")
    }

    /// Regression: `GameSession.stop()` is only reached by leaving the table on
    /// purpose — SwiftUI does not call `onDisappear` for a move to the
    /// background — so nothing was written when the app left the foreground. A
    /// process the system then killed while suspended resumed from the
    /// *previous hand boundary*, which is the whole exploit: shove, force-quit,
    /// hit Continue, and the hand that was going badly never happened.
    @Test func backgroundingMidHandCannotRewindToTheLastHandBoundary() async throws {
        let config = GameConfig(opponents: Array(AIProfile.roster.prefix(2)),
                                startingChips: 1000, difficulty: .easy, blindSpeed: .off)
        let session = GameSession(config: config)
        let game = session.game
        game.instantMode = true

        let previous = SavedGameStore.shared.saved
        defer {
            if let previous { SavedGameStore.shared.store(previous) } else { SavedGameStore.shared.clear() }
        }
        SavedGameStore.shared.clear()

        // Hand one plays out normally, so a hand-boundary snapshot exists to be
        // tempted back to. `GameSession` writes it on `.handFinished`.
        game._setDealerForTesting(before: 0)
        game.deckProvider = { Deck(stacked: cards("7c Kh As 2d Kd Ad 3h 5d 9c Jd 6s")) }
        game.actionOverride = { _, constraints in constraints.canCheck ? .check : .call }
        await game.playHand()
        let boundary = try #require(SavedGameStore.shared.saved, "no hand-boundary snapshot was written")

        // Hand two: the human ships a big raise and the app goes to the
        // background with those chips in the middle. Read the store inside the
        // hand — `.handFinished` overwrites it as soon as `playHand` returns.
        game.deckProvider = { Deck(stacked: cards("Kh As Qh Kd Ad Qd 3h 5d 9c Jd 6s")) }
        // The button has moved on, so the human is the big blind and acts last:
        // the table limps in, the human raises, and only then has anything worth
        // rewinding gone in. Keyed off what is actually committed rather than
        // off turn order, which the button decides.
        var afterBackgrounding: SavedGame?
        game.actionOverride = { seat, _ in
            if seat == 0 { return .raise(to: 700) }
            guard game.players[0].totalInvested >= 700 else { return .call }
            if afterBackgrounding == nil {
                session.persistForResume()          // what `scenePhase != .active` does
                afterBackgrounding = SavedGameStore.shared.saved
            }
            return .fold
        }
        await game.playHand()

        let saved = try #require(afterBackgrounding, "backgrounding wrote nothing to resume from")
        #expect(saved.humanChips <= boundary.humanChips - 700,
                "resuming a killed app must not rewind the 700 already committed: \(saved.humanChips) vs \(boundary.humanChips) at the boundary")
        #expect(saved.handNumber == 2, "the abandoned hand is spent, not replayed")
        #expect(saved.stacks[1] == boundary.stacks[1],
                "only the human pays for the app going away")
    }

    /// A seat can be down to nothing mid-hand while `applyEliminations` has not
    /// run yet. The snapshot must still say it is out, or resuming deals it back
    /// in with an empty stack. `GameSession` reads the same flags to decide there
    /// is nothing worth coming back to.
    @Test func aForfeitSnapshotMarksTheHumanOutWhenItBustsThem() async throws {
        let game = makeGame(opponents: 2)
        game._setDealerForTesting(before: 0)
        game.deckProvider = { Deck(stacked: cards("7c Kh As 2d Kd Ad 3h 5d 9c Jd 6s")) }

        var abandoned: SavedGame?
        game.actionOverride = { seat, constraints in
            if seat == 0 { return .raise(to: constraints.maxRaiseTo) }   // shove it all
            if abandoned == nil { abandoned = game.forfeitSnapshot() }
            return .fold
        }
        await game.playHand()

        let saved = try #require(abandoned)
        #expect(saved.stacks[0] == 0)
        #expect(saved.eliminated[0], "a seat with nothing left is out, flags or not")
        #expect(saved.humanChips == 0, "so the menu has nothing to offer resuming")

        let config = try #require(saved.config)
        let resumed = PokerGame(config: config, restoring: saved)
        resumed.instantMode = true
        resumed.actionOverride = { _, constraints in constraints.canCheck ? .check : .call }
        await resumed.playHand()
        #expect(resumed.players[0].holeCards.isEmpty, "a busted seat is not dealt back in")
    }

    @Test func corruptSnapshotsAreRejected() {
        var snapshot = SavedGame(opponentIDs: ["viktor", "rosa"], startingChips: 1000,
                                 difficulty: .normal, blindSpeed: .normal,
                                 stacks: [1000, 1000, 1000], eliminated: [false, false, false],
                                 dealerIndex: 0, handNumber: 1, bigBlindSeat: 2)
        #expect(snapshot.config != nil)

        snapshot.stacks = [1, 2]
        #expect(snapshot.config == nil, "a stack count that doesn't match the roster is unusable")

        var unknownRoster = snapshot
        unknownRoster.stacks = [1000, 1000, 1000]
        unknownRoster.opponentIDs = ["ghost"]
        #expect(unknownRoster.config == nil, "an unknown opponent id is unusable")
    }

    /// Regression: the snapshot is taken while `.handFinished` is delivered, so
    /// eliminations have to be recorded before that event goes out. Otherwise a
    /// resumed game deals busted players back in with an empty stack.
    @Test func snapshotKnowsWhoIsAlreadyOut() async {
        var bustOutsSeen = 0

        for seed in 0..<25 {
            let game = makeGame(opponents: 2 + seed % 3, chips: 120, blindSpeed: .turbo)
            var snapshot: SavedGame?
            var busted = false
            game.onEvent = { event in
                switch event {
                case .handFinished: snapshot = game.snapshot()   // exactly what GameSession does
                case .playerEliminated: busted = true
                default: break
                }
            }
            game.actionOverride = { _, constraints in
                constraints.canRaise ? .raise(to: constraints.maxRaiseTo)
                                     : (constraints.canCheck ? .check : .call)
            }

            var hands = 0
            while !busted && game.gameOverHumanWon == nil && hands < 80 {
                await game.playHand()
                hands += 1
            }
            guard busted, let saved = snapshot else { continue }
            bustOutsSeen += 1

            for (seat, (stack, eliminated)) in zip(saved.stacks, saved.eliminated).enumerated() {
                #expect(!(stack == 0 && !eliminated),
                        "seat \(seat) has no chips but the save says it is still playing")
            }

            guard game.gameOverHumanWon == nil, let config = saved.config else { continue }
            let resumed = PokerGame(config: config, restoring: saved)
            resumed.instantMode = true
            resumed.actionOverride = { _, constraints in constraints.canCheck ? .check : .call }
            await resumed.playHand()

            for player in resumed.players {
                #expect(!(player.chips == 0 && !player.holeCards.isEmpty && !player.hasFolded),
                        "a busted player was dealt back into the resumed hand")
            }
            #expect(resumed.players.reduce(0) { $0 + $1.chips } == saved.stacks.reduce(0, +))
        }

        #expect(bustOutsSeen > 0, "no bust-out was exercised")
    }
}
