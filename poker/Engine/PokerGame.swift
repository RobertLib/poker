import Foundation
import Observation

// MARK: - Game Events (drive sounds, haptics & transient animations)

nonisolated enum GameEvent: Sendable {
    case handStarted
    case blindsPosted
    case blindLevelUp(BlindLevel)
    case cardDealt(seat: Int?)          // nil = community card
    case chipsCommitted(seat: Int, isAllIn: Bool)
    case playerChecked(seat: Int)
    case playerFolded(seat: Int)
    case betsCollected(fromSeats: [Int])
    case streetRevealed(Street)
    case humanTurn
    case showdownReveal
    case potAwarded(toSeats: [Int], amount: Int)
    case handFinished(HandResult)
    case playerEliminated(seat: Int)
    case gameOver(humanWon: Bool)
}

// MARK: - Poker Game Engine

/// Full No-Limit Texas Hold'em engine: blinds, betting rounds with correct
/// min-raise / incomplete-all-in rules, side pots, showdown and eliminations.
/// Drives itself through an async loop; the UI observes published state and
/// receives `GameEvent`s for sounds and transient effects.
@MainActor
@Observable
final class PokerGame {

    // MARK: Observable state

    private(set) var players: [Player] = []
    private(set) var communityCards: [Card] = []
    /// Chips collected from previous streets (bets in front of players are separate).
    private(set) var pot = 0
    private(set) var street: Street = .preflop
    private(set) var dealerIndex = 0
    private(set) var activeSeat: Int?
    private(set) var handNumber = 0
    private(set) var blindLevel = BlindLevel.schedule[0]
    private(set) var currentBet = 0
    private(set) var isHandInProgress = false
    private(set) var handResult: HandResult?
    /// nil while the game runs; true/false = human won/lost.
    private(set) var gameOverHumanWon: Bool?
    private(set) var humanConstraints: ActionConstraints?
    private(set) var humanEquity: Double?

    let config: GameConfig

    // MARK: Hooks

    var onEvent: ((GameEvent) -> Void)?
    /// Scales all pacing pauses (from the speed setting). 1 = normal.
    var speedProvider: () -> Double = { 1 }
    /// Whether the human's win probability is worth estimating.
    ///
    /// The odds HUD is the only thing that reads `humanEquity`, and its setting
    /// is off by default — so without this the Monte Carlo runs on every street
    /// *and* on every fold for a number nobody is looking at. Defaults to true
    /// so an unwired engine behaves as it always did.
    var oddsProvider: () -> Bool = { true }
    /// Test hook: replaces both human and AI decision-making when set.
    var actionOverride: ((Int, ActionConstraints) async -> PlayerAction)?
    /// Answers for the AI seats only, leaving the human's turn exactly as it is
    /// in a real game — the action bar still appears and still waits for a tap.
    /// Returning nil hands that decision back to `AIBrain`. Used to script the
    /// opposition for the App Store screenshots (see AppStore/screenshots.md).
    var aiActionOverride: ((Int, ActionConstraints) -> PlayerAction?)?
    /// Test hook: skips all pacing pauses.
    var instantMode = false
    /// Test hook: deterministic decks.
    var deckProvider: () -> Deck = { Deck() }

    // MARK: Private state

    private var deck = Deck()
    private var lastRaiseSize = 0
    /// Seat that posted the big blind this hand. Driving the cycle from the big
    /// blind (rather than the button) is what makes the dead-button rules work.
    private var bigBlindSeat: Int?
    /// Seat the small blind fell to this hand, whether or not anybody was left
    /// to post it. The button follows it next hand, so a *dead* seat has to be
    /// remembered rather than skipped — see `moveButton`.
    private var smallBlindSeat: Int?
    private var humanContinuation: CheckedContinuation<PlayerAction, Never>?
    private var runTask: Task<Void, Never>?
    private var equityTask: Task<Void, Never>?
    private var runoutRevealed = false

    var humanSeat: Int { players.firstIndex(where: \.isHuman) ?? 0 }
    var totalPot: Int { pot + players.reduce(0) { $0 + $1.betThisStreet } }
    var isAwaitingHuman: Bool { humanConstraints != nil }

    // MARK: Init

    init(config: GameConfig, restoring saved: SavedGame? = nil) {
        self.config = config
        var seats: [Player] = [
            Player(id: 0, name: localized("player.you"), emoji: "😎", isHuman: true,
                   chips: config.humanStartingChips ?? config.startingChips, personality: .human)
        ]
        for (index, profile) in config.opponents.enumerated() {
            seats.append(Player(id: index + 1, name: profile.name, emoji: profile.emoji,
                                isHuman: false, chips: config.startingChips,
                                personality: profile.personality))
        }
        players = seats
        dealerIndex = seats.indices.randomElement() ?? 0

        // Resuming a saved game: stacks, button and hand number are enough to
        // deal the next hand, and the blind level follows from the hand number.
        if let saved, saved.stacks.count == seats.count, saved.eliminated.count == seats.count {
            for i in players.indices {
                players[i].chips = saved.stacks[i]
                players[i].isEliminated = saved.eliminated[i]
            }
            dealerIndex = min(max(saved.dealerIndex, 0), players.count - 1)
            if let seat = saved.bigBlindSeat, players.indices.contains(seat) {
                bigBlindSeat = seat
            }
            if let seat = saved.smallBlindSeat, players.indices.contains(seat) {
                smallBlindSeat = seat
            }
            handNumber = saved.handNumber
            updateBlindLevel()
        }
    }

    /// Snapshot for resuming later, taken at a hand boundary.
    func snapshot() -> SavedGame {
        makeSnapshot(stacks: players.map(\.chips))
    }

    /// Snapshot for walking away from a hand that is still running.
    ///
    /// The human's committed chips are forfeit, so quitting can never undo a
    /// hand that was going badly. Everyone else is made whole, because the
    /// mirror image matters just as much: if the table kept its losses too, you
    /// could wait for an opponent to shove, quit, and strip them of the lot.
    /// Either way the abandoned hand itself is spent — `handNumber` and the
    /// blind cycle have already moved on, so resuming deals the next one.
    func forfeitSnapshot() -> SavedGame {
        var stacks = players.map(\.chips)
        for i in players.indices where !players[i].isHuman {
            stacks[i] += players[i].totalInvested
        }
        return makeSnapshot(stacks: stacks)
    }

    private func makeSnapshot(stacks: [Int]) -> SavedGame {
        SavedGame(opponentIDs: config.opponents.map(\.id),
                  startingChips: config.startingChips,
                  difficulty: config.difficulty,
                  blindSpeed: config.blindSpeed,
                  stacks: stacks,
                  // A seat with nothing left is out whether or not
                  // `applyEliminations` has run, which is what keeps a snapshot
                  // taken mid-hand from dealing a busted player back in.
                  eliminated: zip(players, stacks).map { $0.isEliminated || $1 == 0 },
                  dealerIndex: dealerIndex,
                  handNumber: handNumber,
                  bigBlindSeat: bigBlindSeat,
                  smallBlindSeat: smallBlindSeat)
    }

    // MARK: Lifecycle

    func start() {
        guard runTask == nil else { return }
        runTask = Task { await run() }
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
        equityTask?.cancel()
        // Clear the constraints along with the continuation. They are what
        // `isAwaitingHuman` reads, so leaving them behind would say a stopped
        // game is still waiting for a tap it can no longer accept.
        humanConstraints = nil
        if let continuation = humanContinuation {
            humanContinuation = nil
            continuation.resume(returning: .fold)
        }
    }

    func submitHumanAction(_ action: PlayerAction) {
        guard let continuation = humanContinuation else { return }
        humanContinuation = nil
        humanConstraints = nil
        continuation.resume(returning: action)
    }

    // MARK: Main loop

    private func run() async {
        while !Task.isCancelled && gameOverHumanWon == nil {
            await playHand()
            guard !Task.isCancelled, gameOverHumanWon == nil else { break }
            await pause(3.4)   // let the result banner breathe
        }
    }

    // MARK: One hand

    /// Test support: forces the dealer button so the NEXT hand's dealer is `seat`.
    func _setDealerForTesting(before seat: Int) {
        var previous = seat - 1
        if previous < 0 { previous = players.count - 1 }
        dealerIndex = previous
        bigBlindSeat = nil
    }

    /// Plays exactly one hand. Called by the run loop; exposed for tests.
    func playHand() async {
        handNumber += 1
        updateBlindLevel()
        handResult = nil
        humanEquity = nil
        communityCards = []
        pot = 0
        street = .preflop
        currentBet = 0
        lastRaiseSize = 0
        runoutRevealed = false
        deck = deckProvider()
        for i in players.indices { players[i].resetForNewHand() }
        moveButton()
        isHandInProgress = true
        onEvent?(.handStarted)
        await pause(0.5)

        // Blinds
        let (sbSeat, bbSeat) = blindSeats()
        if let sbSeat {
            let sbPaid = players[sbSeat].commit(blindLevel.smallBlind)
            players[sbSeat].lastAction = .smallBlind(sbPaid)
        }
        let bbPaid = players[bbSeat].commit(blindLevel.bigBlind)
        players[bbSeat].lastAction = .bigBlind(bbPaid)
        currentBet = blindLevel.bigBlind
        lastRaiseSize = blindLevel.bigBlind
        onEvent?(.blindsPosted)
        await pause(0.45)

        // Hole cards: two passes, starting left of the dealer
        for _ in 0..<2 {
            for seat in seatsInOrder(from: nextActiveSeat(after: dealerIndex))
            where !players[seat].isEliminated {
                players[seat].holeCards.append(deck.deal())
                onEvent?(.cardDealt(seat: seat))
                await pause(0.14)
            }
        }
        await pause(0.3)
        updateHumanEquity()

        // Pre-flop betting
        let preflopFirst = nextInHandSeat(after: bbSeat)
        var handContinues = await bettingRound(firstToAct: preflopFirst)
        guard !Task.isCancelled else { return }
        if !handContinues {
            await concludeUncontested()
            return
        }

        // Flop, turn, river
        for nextStreet in [Street.flop, .turn, .river] {
            street = nextStreet
            await revealRunoutIfNeeded()
            await dealCommunityCards(upTo: nextStreet.communityCardCount)
            updateHumanEquity()
            guard !Task.isCancelled else { return }

            if playersWhoCanAct.count >= 2 {
                handContinues = await bettingRound(firstToAct: nextInHandSeat(after: dealerIndex))
                guard !Task.isCancelled else { return }
                if !handContinues {
                    await concludeUncontested()
                    return
                }
            } else {
                await pause(runoutRevealed ? 1.0 : 0.4)
            }
        }

        await showdown()
    }

    // MARK: Betting round

    /// Runs one street of betting. Returns false when the hand ended (all but one folded).
    private func bettingRound(firstToAct: Int) async -> Bool {
        var queue = seatsInOrder(from: firstToAct).filter { players[$0].canAct }
        var actedSinceFullRaise = Set<Int>()

        while let seat = queue.first {
            queue.removeFirst()
            guard !Task.isCancelled else { return false }
            guard players[seat].canAct else { continue }
            if playersInHand.count <= 1 { break }

            let toCall = currentBet - players[seat].betThisStreet
            let othersCanRespond = playersInHand.contains { $0.id != seat && $0.canAct }
            // Nothing to call and nobody left to respond: the street plays itself out.
            if toCall <= 0 && !othersCanRespond { continue }

            let constraints = makeConstraints(
                seat: seat,
                raiseReopened: !actedSinceFullRaise.contains(seat),
                othersCanRespond: othersCanRespond)

            activeSeat = seat
            let action = await obtainAction(seat: seat, constraints: constraints)
            guard !Task.isCancelled else { return false }

            apply(action, seat: seat, constraints: constraints,
                  queue: &queue, actedSinceFullRaise: &actedSinceFullRaise)
            activeSeat = nil

            if playersInHand.count <= 1 { break }
            await pause(0.45)
        }

        activeSeat = nil
        await collectBets()
        return playersInHand.count > 1
    }

    private func makeConstraints(seat: Int, raiseReopened: Bool, othersCanRespond: Bool) -> ActionConstraints {
        let player = players[seat]
        let toCall = min(max(currentBet - player.betThisStreet, 0), player.chips)
        let maxTo = player.betThisStreet + player.chips
        let minBet = max(blindLevel.bigBlind, 1)
        // Raising over an *incomplete* opening all-in only has to reach the
        // minimum bet, not the bet plus a whole big blind on top: a 3 chip
        // shove into a 10 chip game is raised to 10, not to 13.
        let unrestrictedMinTo = currentBet == 0
            ? minBet
            : max(currentBet + lastRaiseSize, minBet)
        let minTo = min(unrestrictedMinTo, maxTo)
        let canRaise = raiseReopened && maxTo > currentBet && othersCanRespond
        return ActionConstraints(
            toCall: toCall,
            canCheck: currentBet <= player.betThisStreet,
            canRaise: canRaise,
            minRaiseTo: minTo,
            maxRaiseTo: maxTo,
            isOpeningBet: currentBet == 0)
    }

    private func apply(_ action: PlayerAction, seat: Int, constraints: ActionConstraints,
                       queue: inout [Int], actedSinceFullRaise: inout Set<Int>) {
        var resolved = action

        // Sanitize illegal requests (belt & braces for both UI and AI).
        switch resolved {
        case .check where !constraints.canCheck:
            resolved = .fold
        case .raise where !constraints.canRaise:
            resolved = constraints.toCall > 0 ? .call : .check
        case .call where constraints.toCall <= 0:
            resolved = .check
        default:
            break
        }

        switch resolved {
        case .fold:
            players[seat].hasFolded = true
            players[seat].lastAction = .fold
            onEvent?(.playerFolded(seat: seat))
            // One fewer opponent to beat: the odds on screen have to follow the
            // fold rather than wait for the next street.
            updateHumanEquity()

        case .check:
            players[seat].lastAction = .check
            onEvent?(.playerChecked(seat: seat))

        case .call:
            players[seat].commit(constraints.toCall)
            let allIn = players[seat].isAllIn
            players[seat].lastAction = allIn
                ? .allIn(players[seat].betThisStreet)
                : .call(constraints.toCall)
            onEvent?(.chipsCommitted(seat: seat, isAllIn: allIn))
            actedSinceFullRaise.insert(seat)

        case .raise(let target):
            // `minRaiseTo` is already capped at `maxRaiseTo`, so this both rejects
            // sub-minimum raises and still allows a short all-in.
            let clamped = max(min(target, constraints.maxRaiseTo), constraints.minRaiseTo)
            let previousBet = currentBet
            players[seat].commit(clamped - players[seat].betThisStreet)
            currentBet = max(currentBet, players[seat].betThisStreet)

            // A raise only reopens betting when it is at least a full raise
            // (an opening bet of at least one big blind, or an increment of at
            // least the previous raise). Short all-ins don't reopen the action.
            let minBet = max(blindLevel.bigBlind, 1)
            let isFullRaise = previousBet == 0
                ? currentBet >= minBet
                : currentBet - previousBet >= lastRaiseSize
            if isFullRaise {
                lastRaiseSize = previousBet == 0 ? currentBet : currentBet - previousBet
                actedSinceFullRaise = []
            } else if previousBet == 0 {
                // An incomplete opening all-in: the increment it sets is its own
                // size, and `makeConstraints` floors the result at the minimum bet.
                lastRaiseSize = currentBet
            }
            actedSinceFullRaise.insert(seat)

            let allIn = players[seat].isAllIn
            if allIn {
                players[seat].lastAction = .allIn(players[seat].betThisStreet)
            } else if previousBet == 0 {
                players[seat].lastAction = .bet(currentBet)
            } else {
                players[seat].lastAction = .raise(currentBet)
            }
            onEvent?(.chipsCommitted(seat: seat, isAllIn: allIn))

            // Everyone else gets to respond to the new price.
            queue = seatsInOrder(from: nextActiveSeat(after: seat))
                .filter { $0 != seat && players[$0].canAct && players[$0].betThisStreet < currentBet }
        }
    }

    /// Refunds any uncalled portion of the leading bet, then sweeps street bets into the pot.
    private func collectBets() async {
        let bets = players.map(\.betThisStreet)
        let maxBet = bets.max() ?? 0
        if maxBet > 0 {
            let leaders = players.indices.filter { players[$0].betThisStreet == maxBet }
            if leaders.count == 1 {
                let secondMax = players.indices
                    .filter { $0 != leaders[0] }
                    .map { players[$0].betThisStreet }
                    .max() ?? 0
                let refund = maxBet - secondMax
                if refund > 0 {
                    players[leaders[0]].chips += refund
                    players[leaders[0]].betThisStreet -= refund
                    players[leaders[0]].totalInvested -= refund
                }
            }
        }

        let contributors = players.indices.filter { players[$0].betThisStreet > 0 }
        let swept = contributors.reduce(0) { $0 + players[$1].betThisStreet }

        // The street is over either way, so the price always resets — a street
        // whose whole bet was refunded must not leave a stale bet behind.
        currentBet = 0
        lastRaiseSize = 0
        guard swept > 0 else { return }

        onEvent?(.betsCollected(fromSeats: contributors.map { players[$0].id }))
        await pause(0.5)
        pot += swept
        for i in players.indices { players[i].betThisStreet = 0 }
        await pause(0.25)
    }

    // MARK: Community cards & runout

    private func dealCommunityCards(upTo count: Int) async {
        onEvent?(.streetRevealed(street))
        while communityCards.count < count {
            communityCards.append(deck.deal())
            onEvent?(.cardDealt(seat: nil))
            await pause(0.5)
        }
        await pause(0.35)
    }

    /// When everyone is all-in, flip the hole cards face up before running out the board.
    private func revealRunoutIfNeeded() async {
        guard !runoutRevealed,
              playersInHand.count >= 2,
              playersWhoCanAct.count <= 1 else { return }
        runoutRevealed = true
        for i in players.indices where players[i].isInHand {
            players[i].revealedCards = true
        }
        onEvent?(.showdownReveal)
        await pause(1.4)
    }

    // MARK: Hand conclusions

    /// Everyone folded to a single player: award without a showdown.
    private func concludeUncontested() async {
        guard let winner = playersInHand.first else { return }
        let seat = players.firstIndex { $0.id == winner.id }!
        let amount = pot

        await pause(0.4)
        players[seat].chips += amount
        pot = 0

        let result = HandResult(
            potResults: [PotResult(id: 0, amount: amount, eligibleSeats: [winner.id],
                                   winnerSeats: [winner.id], winningHandName: nil, isSidePot: false)],
            winnings: [winner.id: amount],
            winningCards: [],
            headline: players[seat].isHuman
                ? String(localized: "result.youWin \(amount.chipText)")
                : String(localized: "result.playerWins \(players[seat].name) \(amount.chipText)"),
            wentToShowdown: false)
        onEvent?(.potAwarded(toSeats: [winner.id], amount: amount))
        finishHand(with: result)
    }

    private func showdown() async {
        // Reveal every live hand.
        var revealedAny = false
        for i in players.indices where players[i].isInHand && !players[i].revealedCards {
            players[i].revealedCards = true
            revealedAny = true
        }
        if revealedAny {
            onEvent?(.showdownReveal)
            await pause(1.6)
        }

        let values: [Int: HandValue] = playersInHand.reduce(into: [:]) { result, player in
            result[player.id] = HandEvaluator.evaluate(player.holeCards + communityCards)
        }

        let pots = PotBuilder.build(players: players)
        var potResults: [PotResult] = []
        var winnings: [Int: Int] = [:]

        // Award side pots first (they sit at the end of the array), main pot last.
        for (index, potLayer) in pots.enumerated().reversed() {
            let best = potLayer.eligibleSeats.compactMap { values[$0] }.map(\.score).max() ?? 0
            let winners = potLayer.eligibleSeats.filter { values[$0]?.score == best }
            let ordered = orderedFromDealer(winners)

            var shares = Array(repeating: potLayer.amount / max(winners.count, 1), count: winners.count)
            let remainder = potLayer.amount - shares.reduce(0, +)
            if remainder > 0, !shares.isEmpty { shares[0] += remainder }

            for (i, seat) in ordered.enumerated() {
                let playerIndex = players.firstIndex { $0.id == seat }!
                players[playerIndex].chips += shares[i]
                winnings[seat, default: 0] += shares[i]
            }

            let winningHandName = ordered.first.flatMap { values[$0]?.name }
            potResults.append(PotResult(
                id: index, amount: potLayer.amount, eligibleSeats: potLayer.eligibleSeats,
                winnerSeats: ordered, winningHandName: winningHandName, isSidePot: index > 0))

            pot -= potLayer.amount
            onEvent?(.potAwarded(toSeats: ordered, amount: potLayer.amount))
            await pause(pots.count > 1 ? 1.3 : 0.4)
        }
        pot = 0

        // Headline from the main pot.
        let mainResult = potResults.last
        var headline = ""
        var winningCards: Set<Card> = []
        if let main = mainResult {
            let names = main.winnerSeats.map { seat in players.first { $0.id == seat }!.name }
            if main.winnerSeats.count > 1 {
                let joined = ListFormatter.localizedString(byJoining: names)
                headline = String(localized: "result.splitPot \(joined)")
            } else if let seat = main.winnerSeats.first {
                let player = players.first { $0.id == seat }!
                let amount = winnings[seat, default: 0].chipText
                switch (player.isHuman, main.winningHandName) {
                case (true, let hand?):
                    headline = String(localized: "result.youWinWithHand \(amount) \(hand)")
                case (true, nil):
                    headline = String(localized: "result.youWin \(amount)")
                case (false, let hand?):
                    headline = String(localized: "result.playerWinsWithHand \(player.name) \(amount) \(hand)")
                case (false, nil):
                    headline = String(localized: "result.playerWins \(player.name) \(amount)")
                }
            }
        }

        // A side pot is won separately, and the banner is the only thing that
        // says so in words: whoever took one and not the main pot would
        // otherwise get a gold ring and no explanation. Only worth saying when
        // it went somewhere else — where one player scoops every layer the
        // headline has already said it.
        //
        // The main pot is last in `potResults` and the outermost side pot first,
        // so dropping the tail and reversing names the layers from the middle
        // out, which is the order they were built in.
        let mainWinners = Set(mainResult?.winnerSeats ?? [])
        for side in potResults.dropLast().reversed() where Set(side.winnerSeats) != mainWinners {
            let names = side.winnerSeats.map { seat in players.first { $0.id == seat }!.name }
            let joined = ListFormatter.localizedString(byJoining: names)
            headline += " · " + String(localized: "result.sidePot \(side.amount.chipText) \(joined)")
        }
        // Union across every pot: a player who won only a side pot still has a
        // winning hand, and dimming their cards would say otherwise.
        for potResult in potResults {
            for seat in potResult.winnerSeats {
                guard let value = values[seat] else { continue }
                winningCards.formUnion(value.bestFive)
            }
        }

        let result = HandResult(
            potResults: potResults, winnings: winnings, winningCards: winningCards,
            headline: headline, wentToShowdown: true)
        finishHand(with: result)
    }

    /// Applies end-of-hand bookkeeping and returns the events describing it.
    ///
    /// State and events are deliberately separated: `.handFinished` carries the
    /// snapshot that gets persisted, so eliminations have to be recorded
    /// *before* it is emitted — otherwise a resumed game deals busted players
    /// back in with an empty stack.
    private func applyEliminations() -> [GameEvent] {
        var events: [GameEvent] = []
        for i in players.indices where players[i].chips == 0 && !players[i].isEliminated {
            players[i].isEliminated = true
            events.append(.playerEliminated(seat: players[i].id))
        }

        if players[humanSeat].isEliminated {
            gameOverHumanWon = false
            events.append(.gameOver(humanWon: false))
        } else if players.filter({ !$0.isEliminated }).count == 1 {
            gameOverHumanWon = true
            events.append(.gameOver(humanWon: true))
        }
        return events
    }

    /// Records eliminations, publishes the result, then announces the fallout.
    private func finishHand(with result: HandResult) {
        let endEvents = applyEliminations()
        handResult = result
        isHandInProgress = false
        onEvent?(.handFinished(result))
        for event in endEvents { onEvent?(event) }
    }

    // MARK: Seats & order

    private var playersInHand: [Player] { players.filter(\.isInHand) }
    private var playersWhoCanAct: [Player] { players.filter(\.canAct) }

    /// All non-eliminated seats in clockwise order starting at `start` (inclusive).
    private func seatsInOrder(from start: Int) -> [Int] {
        let n = players.count
        return (0..<n)
            .map { (start + $0) % n }
            .filter { !players[$0].isEliminated }
    }

    private func nextActiveSeat(after seat: Int) -> Int {
        let n = players.count
        var i = (seat + 1) % n
        while players[i].isEliminated { i = (i + 1) % n }
        return i
    }

    /// The next seat that can actually act, or — when nobody can — the next seat
    /// still in the hand, so callers never receive a folded or eliminated seat.
    private func nextInHandSeat(after seat: Int) -> Int {
        let order = seatsInOrder(from: (seat + 1) % players.count)
        if let actor = order.first(where: { players[$0].canAct }) { return actor }
        if let live = order.first(where: { players[$0].isInHand }) { return live }
        return order.first ?? seat
    }

    private func orderedFromDealer(_ seats: [Int]) -> [Int] {
        seatsInOrder(from: nextActiveSeat(after: dealerIndex)).filter(seats.contains)
    }

    /// Advances the button under dead-button rules: the big blind moves to the
    /// next live player every hand, so nobody is ever skipped over the big blind
    /// or made to pay it twice in a row. The two positions behind it follow the
    /// *players* rather than the seats — the small blind goes to whoever held
    /// the big blind last hand, the button to whoever held the small blind —
    /// and either is *dead* when that player has just been knocked out.
    ///
    /// Chaining the positions like that is what keeps a dead blind tied to the
    /// elimination that caused it. Deriving them from absolute seat indices
    /// instead (`bb - 1`, `bb - 2`) looks identical on a full table and is
    /// wrong on a broken one: the empty seats are never filled again, so the
    /// dead positions come back every single orbit. On a six-seat table down
    /// to seats 0, 2 and 5 that cost two hands in three their small blind
    /// outright, and seats 0 and 2 never posted one at all — a permanent half
    /// a big blind an orbit to whoever the busted seats happened to leave
    /// standing. `deadBlindsDoNotOutliveTheEliminationThatCausedThem` is what
    /// holds it shut.
    private func moveButton() {
        let liveCount = players.indices.filter { !players[$0].isEliminated }.count
        guard liveCount >= 2 else { return }

        guard let previousBigBlind = bigBlindSeat else {
            // First hand of a game, or one resumed from a save written before
            // the cycle was tracked: seed it from the button.
            dealerIndex = nextActiveSeat(after: dealerIndex)
            let firstSmallBlind = liveCount == 2
                ? dealerIndex                               // heads-up: the button posts it
                : nextActiveSeat(after: dealerIndex)
            smallBlindSeat = firstSmallBlind
            bigBlindSeat = nextActiveSeat(after: firstSmallBlind)
            return
        }

        // A save written before the small blind was tracked knows where the big
        // blind was but not the seat behind it; the old absolute position is the
        // closest thing to continuity, and the chain takes over from the next
        // hand on.
        let previousSmallBlind = smallBlindSeat
            ?? (previousBigBlind - 1 + players.count) % players.count

        let bb = nextActiveSeat(after: previousBigBlind)
        bigBlindSeat = bb
        if liveCount == 2 {
            // Heads-up: the button posts the small blind, and nothing can be
            // dead because both players post.
            dealerIndex = nextActiveSeat(after: bb)
            smallBlindSeat = dealerIndex
        } else {
            smallBlindSeat = previousBigBlind
            dealerIndex = previousSmallBlind    // may be an empty seat — a dead button
        }
    }

    /// The seats posting this hand's blinds. `sb` is nil for a *dead* small
    /// blind — the player it falls to has just been knocked out, so nobody
    /// posts it.
    private func blindSeats() -> (sb: Int?, bb: Int) {
        let bb = bigBlindSeat ?? nextActiveSeat(after: nextActiveSeat(after: dealerIndex))
        let liveCount = players.indices.filter { !players[$0].isEliminated }.count
        if liveCount == 2 {
            // Heads-up: the dealer posts the small blind.
            return (dealerIndex, bb)
        }
        let sbPosition = smallBlindSeat ?? (bb - 1 + players.count) % players.count
        return (players[sbPosition].isEliminated ? nil : sbPosition, bb)
    }

    private func updateBlindLevel() {
        guard let handsPerLevel = config.blindSpeed.handsPerLevel else { return }
        let levelIndex = min((handNumber - 1) / handsPerLevel, BlindLevel.schedule.count - 1)
        let newLevel = BlindLevel.schedule[levelIndex]
        if newLevel != blindLevel {
            blindLevel = newLevel
            onEvent?(.blindLevelUp(newLevel))
        }
    }

    // MARK: Decision routing

    private func obtainAction(seat: Int, constraints: ActionConstraints) async -> PlayerAction {
        if let override = actionOverride {
            return await override(seat, constraints)
        }

        let player = players[seat]
        if player.isHuman {
            onEvent?(.humanTurn)
            humanConstraints = constraints
            return await withCheckedContinuation { humanContinuation = $0 }
        }

        // A scripted seat still pauses, so the table does not jump a whole
        // street between two frames of the same animation.
        if let scripted = aiActionOverride?(seat, constraints) {
            await pause(0.5)
            return scripted
        }

        let input = AIDecisionInput(
            holeCards: player.holeCards,
            communityCards: communityCards,
            street: street,
            potTotal: totalPot,
            toCall: constraints.toCall,
            canRaise: constraints.canRaise,
            minRaiseTo: constraints.minRaiseTo,
            maxRaiseTo: constraints.maxRaiseTo,
            myBetThisStreet: player.betThisStreet,
            myChips: player.chips,
            currentBet: currentBet,
            bigBlind: blindLevel.bigBlind,
            opponentsInHand: playersInHand.count - 1,
            positionScore: positionScore(of: seat),
            opponentRange: perceivedOpponentRange,
            personality: player.personality,
            difficulty: config.difficulty)

        let decision = await Task.detached(priority: .userInitiated) {
            AIBrain.decide(input)
        }.value

        // Thinking time: quick checks are fast, big decisions take longer.
        let base = constraints.toCall > 0 ? Double.random(in: 0.9...2.0) : Double.random(in: 0.55...1.2)
        await pause(base)
        return decision
    }

    /// How much this street's betting narrows what the opposition can hold.
    /// 0 = nothing has happened, so any two cards are possible.
    private var perceivedOpponentRange: Double {
        let bigBlind = max(blindLevel.bigBlind, 1)
        // Both curves saturate smoothly: each extra big blind (or extra fraction
        // of the pot) narrows what the opposition can credibly hold, with
        // diminishing returns rather than a cliff.
        if street == .preflop {
            let raiseInBigBlinds = Double(currentBet) / Double(bigBlind)
            return min(1, max(0, 1 - pow(0.72, raiseInBigBlinds - 1)))
        }
        let potBeforeBet = max(totalPot - currentBet, bigBlind)
        let betFraction = Double(currentBet) / Double(potBeforeBet)
        return min(1, max(0, 1 - pow(0.45, betFraction)))
    }

    /// 0 = first to act post-flop, 1 = button.
    private func positionScore(of seat: Int) -> Double {
        let order = seatsInOrder(from: nextActiveSeat(after: dealerIndex)).filter { players[$0].isInHand }
        guard order.count > 1, let index = order.firstIndex(of: seat) else { return 0.5 }
        return Double(index) / Double(order.count - 1)
    }

    // MARK: Human helpers

    /// Live description of the human's current best hand, e.g. "Pair of Kings".
    var humanHandLabel: String? {
        let human = players[humanSeat]
        guard human.isInHand, human.holeCards.count == 2 else { return nil }
        let all = human.holeCards + communityCards
        if all.count >= 5 {
            return HandEvaluator.evaluate(all).name
        }
        let first = human.holeCards[0], second = human.holeCards[1]
        if first.rank == second.rank {
            return String(localized: "hand.name.pair \(first.rank.name(.pluralPossessive))")
        }
        return String(localized: "hand.name.highCard \(max(first.rank, second.rank).name(.singular))")
    }

    /// Re-estimates the odds after they have been switched back on mid-hand.
    /// Without it the HUD would stay blank until the next street, because
    /// nothing else asks between one street and the next.
    func refreshHumanEquity() {
        updateHumanEquity()
    }

    private func updateHumanEquity() {
        let human = players[humanSeat]
        guard oddsProvider(), human.isInHand, human.holeCards.count == 2 else {
            // Cancel before clearing, not after: an estimate already in flight
            // for the hand the human has just folded out of would otherwise
            // land afterwards and put a number back.
            equityTask?.cancel()
            humanEquity = nil
            return
        }
        let hole = human.holeCards
        let board = communityCards
        let opponents = max(playersInHand.count - 1, 1)

        equityTask?.cancel()
        equityTask = Task { [weak self] in
            let equity = await Task.detached(priority: .utility) {
                AIBrain.equity(hole: hole, board: board, opponents: opponents, iterations: 700)
            }.value
            guard !Task.isCancelled else { return }
            self?.humanEquity = equity
        }
    }

    // MARK: Pacing

    private func pause(_ seconds: Double) async {
        guard !instantMode else {
            await Task.yield()
            return
        }
        let scale = max(speedProvider(), 0.1)
        try? await Task.sleep(for: .seconds(seconds / scale))
    }
}
