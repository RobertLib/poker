import Foundation
import Observation

// MARK: - Game speed

enum GameSpeed: String, CaseIterable, Codable, Identifiable {
    case relaxed = "Relaxed"
    case normal = "Normal"
    case fast = "Fast"

    var id: String { rawValue }

    var displayName: String { localized(.init("gameSpeed.\(rawValue.lowercased())")) }

    var multiplier: Double {
        switch self {
        case .relaxed: return 0.72
        case .normal: return 1.0
        case .fast: return 1.65
        }
    }
}

// MARK: - Settings

@MainActor
@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    var soundEnabled: Bool { didSet { save() } }
    var hapticsEnabled: Bool { didSet { save() } }
    var showOdds: Bool { didSet { save() } }
    var fourColorDeck: Bool { didSet { save() } }
    var gameSpeed: GameSpeed { didSet { save() } }
    var feltTheme: FeltTheme { didSet { save() } }

    // Last used table setup (restored in the new game screen)
    var lastOpponentCount: Int { didSet { save() } }
    var lastStartingChips: Int { didSet { save() } }
    var lastDifficulty: Difficulty { didSet { save() } }
    var lastBlindSpeed: BlindSpeed { didSet { save() } }

    private static let key = "poker.settings.v1"

    #if DEBUG
    /// Set by `Shots.applySettings()`. A screenshot run rewrites every setting to
    /// pose the shot, and on a real device that would silently replace the
    /// player's own choices — so in this mode the values apply to the running
    /// app and nothing is written to `UserDefaults`. Debug-only, like the poses.
    @ObservationIgnored private var isEphemeral = false

    func makeEphemeral() { isEphemeral = true }
    #endif

    private struct Payload: Codable {
        var soundEnabled = true
        var hapticsEnabled = true
        var showOdds = false
        var fourColorDeck = false
        var gameSpeed = GameSpeed.normal
        var feltTheme = FeltTheme.emerald
        var lastOpponentCount = 4
        var lastStartingChips = 1000
        var lastDifficulty = Difficulty.normal
        var lastBlindSpeed = BlindSpeed.normal
    }

    private init() {
        var payload = Payload()
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(Payload.self, from: data) {
            payload = decoded
        }
        soundEnabled = payload.soundEnabled
        hapticsEnabled = payload.hapticsEnabled
        showOdds = payload.showOdds
        fourColorDeck = payload.fourColorDeck
        gameSpeed = payload.gameSpeed
        feltTheme = payload.feltTheme
        lastOpponentCount = payload.lastOpponentCount
        lastStartingChips = payload.lastStartingChips
        lastDifficulty = payload.lastDifficulty
        lastBlindSpeed = payload.lastBlindSpeed
    }

    private func save() {
        #if DEBUG
        guard !isEphemeral else { return }
        #endif
        let payload = Payload(
            soundEnabled: soundEnabled,
            hapticsEnabled: hapticsEnabled,
            showOdds: showOdds,
            fourColorDeck: fourColorDeck,
            gameSpeed: gameSpeed,
            feltTheme: feltTheme,
            lastOpponentCount: lastOpponentCount,
            lastStartingChips: lastStartingChips,
            lastDifficulty: lastDifficulty,
            lastBlindSpeed: lastBlindSpeed)
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

// MARK: - Saved game store

@MainActor
@Observable
final class SavedGameStore {
    static let shared = SavedGameStore()

    private(set) var saved: SavedGame?

    private static let key = "poker.savedgame.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key) {
            saved = try? JSONDecoder().decode(SavedGame.self, from: data)
        }
        // A snapshot whose roster no longer resolves is unusable.
        if saved?.config == nil { clear() }
    }

    func store(_ game: SavedGame) {
        saved = game
        if let data = try? JSONEncoder().encode(game) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    func clear() {
        saved = nil
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    #if DEBUG
    /// A saved game for the menu shot to offer "Continue" on, held in memory
    /// only. Photographing the menu must not cost a real device the game it had
    /// waiting — the same reason `StatsStore.injectDemoValues()` assigns its
    /// stored properties instead of replaying hands.
    func storeEphemeral(_ game: SavedGame) {
        saved = game
    }
    #endif
}

// MARK: - Statistics

@MainActor
@Observable
final class StatsStore {
    static let shared = StatsStore()

    private(set) var gamesPlayed = 0
    private(set) var gamesWon = 0
    private(set) var handsPlayed = 0
    private(set) var handsWon = 0
    private(set) var showdownsSeen = 0
    private(set) var showdownsWon = 0
    /// Best single-hand profit — the share of the pot minus what the hand cost,
    /// not the size of the pot. Values written before this was net stay as they
    /// were rather than resetting everyone's history.
    private(set) var biggestWin = 0
    private(set) var bestHandCategoryRaw = -1
    /// The record hand's encoded value, which is everything `HandValue.name`
    /// needs to say it again. Stored instead of the finished sentence because
    /// that sentence is localised: a record set on a Czech device used to keep
    /// reading "Full house: králové a devítky" after the phone was switched to
    /// English. 0 = no record, or one written before this was kept.
    private(set) var bestHandScore: UInt32 = 0
    /// What older versions wrote: the name as text, in whatever language the
    /// device was in at the time. Shown only while no scored record exists —
    /// the ranks needed to rebuild those were never on disk, and the stale
    /// wording is still more use to the player than dropping the record.
    private(set) var legacyBestHandName = ""
    private(set) var currentStreak = 0   // consecutive hands won
    private(set) var bestStreak = 0

    var winRate: Double { handsPlayed == 0 ? 0 : Double(handsWon) / Double(handsPlayed) }

    /// The record hand, named in the language the app is running in now.
    var bestHandName: String {
        // `encode` puts the category in the bits above the tiebreakers, so the
        // score carries its own category and nothing else has to be stored.
        guard bestHandScore > 0,
              let category = HandCategory(rawValue: Int(bestHandScore >> 20)) else {
            return legacyBestHandName
        }
        return HandValue(category: category, score: bestHandScore, bestFive: []).name
    }

    private static let key = "poker.stats.v1"

    private struct Payload: Codable {
        var gamesPlayed = 0, gamesWon = 0
        var handsPlayed = 0, handsWon = 0
        var showdownsSeen = 0, showdownsWon = 0
        // Stored under the original key so existing statistics survive.
        var biggestPot = 0
        var bestHandCategoryRaw = -1
        // Likewise the original key: an old payload still decodes, and its text
        // becomes `legacyBestHandName`.
        var bestHandName = ""
        var bestHandScore: UInt32 = 0
        var currentStreak = 0, bestStreak = 0
    }

    private init() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return }
        gamesPlayed = payload.gamesPlayed
        gamesWon = payload.gamesWon
        handsPlayed = payload.handsPlayed
        handsWon = payload.handsWon
        showdownsSeen = payload.showdownsSeen
        showdownsWon = payload.showdownsWon
        biggestWin = payload.biggestPot
        bestHandCategoryRaw = payload.bestHandCategoryRaw
        bestHandScore = payload.bestHandScore
        legacyBestHandName = payload.bestHandName
        currentStreak = payload.currentStreak
        bestStreak = payload.bestStreak
    }

    // MARK: Recording

    /// - Parameter profit: chips won *net* of what the hand cost to play.
    func recordHand(humanWon: Bool, profit: Int, wentToShowdown: Bool, humanSawShowdown: Bool) {
        handsPlayed += 1
        if humanWon {
            handsWon += 1
            currentStreak += 1
            bestStreak = max(bestStreak, currentStreak)
            // A split pot can hand back less than it cost; that is not a gain,
            // so `biggestWin` can only ever move up.
            biggestWin = max(biggestWin, profit)
        } else {
            currentStreak = 0
        }
        if humanSawShowdown {
            showdownsSeen += 1
            if humanWon { showdownsWon += 1 }
        }
        save()
    }

    func recordHumanHand(_ value: HandValue) {
        // Still compared by category rather than by score, so an existing record
        // is not displaced by a weaker hand of the same kind — and so a legacy
        // record, which has no score to compare against, survives until it is
        // genuinely beaten.
        if value.category.rawValue > bestHandCategoryRaw {
            bestHandCategoryRaw = value.category.rawValue
            bestHandScore = value.score
            legacyBestHandName = ""
            save()
        }
    }

    func recordGame(won: Bool) {
        gamesPlayed += 1
        if won { gamesWon += 1 }
        save()
    }

    func reset() {
        gamesPlayed = 0; gamesWon = 0
        handsPlayed = 0; handsWon = 0
        showdownsSeen = 0; showdownsWon = 0
        biggestWin = 0
        bestHandCategoryRaw = -1
        bestHandScore = 0
        legacyBestHandName = ""
        currentStreak = 0; bestStreak = 0
        save()
    }

    private func save() {
        let payload = Payload(
            gamesPlayed: gamesPlayed, gamesWon: gamesWon,
            handsPlayed: handsPlayed, handsWon: handsWon,
            showdownsSeen: showdownsSeen, showdownsWon: showdownsWon,
            biggestPot: biggestWin,
            bestHandCategoryRaw: bestHandCategoryRaw,
            bestHandName: legacyBestHandName,
            bestHandScore: bestHandScore,
            currentStreak: currentStreak, bestStreak: bestStreak)
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

// MARK: - Screenshot support

#if DEBUG
extension StatsStore {
    /// Believable statistics for the App Store screenshots (`-shot 07-stats`).
    ///
    /// Assigns the stored properties directly instead of replaying hands, so
    /// nothing is written to `UserDefaults` and a real device's history cannot be
    /// overwritten by taking a picture of it. `private(set)` reaches across the
    /// file, which is why this extension lives here rather than beside the rest
    /// of the shot catalogue.
    func injectDemoValues() {
        gamesPlayed = 34
        gamesWon = 11
        handsPlayed = 1286
        handsWon = 402
        showdownsSeen = 219
        showdownsWon = 128
        biggestWin = 6480
        currentStreak = 3
        bestStreak = 9
        // Taken from a real hand so the name declines correctly in Czech.
        let hand = HandEvaluator.evaluate([
            Card(rank: .king, suit: .diamonds), Card(rank: .king, suit: .spades),
            Card(rank: .king, suit: .clubs), Card(rank: .nine, suit: .hearts),
            Card(rank: .nine, suit: .spades), Card(rank: .four, suit: .diamonds),
            Card(rank: .two, suit: .clubs),
        ])
        bestHandCategoryRaw = hand.category.rawValue
        // The score, not the sentence — `bestHandName` is derived from it, which
        // is what lets the Czech and English screenshots of this screen both
        // name the same hand correctly.
        bestHandScore = hand.score
    }
}
#endif
