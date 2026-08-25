import SwiftUI

// MARK: - Root navigation

struct RootView: View {
    enum Screen {
        case menu
        case setup
        case game
    }

    @State private var screen: Screen = .menu
    @State private var session: GameSession?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Screens slide and scale into each other. Reduce Motion swaps that for a
    /// cross-fade of the same length, here and in the transitions below.
    private func screenChange(_ duration: Double) -> Animation {
        reduceMotion ? .easeInOut(duration: duration) : .spring(duration: duration)
    }

    private func resumeSavedGame() {
        guard let saved = SavedGameStore.shared.saved, let config = saved.config else { return }
        session = GameSession(config: config, restoring: saved)
        withAnimation(screenChange(0.5)) { screen = .game }
    }

    /// Debug only, all of it. Launch arguments cannot reach a shipped app, so
    /// the QA table rigs have no business being in the binary that ships — the
    /// same reason the `-shot` poses are gated.
    private func handleLaunchArguments() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        // App Store screenshots and previews (`-shot <name>`).
        if let scene = Shots.requested {
            Shots.clearReadyMarker()
            Shots.applySettings()
            Shots.applyStores()
            switch scene {
            case .table(let pose):
                // A posed hand reports its own readiness once it reaches the
                // street being photographed.
                session = Shots.makeSession(pose)
                screen = .game
            case .setup:
                screen = .setup
                Shots.markReady()
            case .menu, .rules, .stats, .settings:
                screen = .menu
                // The sheets open from MenuView's own onAppear, so this waits
                // for the presentation as well as for the menu animation.
                Shots.markReady(after: 2.2)
            }
            return
        }
        // Every argument that describes a table implies dealing one, so
        // `-qa-full` on its own works the way the README's table reads rather
        // than silently needing `-qa-game` alongside it.
        let tableArguments = ["-qa-game", "-qa-stacked", "-qa-headsup", "-qa-full",
                              "-qa-autopilot", "-qa-raise"]
        if tableArguments.contains(where: arguments.contains) {
            var config = GameConfig.default
            if arguments.contains("-qa-stacked") {
                config = GameConfig(
                    opponents: Array(AIProfile.roster.prefix(2)),
                    startingChips: 150,
                    difficulty: .easy,
                    blindSpeed: .turbo,
                    humanStartingChips: 3000)
            } else if arguments.contains("-qa-headsup") {
                config.opponents = Array(AIProfile.roster.prefix(1))
            } else if arguments.contains("-qa-full") {
                config.opponents = Array(AIProfile.roster.prefix(5))
            }
            session = GameSession(config: config)
            screen = .game
        } else if arguments.contains("-qa-setup") {
            screen = .setup
        }
        #endif
    }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            switch screen {
            case .menu:
                MenuView(
                    onPlay: { withAnimation(screenChange(0.45)) { screen = .setup } },
                    onContinue: resumeSavedGame)
                    .transition(.opacity)

            case .setup:
                GameSetupView(
                    onStart: { config in
                        session = GameSession(config: config)
                        withAnimation(screenChange(0.5)) { screen = .game }
                    },
                    onBack: { withAnimation(screenChange(0.45)) { screen = .menu } })
                    .transition(reduceMotion ? .opacity
                                : .move(edge: .trailing).combined(with: .opacity))

            case .game:
                if let session {
                    GameView(session: session) {
                        withAnimation(screenChange(0.5)) {
                            screen = .menu
                        }
                        self.session = nil
                    }
                    .transition(reduceMotion ? .opacity
                                : .opacity.combined(with: .scale(scale: 1.04)))
                }
            }
        }
        .onAppear(perform: handleLaunchArguments)
    }
}

// MARK: - Main menu

struct MenuView: View {
    let onPlay: () -> Void
    let onContinue: () -> Void

    @State private var savedGames = SavedGameStore.shared
    @State private var showSettings = false
    @State private var showStats = false
    @State private var showRules = false
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Reduce Motion keeps the entrance as a plain fade: no rise, no scale.
    private var entranceOffset: CGFloat { reduceMotion ? 0 : 16 }

    var body: some View {
        ZStack {
            FloatingSuitsBackground()

            VStack(spacing: 0) {
                Spacer()

                // Title block
                VStack(spacing: 10) {
                    ZStack {
                        CardFaceView(card: Card(rank: .ace, suit: .spades), width: 74)
                            .rotationEffect(.degrees(-12))
                            .offset(x: -26)
                        CardFaceView(card: Card(rank: .ace, suit: .hearts), width: 74)
                            .rotationEffect(.degrees(10))
                            .offset(x: 26, y: 3)
                    }
                    .padding(.bottom, 16)
                    .scaleEffect(reduceMotion ? 1 : (appeared ? 1 : 0.7))
                    .opacity(appeared ? 1 : 0)
                    .accessibilityHidden(true)

                    Text(verbatim: "ACE HIGH")
                        .font(.system(size: 52, weight: .black, design: .serif))
                        .kerning(4)
                        .foregroundStyle(
                            LinearGradient(colors: [Theme.goldBright, Theme.gold, Theme.goldDark],
                                           startPoint: .top, endPoint: .bottom))
                        .shadow(color: Theme.gold.opacity(0.35), radius: 16, y: 4)

                    Text("menu.subtitle")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .kerning(5)
                        .foregroundStyle(Theme.subtleText)
                }
                .offset(y: appeared ? 0 : entranceOffset)
                .opacity(appeared ? 1 : 0)

                Spacer()

                // Buttons
                VStack(spacing: 12) {
                    if let saved = savedGames.saved {
                        Button(String(localized: "menu.continue \(saved.humanChips.chipText)")) {
                            Haptics.chips()
                            onContinue()
                        }
                        .buttonStyle(GoldButtonStyle())

                        Button("menu.newGame") { Haptics.tap(); onPlay() }
                            .buttonStyle(GoldButtonStyle(prominent: false))
                    } else {
                        Button("menu.play") { Haptics.tap(); onPlay() }
                            .buttonStyle(GoldButtonStyle())
                    }

                    Button("menu.statistics") { Haptics.tap(); showStats = true }
                        .buttonStyle(GoldButtonStyle(prominent: false))

                    Button("menu.howToPlay") { Haptics.tap(); showRules = true }
                        .buttonStyle(GoldButtonStyle(prominent: false))

                    Button("menu.settings") { Haptics.tap(); showSettings = true }
                        .buttonStyle(GoldButtonStyle(prominent: false))
                }
                .frame(maxWidth: 320)
                .padding(.horizontal, 34)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : entranceOffset * 1.5)

                Spacer()

                Text("menu.footer")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(Theme.subtleText.opacity(0.7))
                    .padding(.bottom, 18)
            }
        }
        .onAppear {
            // Everything on this screen is a button, and the first one tapped
            // is the app's first haptic of the launch. See `Haptics.prepare()`.
            Haptics.prepare()
            withAnimation(reduceMotion
                          ? .easeOut(duration: 0.5).delay(0.1)
                          : .spring(duration: 0.8, bounce: 0.25).delay(0.1)) {
                appeared = true
            }
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-qa-rules") { showRules = true }
            if arguments.contains("-qa-stats") { showStats = true }
            if arguments.contains("-qa-settings") { showSettings = true }
            switch Shots.requested {
            case .rules: showRules = true
            case .stats: showStats = true
            case .settings: showSettings = true
            default: break
            }
            #endif
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showStats) { StatsView() }
        .sheet(isPresented: $showRules) { RulesView() }
    }
}

// MARK: - Floating suit symbols background

struct FloatingSuitsBackground: View {
    private struct Item: Identifiable {
        let id: Int
        let symbol: String
        let x: CGFloat
        let size: CGFloat
        let duration: Double
        let delay: Double
    }

    private let items: [Item] = {
        let symbols = ["♠", "♥", "♦", "♣"]
        return (0..<10).map { i in
            Item(id: i,
                 symbol: symbols[i % 4],
                 x: CGFloat([0.08, 0.85, 0.25, 0.65, 0.92, 0.15, 0.5, 0.78, 0.35, 0.6][i]),
                 size: CGFloat([44, 60, 32, 52, 38, 66, 30, 46, 58, 36][i]),
                 duration: Double([26, 34, 22, 30, 25, 38, 21, 28, 33, 24][i]),
                 delay: Double(i) * -3.4)
        }
    }()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            if reduceMotion {
                // No clock at all: the suits sit scattered where they are, so
                // the menu keeps its texture without anything drifting across
                // it for as long as the app is open.
                suits(in: geo.size, at: nil)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    suits(in: geo.size, at: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// `now` nil = a fixed, evenly spread standstill instead of a drift.
    private func suits(in size: CGSize, at now: Double?) -> some View {
        ZStack {
            ForEach(items) { item in
                let progress = progress(of: item, at: now)
                Text(item.symbol)
                    .font(.system(size: item.size))
                    .foregroundStyle(Color.white.opacity(0.035))
                    .position(
                        x: item.x * size.width + sin(progress * 2 * .pi) * 20,
                        y: size.height * (1.15 - progress * 1.3))
            }
        }
    }

    private func progress(of item: Item, at now: Double?) -> Double {
        guard let now else {
            // Spread over the drift's visible band rather than its full cycle,
            // which runs the symbols off both edges.
            return 0.15 + 0.7 * Double(item.id) / Double(max(items.count - 1, 1))
        }
        return ((now + item.delay) / item.duration).truncatingRemainder(dividingBy: 1)
    }
}

// MARK: - Game setup

struct GameSetupView: View {
    let onStart: (GameConfig) -> Void
    let onBack: () -> Void

    @State private var settings = SettingsStore.shared
    @State private var opponentCount: Int
    @State private var startingChips: Int
    @State private var difficulty: Difficulty
    @State private var blindSpeed: BlindSpeed
    /// Line-up for this game, shuffled once so the preview matches who you'll face.
    @State private var lineup: [AIProfile]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(onStart: @escaping (GameConfig) -> Void, onBack: @escaping () -> Void) {
        self.onStart = onStart
        self.onBack = onBack
        let saved = SettingsStore.shared
        _opponentCount = State(initialValue: saved.lastOpponentCount)
        _startingChips = State(initialValue: saved.lastStartingChips)
        _difficulty = State(initialValue: saved.lastDifficulty)
        _blindSpeed = State(initialValue: saved.lastBlindSpeed)
        #if DEBUG
        // A shuffled line-up would put different faces in the Czech and English
        // screenshots of the same screen.
        _lineup = State(initialValue: Shots.requestedName == nil
                        ? AIProfile.roster.shuffled()
                        : AIProfile.roster)
        #else
        _lineup = State(initialValue: AIProfile.roster.shuffled())
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    Haptics.tap()
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.cream)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .accessibilityLabel(Text("a11y.back"))
                Spacer()
                Text("setup.title")
                    .font(.system(.headline, design: .rounded, weight: .black))
                    .kerning(2)
                    .foregroundStyle(Theme.cream)
                Spacer()
                Color.clear.frame(width: 38, height: 38)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            ScrollView {
                VStack(spacing: 22) {
                    // Opponents
                    setupSection("setup.opponents") {
                        VStack(spacing: 12) {
                            HStack(spacing: 10) {
                                ForEach(1...5, id: \.self) { count in
                                    Button {
                                        opponentCount = count
                                        Haptics.tap()
                                    } label: {
                                        Text("\(count)")
                                            .font(.system(.title3, design: .rounded, weight: .heavy))
                                            .foregroundStyle(opponentCount == count ? Color.black.opacity(0.85) : Theme.cream)
                                            .frame(width: 46, height: 46)
                                            .background(
                                                Circle().fill(opponentCount == count
                                                              ? AnyShapeStyle(LinearGradient(
                                                                    colors: [Theme.goldBright, Theme.gold],
                                                                    startPoint: .top, endPoint: .bottom))
                                                              : AnyShapeStyle(Color.white.opacity(0.08))))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(Text("a11y.opponentCount \(count)"))
                                    .accessibilityAddTraits(opponentCount == count ? [.isSelected] : [])
                                }
                            }

                            HStack(spacing: 14) {
                                ForEach(lineup.prefix(opponentCount)) { profile in
                                    VStack(spacing: 3) {
                                        Text(profile.emoji)
                                            .font(.system(size: 30))
                                        Text(verbatim: profile.name)
                                            .font(.system(.caption, design: .rounded, weight: .bold))
                                            .foregroundStyle(Theme.cream)
                                        Text(verbatim: profile.tagline)
                                            .font(.system(.caption2, design: .rounded, weight: .medium))
                                            .foregroundStyle(Theme.subtleText)
                                            .multilineTextAlignment(.center)
                                            // Two lines with the space reserved: Czech
                                            // taglines run longer than the English ones,
                                            // and the row must not jump as it changes.
                                            .lineLimit(2, reservesSpace: true)
                                            .minimumScaleFactor(0.75)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .accessibilityElement(children: .combine)
                                }
                            }
                            .animation(reduceMotion ? nil : .spring(duration: 0.3),
                                       value: opponentCount)
                        }
                    }

                    // Difficulty
                    setupSection("setup.difficulty") {
                        segmented(Difficulty.allCases, selection: $difficulty) { $0.displayName }
                    }

                    // Starting stack
                    setupSection("setup.startingChips") {
                        segmented([500, 1000, 2500, 5000], selection: $startingChips) { $0.chipText }
                    }

                    // Blind speed
                    setupSection("setup.blindsIncrease") {
                        segmented(BlindSpeed.allCases, selection: $blindSpeed) { $0.displayName }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 130)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button("setup.dealMeIn") {
                Haptics.chips()
                settings.lastOpponentCount = opponentCount
                settings.lastStartingChips = startingChips
                settings.lastDifficulty = difficulty
                settings.lastBlindSpeed = blindSpeed
                let config = GameConfig(
                    opponents: Array(lineup.prefix(opponentCount)),
                    startingChips: startingChips,
                    difficulty: difficulty,
                    blindSpeed: blindSpeed)
                SavedGameStore.shared.clear()
                onStart(config)
            }
            .buttonStyle(GoldButtonStyle())
            .frame(maxWidth: 340)
            .padding(.horizontal, 30)
            .padding(.bottom, 12)
            .padding(.top, 8)
            .background(
                LinearGradient(colors: [Theme.backgroundBottom.opacity(0), Theme.backgroundBottom],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea())
        }
    }

    private func setupSection(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .heavy))
                .kerning(1.5)
                .foregroundStyle(Theme.gold)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)))
    }

    private func segmented<T: Hashable>(_ options: [T], selection: Binding<T>,
                                        label: @escaping (T) -> String) -> some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                Button {
                    selection.wrappedValue = option
                    Haptics.tap()
                } label: {
                    Text(verbatim: label(option))
                        .font(.system(.footnote, design: .rounded, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(selection.wrappedValue == option ? Color.black.opacity(0.85) : Theme.cream)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            Capsule().fill(selection.wrappedValue == option
                                           ? AnyShapeStyle(LinearGradient(
                                                colors: [Theme.goldBright, Theme.gold],
                                                startPoint: .top, endPoint: .bottom))
                                           : AnyShapeStyle(Color.white.opacity(0.08))))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection.wrappedValue == option ? [.isSelected] : [])
            }
        }
    }
}
