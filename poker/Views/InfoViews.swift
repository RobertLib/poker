import SwiftUI

// MARK: - Shared sheet chrome

private struct SheetContainer<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    content
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                    .accessibilityLabel(Text("a11y.closeSheet"))
                }
            }
            .toolbarBackground(Theme.backgroundTop, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}

private func sectionCard(@ViewBuilder content: () -> some View) -> some View {
    content()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)))
}

// MARK: - Rules & hand rankings

struct RulesView: View {
    var body: some View {
        SheetContainer(title: "rules.title") {
            VStack(spacing: 18) {
                sectionCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("rules.intro.title")
                            .font(.system(.caption, design: .rounded, weight: .heavy))
                            .kerning(1.5)
                            .foregroundStyle(Theme.gold)
                        Text("rules.intro")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Theme.cream.opacity(0.9))
                            .lineSpacing(3)
                    }
                }

                sectionCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("rules.moves.title")
                            .font(.system(.caption, design: .rounded, weight: .heavy))
                            .kerning(1.5)
                            .foregroundStyle(Theme.gold)
                        moveRow("action.fold", "rules.move.fold")
                        moveRow("action.check", "rules.move.check")
                        moveRow("action.callPlain", "rules.move.call")
                        moveRow("rules.move.betRaise.title", "rules.move.betRaise")
                        moveRow("action.allIn", "rules.move.allIn")
                    }
                }

                sectionCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("rules.rankings.title")
                            .font(.system(.caption, design: .rounded, weight: .heavy))
                            .kerning(1.5)
                            .foregroundStyle(Theme.gold)
                        ForEach(Array(Self.rankings.enumerated()), id: \.offset) { _, ranking in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(ranking.name)
                                        .font(.system(.footnote, design: .rounded, weight: .bold))
                                        .foregroundStyle(Theme.cream)
                                    Text(ranking.blurb)
                                        .font(.system(.caption2, design: .rounded, weight: .medium))
                                        .foregroundStyle(Theme.subtleText)
                                }
                                .frame(minWidth: 100, idealWidth: 118, maxWidth: 150, alignment: .leading)
                                Spacer(minLength: 0)
                                HStack(spacing: 3) {
                                    ForEach(ranking.cards, id: \.id) { card in
                                        CardFaceView(card: card, width: 30)
                                            .accessibilityHidden(true)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func moveRow(_ name: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(name)
                .font(.system(.footnote, design: .rounded, weight: .heavy))
                .foregroundStyle(Theme.goldBright)
                .frame(width: 84, alignment: .leading)
            Text(text)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.cream.opacity(0.85))
        }
    }

    private static func c(_ rank: Rank, _ suit: Suit) -> Card { Card(rank: rank, suit: suit) }

    static let rankings: [(name: LocalizedStringKey, blurb: LocalizedStringKey, cards: [Card])] = [
        ("hand.royalFlush", "rules.royalFlush.blurb",
         [c(.ace, .spades), c(.king, .spades), c(.queen, .spades), c(.jack, .spades), c(.ten, .spades)]),
        ("hand.straightFlush", "rules.straightFlush.blurb",
         [c(.nine, .hearts), c(.eight, .hearts), c(.seven, .hearts), c(.six, .hearts), c(.five, .hearts)]),
        ("hand.fourOfAKind", "rules.fourOfAKind.blurb",
         [c(.queen, .spades), c(.queen, .hearts), c(.queen, .diamonds), c(.queen, .clubs), c(.seven, .hearts)]),
        ("hand.fullHouse", "rules.fullHouse.blurb",
         [c(.jack, .clubs), c(.jack, .hearts), c(.jack, .spades), c(.nine, .diamonds), c(.nine, .clubs)]),
        ("hand.flush", "rules.flush.blurb",
         [c(.ace, .diamonds), c(.jack, .diamonds), c(.eight, .diamonds), c(.six, .diamonds), c(.two, .diamonds)]),
        ("hand.straight", "rules.straight.blurb",
         [c(.ten, .clubs), c(.nine, .hearts), c(.eight, .spades), c(.seven, .diamonds), c(.six, .clubs)]),
        ("hand.threeOfAKind", "rules.threeOfAKind.blurb",
         [c(.eight, .spades), c(.eight, .diamonds), c(.eight, .hearts), c(.king, .clubs), c(.four, .spades)]),
        ("hand.twoPair", "rules.twoPair.blurb",
         [c(.ace, .clubs), c(.ace, .hearts), c(.nine, .spades), c(.nine, .diamonds), c(.five, .hearts)]),
        ("hand.pair", "rules.pair.blurb",
         [c(.ten, .hearts), c(.ten, .spades), c(.ace, .diamonds), c(.seven, .clubs), c(.three, .hearts)]),
        ("hand.highCard", "rules.highCard.blurb",
         [c(.ace, .spades), c(.queen, .diamonds), c(.nine, .clubs), c(.six, .hearts), c(.three, .spades)]),
    ]
}

// MARK: - Statistics

struct StatsView: View {
    @State private var stats = StatsStore.shared
    @State private var confirmReset = false

    var body: some View {
        SheetContainer(title: "stats.title") {
            VStack(spacing: 18) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    statTile("stats.gamesWon", "\(stats.gamesWon) / \(stats.gamesPlayed)", "trophy.fill")
                    statTile("stats.handsWon", "\(stats.handsWon) / \(stats.handsPlayed)", "hand.thumbsup.fill")
                    statTile("stats.winRate", stats.handsPlayed > 0 ? "\(Int((stats.winRate * 100).rounded()))%" : "—", "percent")
                    statTile("stats.biggestWin", stats.biggestWin > 0 ? stats.biggestWin.chipText : "—", "circle.circle.fill")
                    statTile("stats.bestStreak", stats.bestStreak > 0 ? "\(stats.bestStreak)" : "—", "flame.fill")
                    statTile("stats.showdownsWon", "\(stats.showdownsWon) / \(stats.showdownsSeen)", "eye.fill")
                }

                sectionCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("stats.bestHandEver")
                            .font(.system(.caption, design: .rounded, weight: .heavy))
                            .kerning(1.5)
                            .foregroundStyle(Theme.gold)
                        Text(stats.bestHandName.isEmpty
                             ? String(localized: "stats.noBestHand")
                             : stats.bestHandName)
                            .font(.system(.title3, design: .rounded, weight: .black))
                            .foregroundStyle(stats.bestHandName.isEmpty ? Theme.subtleText : Theme.cream)
                    }
                }

                Button("stats.reset", role: .destructive) {
                    confirmReset = true
                }
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .padding(.top, 8)
            }
            .confirmationDialog("stats.reset.confirm", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("stats.reset.confirmAction", role: .destructive) { stats.reset() }
                Button("common.cancel", role: .cancel) {}
            }
        }
    }

    private func statTile(_ label: LocalizedStringKey, _ value: String, _ icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(.body))
                .foregroundStyle(Theme.gold)
            Text(verbatim: value)
                .font(.system(.title2, design: .rounded, weight: .black))
                .foregroundStyle(Theme.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .kerning(0.5)
                .foregroundStyle(Theme.subtleText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)))
    }
}

// MARK: - Settings

struct SettingsView: View {
    @State private var settings = SettingsStore.shared
    /// Grows with the text so a scaled-up symbol never spills out of its slot.
    @ScaledMetric(relativeTo: .subheadline) private var iconWidth: CGFloat = 26

    var body: some View {
        SheetContainer(title: "settings.title") {
            VStack(spacing: 18) {
                sectionCard {
                    VStack(spacing: 14) {
                        toggleRow("settings.sound", "speaker.wave.2.fill", $settings.soundEnabled)
                        Divider().overlay(Color.white.opacity(0.08))
                        toggleRow("settings.haptics", "iphone.radiowaves.left.and.right", $settings.hapticsEnabled)
                        Divider().overlay(Color.white.opacity(0.08))
                        toggleRow("settings.showOdds", "percent", $settings.showOdds)
                        Divider().overlay(Color.white.opacity(0.08))
                        toggleRow("settings.fourColorDeck", "paintpalette.fill", $settings.fourColorDeck)
                    }
                }

                sectionCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("settings.gameSpeed")
                            .font(.system(.caption, design: .rounded, weight: .heavy))
                            .kerning(1.5)
                            .foregroundStyle(Theme.gold)
                        HStack(spacing: 8) {
                            ForEach(GameSpeed.allCases) { speed in
                                selectablePill(speed.displayName, selected: settings.gameSpeed == speed) {
                                    settings.gameSpeed = speed
                                }
                            }
                        }
                    }
                }

                sectionCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("settings.tableFelt")
                            .font(.system(.caption, design: .rounded, weight: .heavy))
                            .kerning(1.5)
                            .foregroundStyle(Theme.gold)
                        HStack(spacing: 12) {
                            ForEach(FeltTheme.allCases) { felt in
                                Button {
                                    settings.feltTheme = felt
                                    Haptics.tap()
                                } label: {
                                    VStack(spacing: 5) {
                                        Circle()
                                            .fill(
                                                RadialGradient(colors: [felt.center, felt.edge],
                                                               center: .center, startRadius: 2, endRadius: 22))
                                            .frame(width: 42, height: 42)
                                            .overlay(
                                                Circle().strokeBorder(
                                                    settings.feltTheme == felt ? Theme.goldBright : Color.white.opacity(0.15),
                                                    lineWidth: settings.feltTheme == felt ? 2.5 : 1))
                                        Text(verbatim: felt.displayName)
                                            .font(.system(.caption2, design: .rounded, weight: .bold))
                                            .foregroundStyle(settings.feltTheme == felt ? Theme.cream : Theme.subtleText)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text(verbatim: felt.displayName))
                                .accessibilityAddTraits(settings.feltTheme == felt ? [.isSelected] : [])
                            }
                        }
                    }
                }
            }
        }
    }

    private func toggleRow(_ label: LocalizedStringKey, _ icon: String, _ binding: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(.subheadline))
                .foregroundStyle(Theme.gold)
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            Text(label)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.cream)
                // The switch beside it carries the same words for VoiceOver, so
                // this copy would only be read a second time.
                .accessibilityHidden(true)
            Spacer()
            // The label goes to the `Toggle` rather than being left empty:
            // `labelsHidden()` takes it off the screen but keeps it for
            // accessibility, and without one the switch announces itself as
            // "on, switch button" with no clue which setting it belongs to.
            Toggle(label, isOn: binding)
                .labelsHidden()
                .tint(Theme.gold)
        }
    }

    private func selectablePill(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            Haptics.tap()
        } label: {
            Text(verbatim: label)
                .font(.system(.footnote, design: .rounded, weight: .bold))
                .foregroundStyle(selected ? Color.black.opacity(0.85) : Theme.cream)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(selected
                                   ? AnyShapeStyle(LinearGradient(colors: [Theme.goldBright, Theme.gold],
                                                                  startPoint: .top, endPoint: .bottom))
                                   : AnyShapeStyle(Color.white.opacity(0.08))))
        }
        .buttonStyle(.plain)
    }
}
