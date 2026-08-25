import SwiftUI
import Observation

// MARK: - Transient UI models

struct ChipFlight: Identifiable {
    let id = UUID()
    /// nil = the pot
    let fromSeat: Int?
    let toSeat: Int?
    let amount: Int
}

// MARK: - Game Session

/// Owns the engine for one game and translates engine events into
/// sounds, haptics, chip flights, confetti and stat recording.
/// Also snapshots the game between hands so it survives leaving the table.
@MainActor
@Observable
final class GameSession {
    private(set) var game: PokerGame

    private(set) var chipFlights: [ChipFlight] = []
    private(set) var confettiBurst = 0          // increment triggers a burst
    private(set) var toast: String?
    var showGameOver = false

    private let config: GameConfig
    private var toastTask: Task<Void, Never>?
    private var autopilotTask: Task<Void, Never>?
    /// Leaving the table calls `stop()` from the quit dialog and again from
    /// `GameView.onDisappear`. Both have to work on their own, so the second one
    /// has to do nothing rather than take a second forfeit off the same hand.
    private var isStopped = false

    init(config: GameConfig, restoring saved: SavedGame? = nil) {
        self.config = config
        game = PokerGame(config: config, restoring: saved)
        wire(game)
    }

    private func wire(_ game: PokerGame) {
        game.speedProvider = { SettingsStore.shared.gameSpeed.multiplier }
        game.oddsProvider = { SettingsStore.shared.showOdds }
        game.onEvent = { [weak self] event in
            self?.handle(event)
        }
    }

    func start() {
        isStopped = false
        SoundManager.shared.prepare()
        // Blinds are posted and cards are dealt within the first second, and
        // both of them buzz. See `Haptics.prepare()`.
        Haptics.prepare()
        game.start()
        startAutopilotIfRequested()
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        autopilotTask?.cancel()
        // Walking away mid-hand forfeits what you have already put in, so
        // leaving the table can never rewind a hand that was going badly.
        if game.isHandInProgress {
            persistSnapshot()
        }
        game.stop()
    }

    /// Writes what a resume should find, without stopping the game.
    ///
    /// Called when the app leaves the foreground. That is *not* `onDisappear`:
    /// the table stays on screen and the hand carries on if the app comes back,
    /// so the engine must keep running — but the system can also kill a
    /// suspended app, and then whatever is on disk is what "Continue" offers.
    /// Without this that would be the *previous* hand boundary, handing back
    /// everything committed to the hand in progress. Which is precisely the
    /// loophole `forfeitSnapshot()` exists to close: shove, force-quit, and the
    /// bad hand never happened. Coming back instead simply overwrites this at
    /// the next hand boundary.
    func persistForResume() {
        guard !isStopped else { return }
        persistSnapshot()
    }

    /// If the forfeit busts you — or leaves nobody to play — there is nothing to
    /// come back to and the save goes with it.
    private func persistSnapshot() {
        // A finished game has already cleared its save, and re-storing one here
        // would put "Continue" back on the menu for a tournament that is over.
        guard game.gameOverHumanWon == nil else { return }
        let snapshot = game.isHandInProgress ? game.forfeitSnapshot() : game.snapshot()
        if snapshot.humanChips > 0 && snapshot.opponentsLeft > 0 {
            SavedGameStore.shared.store(snapshot)
        } else {
            SavedGameStore.shared.clear()
        }
    }

    /// Starts a brand new game with the same table setup.
    func rematch() {
        stop()
        SavedGameStore.shared.clear()
        chipFlights = []
        toast = nil
        showGameOver = false
        let fresh = PokerGame(config: config)
        wire(fresh)
        game = fresh
        start()
    }

    /// QA hook (`-qa-autopilot` launch argument): auto-plays the human seat
    /// so full hands can be observed without touch input.
    ///
    /// Debug only, like the `-shot` poses: launch arguments cannot reach a
    /// shipped app anyway, so the whole facility has no business being in the
    /// binary that does ship.
    private func startAutopilotIfRequested() {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-qa-autopilot") else { return }
        autopilotTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                // Stop outright once the session is gone, rather than looping on
                // a nil `self` for as long as the process lives.
                guard let self else { return }
                guard let constraints = self.game.humanConstraints else { continue }
                self.game.submitHumanAction(constraints.canCheck ? .check : .call)
            }
        }
        #endif
    }

    func removeFlight(_ id: UUID) {
        chipFlights.removeAll { $0.id == id }
    }

    // MARK: Event handling

    private func handle(_ event: GameEvent) {
        switch event {
        case .handStarted:
            SoundManager.shared.play(.shuffle)
            chipFlights = []

        case .blindsPosted:
            SoundManager.shared.play(.chipsSmall)

        case .blindLevelUp(let level):
            SoundManager.shared.play(.levelUp)
            showToast(String(localized: "toast.blindsUp \(level.smallBlind.chipText) \(level.bigBlind.chipText)"))

        case .cardDealt:
            SoundManager.shared.play(.deal)

        case .chipsCommitted(_, let isAllIn):
            SoundManager.shared.play(isAllIn ? .allIn : .chipsSmall)
            Haptics.chips()
            if isAllIn { Haptics.heavyHit() }

        case .playerChecked:
            SoundManager.shared.play(.check)

        case .playerFolded:
            SoundManager.shared.play(.fold)

        case .betsCollected(let seats):
            for seat in seats {
                let amount = game.players.first { $0.id == seat }?.betThisStreet ?? 0
                guard amount > 0 else { continue }
                chipFlights.append(ChipFlight(fromSeat: seat, toSeat: nil, amount: amount))
            }
            SoundManager.shared.play(.chipsSmall)

        case .streetRevealed:
            break

        case .humanTurn:
            SoundManager.shared.play(.yourTurn)
            Haptics.tap()
            // The action bar has just gone live, so the next thing to happen is
            // a tap on it. That is the one moment in a hand where the app knows
            // a haptic is coming and roughly when. See `Haptics.prepare()`.
            Haptics.prepare()
            // The sound and the haptic are the only things that say the table is
            // waiting, and neither reaches VoiceOver. Without this a blind
            // player has to keep swiping back to the action bar to find out
            // whether it is live yet. The post is a no-op when VoiceOver is off.
            AccessibilityNotification.Announcement(localized("a11y.yourTurn")).post()

        case .showdownReveal:
            SoundManager.shared.play(.flip)

        case .potAwarded(let seats, let amount):
            // Split the flights the way the engine splits the pot — odd chip to
            // the first seat left of the button, which is the order `seats`
            // arrives in — so the amounts flying out add up to the pot.
            let share = amount / max(seats.count, 1)
            let oddChips = amount - share * seats.count
            for (index, seat) in seats.enumerated() {
                chipFlights.append(ChipFlight(fromSeat: nil, toSeat: seat,
                                              amount: share + (index == 0 ? oddChips : 0)))
            }
            SoundManager.shared.play(.chipsBig)

        case .handFinished(let result):
            recordHand(result)
            // Hand boundary: safe point to snapshot for resuming later.
            SavedGameStore.shared.store(game.snapshot())

        case .playerEliminated(let seat):
            if seat != game.humanSeat {
                let name = game.players.first { $0.id == seat }?.name ?? ""
                showToast(String(localized: "toast.playerOut \(name)"))
            }

        case .gameOver(let humanWon):
            StatsStore.shared.recordGame(won: humanWon)
            SavedGameStore.shared.clear()
            if humanWon {
                SoundManager.shared.play(.victory)
                Haptics.success()
                confettiBurst += 3
            } else {
                SoundManager.shared.play(.lose)
                Haptics.warning()
            }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation(Motion.fading(.spring(duration: 0.6), over: 0.4)) {
                    self?.showGameOver = true
                }
            }
        }
    }

    private func recordHand(_ result: HandResult) {
        let humanSeat = game.humanSeat
        let humanWinnings = result.winnings[humanSeat] ?? 0
        let human = game.players[humanSeat]
        let humanSawShowdown = result.wentToShowdown && human.isInHand
        // Taking down a 400 pot you put 300 into is a 100 chip win, so the
        // recorded figure is profit — the share of the pot minus what it cost.
        let profit = humanWinnings - human.totalInvested

        StatsStore.shared.recordHand(
            humanWon: humanWinnings > 0,
            profit: profit,
            wentToShowdown: result.wentToShowdown,
            humanSawShowdown: humanSawShowdown)

        if humanSawShowdown, human.holeCards.count == 2, game.communityCards.count == 5 {
            StatsStore.shared.recordHumanHand(
                HandEvaluator.evaluate(human.holeCards + game.communityCards))
        }

        if humanWinnings > 0 {
            SoundManager.shared.play(.win)
            Haptics.success()
            if humanWinnings >= game.blindLevel.bigBlind * 18 {
                confettiBurst += 1
            }
        }
    }

    private func showToast(_ text: String) {
        toastTask?.cancel()
        withAnimation(Motion.fading(.spring(duration: 0.4), over: 0.4)) { toast = text }
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) { self?.toast = nil }
        }
    }
}
