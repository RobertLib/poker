#if DEBUG
import Foundation

// MARK: - App Store screenshot scenes
//
// Deterministic poses for the App Store screenshots and the App Preview, picked
// by `-shot <name>`. The shot list lives in AppStore/screenshots.md and the
// script that drives them in Tools/appstore_media.sh.
//
// The whole file is Debug-only, so none of it reaches an App Store build.
//
// A pose is a *real* hand of poker that happens to be dealt the same way every
// time — not a mocked screen. It is built only out of hooks the engine already
// exposes to the tests: a stacked deck, a pinned button, a restored stack
// snapshot and a scripted opposition. That matters, because a mocked table
// drifts away from the game as the game changes, whereas a pose that stops
// being legal stops rendering.
//
// Everything scripted here is keyed by *street* rather than by turn order.
// Turn order depends on the button, on who folded and on whether a raise
// reopened the action; a positional script would quietly photograph the wrong
// moment the first time any of that changed.

// MARK: - Pose

/// One table pose: who is sitting, what everyone holds, what the board runs out
/// as, and how the hand is played up to the moment being photographed.
struct TablePose {
    /// Profile ids from `AIProfile.roster`, seated at 1…n.
    var opponents: [String]
    /// Seat that holds the button for the posed hand.
    var dealer: Int
    /// Chips per seat; index 0 is you. The sum stays believable for the
    /// starting stack, because the table shows every stack at once.
    var stacks: [Int]
    /// Only used to pick the blind level — hand 41 at Normal speed is 40/80.
    var handNumber: Int
    var startingChips: Int
    var difficulty: Difficulty = .normal
    var blindSpeed: BlindSpeed = .normal

    /// Hole cards by seat. Seats left out are dealt whatever is left over, so
    /// specify every seat for a pose that reaches a showdown.
    var hole: [Int: [Card]]
    /// The runout, from the flop onwards. Fewer than five cards is fine when
    /// the pose stops before the river.
    var board: [Card]

    /// One action per seat per street. Anything unscripted checks if it can and
    /// calls if it cannot, which keeps the hand alive rather than folding it out
    /// from under the shot.
    var aiPlan: [Int: [Street: PlayerAction]] = [:]

    /// The street on which the shot is taken: your turn is played for you
    /// (check, or call) until this street, and then the action bar is left
    /// waiting. `nil` plays the hand out to the showdown.
    var holdAt: Street?
    /// Stop the engine when the hand finishes, so the result banner and the
    /// highlighted winning cards stay on screen instead of being dealt over.
    var freezeOnHandEnd = false

    var seatCount: Int { opponents.count + 1 }

    /// The rigged deck for this pose.
    ///
    /// The engine deals two passes starting to the left of the button and takes
    /// no burn cards, so with `n` seats a seat `s` gets deck slots `o` and
    /// `n + o`, where `o` is how far it sits after the button. The board follows
    /// at `2n`. Slots nobody asked for are filled with whatever is left, in a
    /// fixed order — a pose has to deal the same cards on every run.
    func stackedDeck() -> Deck {
        let n = seatCount
        var slots = [Card?](repeating: nil, count: 2 * n + 5)
        for (seat, cards) in hole where cards.count == 2 {
            let offset = ((seat - dealer - 1) % n + n) % n
            slots[offset] = cards[0]
            slots[n + offset] = cards[1]
        }
        for (index, card) in board.prefix(5).enumerated() {
            slots[2 * n + index] = card
        }
        let used = Set(slots.compactMap { $0 })
        var spare = Card.fullDeck.filter { !used.contains($0) }.makeIterator()
        let cards = slots.map { $0 ?? spare.next()! }
        return Deck(stacked: cards)
    }
}

// MARK: - Scenes

enum ShotScene {
    case menu
    /// The new-game screen. What it shows comes from `applySettings` writing the
    /// "last used" table setup, which is where `GameSetupView` reads it from —
    /// there is nothing for the case itself to carry.
    case setup
    case rules
    case stats
    case settings
    case table(TablePose)
}

// MARK: - Catalogue

enum Shots {

    /// `-shot <name>`, or nil in a normal run.
    static var requestedName: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-shot"),
              index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static var requested: ShotScene? {
        guard let name = requestedName else { return nil }
        return catalogue[name]
    }

    // Shorthands, so the poses below read as cards rather than as initialisers.
    private static func c(_ rank: Rank, _ suit: Suit) -> Card { Card(rank: rank, suit: suit) }
    /// A raise the engine will clamp to the seat's whole stack.
    private static let shove = PlayerAction.raise(to: Int.max)

    static let catalogue: [String: ShotScene] = [

        // 1 — the hero shot. Six seats, 1.3K in the middle, and you are facing
        // a bet on the turn holding the ace-high flush the app is named after.
        "01-table": .table(TablePose(
            opponents: ["viktor", "rosa", "moose", "rex", "greta"],
            dealer: 3,
            stacks: [2150, 1480, 3260, 640, 2900, 1570],
            handNumber: 40,
            startingChips: 2000,
            hole: [0: [c(.ace, .spades), c(.king, .spades)]],
            board: [c(.king, .hearts), c(.nine, .spades), c(.four, .spades), c(.queen, .spades)],
            aiPlan: [
                // Rex opens both streets, so your turn arrives with a price on it.
                4: [.flop: .raise(to: 160), .turn: .raise(to: 380)],
                1: [.flop: .fold],
                3: [.flop: .fold],
                5: [.flop: .fold],
            ],
            holdAt: .turn)),

        // 2 — the payoff. Kings full against trip nines, banner up, winning
        // cards lit, and the engine stopped so it stays there.
        "02-showdown": .table(TablePose(
            opponents: ["viktor", "rosa", "moose"],
            dealer: 2,
            stacks: [4200, 3900, 1150, 2750],
            handNumber: 40,
            startingChips: 3000,
            hole: [
                0: [c(.king, .diamonds), c(.king, .spades)],
                1: [c(.ace, .spades), c(.nine, .diamonds)],
                2: [c(.queen, .spades), c(.jack, .spades)],
                3: [c(.ace, .hearts), c(.ten, .clubs)],
            ],
            board: [c(.king, .clubs), c(.nine, .hearts), c(.nine, .spades),
                    c(.four, .diamonds), c(.two, .clubs)],
            aiPlan: [
                1: [.preflop: .raise(to: 240), .flop: .raise(to: 300),
                    .turn: .raise(to: 600), .river: .raise(to: 900)],
                2: [.preflop: .fold],
                3: [.preflop: .fold],
            ],
            holdAt: nil,
            freezeOnHandEnd: true)),

        // 3 — bet sizing. `-qa-raise` opens the panel; the pot fractions and the
        // all-in button only mean something with a pot worth carving up, so the
        // pose stops on the flop after a raised pot.
        "03-raise": .table(TablePose(
            opponents: ["rosa", "rex", "greta", "ace"],
            dealer: 4,
            stacks: [3400, 1960, 2820, 1100, 2720],
            handNumber: 40,
            startingChips: 2400,
            hole: [0: [c(.ace, .hearts), c(.ace, .clubs)]],
            board: [c(.ten, .diamonds), c(.seven, .hearts), c(.two, .spades)],
            aiPlan: [
                2: [.preflop: .raise(to: 220)],
                1: [.flop: .fold],
                3: [.flop: .fold],
            ],
            holdAt: .flop)),

        // 4 — the table you get to build, with the line-up you will actually
        // face underneath the seat count.
        "04-setup": .setup,

        // 5 — the moment the game is about: an overpair, a shove, and the win
        // probability on your hand. Four-colour deck on, garnet felt, so the
        // set is not five variations of the same green table.
        "05-allin": .table(TablePose(
            opponents: ["viktor", "greta", "rex"],
            dealer: 1,
            stacks: [3800, 2900, 1400, 3900],
            handNumber: 40,
            startingChips: 3000,
            hole: [0: [c(.ace, .spades), c(.ace, .diamonds)]],
            board: [c(.nine, .diamonds), c(.seven, .hearts), c(.two, .spades), c(.king, .clubs)],
            aiPlan: [
                3: [.flop: .raise(to: 300), .turn: shove],
                1: [.turn: .fold],
                2: [.flop: .fold],
            ],
            holdAt: .turn)),

        // 6, 7, 8 — the screens around the table.
        "06-rules": .rules,
        "07-stats": .stats,
        "08-menu": .menu,

        // Preview clips. The App Preview needs motion, so these play themselves:
        // no `holdAt`, and the human seat calls its way to the showdown.
        "preview-hand": .table(TablePose(
            opponents: ["viktor", "rosa", "moose", "rex", "greta"],
            dealer: 3,
            stacks: [2150, 1480, 3260, 940, 2900, 1570],
            handNumber: 40,
            startingChips: 2000,
            hole: [
                0: [c(.ace, .spades), c(.king, .spades)],
                4: [c(.queen, .hearts), c(.queen, .clubs)],
            ],
            board: [c(.king, .hearts), c(.nine, .spades), c(.four, .spades),
                    c(.queen, .spades), c(.three, .diamonds)],
            aiPlan: [
                4: [.flop: .raise(to: 160), .turn: .raise(to: 380), .river: .raise(to: 620)],
                1: [.flop: .fold],
                3: [.flop: .fold],
                5: [.flop: .fold],
            ],
            holdAt: nil,
            freezeOnHandEnd: true)),

        "preview-allin": .table(TablePose(
            opponents: ["viktor", "greta", "rex"],
            dealer: 1,
            stacks: [3800, 2900, 1400, 3900],
            handNumber: 40,
            startingChips: 3000,
            hole: [
                0: [c(.ace, .spades), c(.ace, .diamonds)],
                3: [c(.king, .hearts), c(.queen, .hearts)],
            ],
            board: [c(.nine, .diamonds), c(.seven, .hearts), c(.two, .spades),
                    c(.king, .clubs), c(.five, .clubs)],
            aiPlan: [
                3: [.flop: .raise(to: 300), .turn: shove],
                1: [.turn: .fold],
                2: [.flop: .fold],
            ],
            holdAt: nil,
            freezeOnHandEnd: true)),
    ]

    // MARK: Settings

    /// Per-shot appearance, so the set is not five pictures of the same felt and
    /// the features that live in Settings can be seen doing something.
    static func applySettings() {
        guard let name = requestedName else { return }
        let settings = SettingsStore.shared
        // Everything below is a pose, not a preference: keep it out of
        // `UserDefaults` so taking a picture on a real device does not replace
        // whatever that player had chosen.
        settings.makeEphemeral()
        settings.soundEnabled = false        // the simulator records no audio anyway
        settings.hapticsEnabled = false
        settings.showOdds = true
        settings.fourColorDeck = false
        settings.feltTheme = .emerald
        // Only affects how long a pose takes to arrive, never what it looks
        // like once it has: the script waits for the marker, not for a clock.
        settings.gameSpeed = .fast
        settings.lastOpponentCount = 4
        settings.lastStartingChips = 2500
        settings.lastDifficulty = .hard
        settings.lastBlindSpeed = .normal

        switch name {
        case "03-raise":
            settings.feltTheme = .sapphire
        case "05-allin", "preview-allin":
            settings.feltTheme = .garnet
            settings.fourColorDeck = true
        case "04-setup":
            settings.lastOpponentCount = 5
        default:
            break
        }
    }

    /// Statistics and a game to continue, for the two shots that would otherwise
    /// photograph an empty screen.
    static func applyStores() {
        switch requestedName {
        case "07-stats":
            StatsStore.shared.injectDemoValues()
        case "08-menu":
            // A saved game is what puts "Continue" above "New Game" — the
            // clearest way to show that leaving the table costs you nothing.
            SavedGameStore.shared.storeEphemeral(SavedGame(
                opponentIDs: ["viktor", "rosa", "moose", "rex"],
                startingChips: 2000,
                difficulty: .hard,
                blindSpeed: .normal,
                stacks: [3480, 1220, 2650, 1900, 750],
                eliminated: [false, false, false, false, false],
                dealerIndex: 2,
                handNumber: 37,
                bigBlindSeat: 4))
            StatsStore.shared.injectDemoValues()
        default:
            break
        }
    }

    // MARK: Table poses

    /// Builds the session for a table pose with every hook set before the engine
    /// is started by `GameView`.
    static func makeSession(_ pose: TablePose) -> GameSession {
        let saved = SavedGame(
            opponentIDs: pose.opponents,
            startingChips: pose.startingChips,
            difficulty: pose.difficulty,
            blindSpeed: pose.blindSpeed,
            stacks: pose.stacks,
            eliminated: Array(repeating: false, count: pose.seatCount),
            dealerIndex: pose.dealer,
            handNumber: pose.handNumber,
            bigBlindSeat: nil)
        guard let config = saved.config else {
            preconditionFailure("shot pose does not resolve: \(pose.opponents)")
        }
        let session = GameSession(config: config, restoring: saved)
        let driver = PoseDriver(pose: pose, session: session)
        driver.attach()
        // The engine only ever holds the driver weakly, through the closures it
        // installs, so something has to own it — without this it is deallocated
        // before the first card is dealt and the pose quietly becomes an
        // ordinary hand against the real AI.
        activeDriver = driver
        return session
    }

    /// Owner of the driver for the shot currently being taken. One shot per
    /// launch, so one slot is enough.
    private static var activeDriver: AnyObject?

    // MARK: Readiness marker

    /// A posed hand is a real hand, so it takes as long to arrive as the deal,
    /// the blinds and two streets of betting take — which is a different length
    /// on every pose, on every device and at every game speed. Rather than have
    /// the capture script sleep for a guess, the app drops this file when the
    /// moment being photographed is actually on screen, and the script waits for
    /// it. See `wait_ready` in Tools/appstore_media.sh.
    private static let readyMarker = URL.documentsDirectory.appending(path: "shot-ready")

    /// Removes any marker left behind by the previous launch.
    static func clearReadyMarker() {
        try? FileManager.default.removeItem(at: readyMarker)
    }

    /// Marks the shot ready once the last animation has had time to land.
    static func markReady(after delay: Double = 1.6) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            try? Data().write(to: readyMarker)
        }
    }
}

// MARK: - Pose driver

/// Drives one posed hand: rigs the deck, pins the button, answers for the
/// opposition and plays your seat up to the street being photographed.
///
/// Owned by `Shots.activeDriver` and holding the session weakly, so the pose
/// does not keep a finished game alive: the session owns the engine, the engine
/// owns the closures installed below, and those close over this weakly.
@MainActor
private final class PoseDriver {
    private let pose: TablePose
    private weak var session: GameSession?
    /// One scripted action per seat per street; a seat asked twice on the same
    /// street falls through to checking or calling, so a re-raise cannot make it
    /// fire the same bet again.
    private var spent: Set<String> = []

    init(pose: TablePose, session: GameSession) {
        self.pose = pose
        self.session = session
    }

    func attach() {
        guard let game = session?.game else { return }
        game.deckProvider = { [pose] in pose.stackedDeck() }
        // `_setDealerForTesting(before:)` makes the *next* hand's button the
        // seat given, which is the hand this pose is about to deal.
        game._setDealerForTesting(before: pose.dealer)
        game.aiActionOverride = { [weak self] seat, constraints in
            self?.aiAction(seat: seat, constraints: constraints)
        }
        let existing = game.onEvent
        game.onEvent = { [weak self] event in
            existing?(event)
            self?.handle(event)
        }
    }

    private func aiAction(seat: Int, constraints: ActionConstraints) -> PlayerAction? {
        guard let game = session?.game else { return nil }
        let key = "\(seat)-\(game.street.rawValue)"
        if let action = pose.aiPlan[seat]?[game.street], !spent.contains(key) {
            spent.insert(key)
            return action
        }
        // Never fold an unscripted seat: a pose that folds itself out photographs
        // an empty table.
        return constraints.canCheck ? .check : .call
    }

    private func handle(_ event: GameEvent) {
        guard let game = session?.game else { return }
        switch event {
        case .humanTurn:
            // Play your seat until the street being photographed, then leave the
            // action bar waiting exactly as it would wait for a real tap.
            if let hold = pose.holdAt, game.street >= hold {
                // This is the photograph: your turn, on the street the pose was
                // built for, with the action bar live.
                Shots.markReady()
                return
            }
            // `.humanTurn` is emitted just *before* the engine installs the
            // continuation it will wait on, so answering it in the same turn of
            // the run loop is dropped on the floor and the pose deadlocks on the
            // first decision. Let the engine get there first.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                guard let game = self?.session?.game,
                      let constraints = game.humanConstraints else { return }
                game.submitHumanAction(constraints.canCheck ? .check : .call)
            }

        case .handFinished:
            guard pose.freezeOnHandEnd else { return }
            // The run loop would deal over the result banner after 3.4 s.
            game.stop()
            // Longer than the rest: the pot has to finish flying to the winner
            // and the confetti has to reach the top of its arc.
            Shots.markReady(after: 2.6)

        default:
            break
        }
    }
}
#endif
