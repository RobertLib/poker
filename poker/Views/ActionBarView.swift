import SwiftUI

// MARK: - Action Bar

struct ActionBarView: View {

    // MARK: Fitted footprint
    //
    // The strip under the felt is not slack: it is exactly what these slide
    // into, and `TableLayoutTests.theBandUnderTheFeltFitsTheControls` checks
    // every screen leaves room for them. They live here so the view and the test
    // cannot drift apart.

    static let rowHeight: CGFloat = 26
    static let buttonHeight: CGFloat = 56
    private static let panelSpacing: CGFloat = 7
    private static let panelPadding: CGFloat = 10
    private static let barSpacing: CGFloat = 8

    /// The buttons, the gap above them and the bar's own bottom padding.
    static let barHeight: CGFloat = buttonHeight + barSpacing + 10
    /// Three rows, the gaps between them, the panel's padding and the gap to the
    /// buttons underneath.
    static let panelHeight: CGFloat = rowHeight * 3 + panelSpacing * 2
        + panelPadding * 2 + barSpacing

    /// How far chrome type may grow. The boxes above are fitted, not elastic:
    /// past this the raise panel reaches up over your hole cards on the shortest
    /// screen the app supports. `GameView` applies it to the chrome as a whole.
    static let maxDynamicTypeSize = DynamicTypeSize.xxLarge

    #if DEBUG
    private static let qaOpensRaisePanel =
        ProcessInfo.processInfo.arguments.contains("-qa-raise")
    #endif

    let game: PokerGame

    /// One metric drives every size in the bar, so the proportions it was fitted
    /// with survive Dynamic Type. 100 → percent of the fitted size.
    @ScaledMetric(relativeTo: .body) private var typeScale: CGFloat = 100

    @State private var showRaisePanel = false
    @State private var raiseTarget: Double = 0
    @State private var isDraggingSlider = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var constraints: ActionConstraints? { game.humanConstraints }
    private var enabled: Bool { game.isAwaitingHuman }

    private func scaled(_ size: CGFloat) -> CGFloat { size * typeScale / 100 }

    var body: some View {
        VStack(spacing: Self.barSpacing) {
            if showRaisePanel, let constraints, enabled {
                raisePanel(constraints)
                    .transition(reduceMotion ? .opacity
                                : .move(edge: .bottom).combined(with: .opacity))
            }

            buttonRow
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .animation(reduceMotion ? .easeInOut(duration: 0.25) : .spring(duration: 0.32),
                   value: showRaisePanel)
        .animation(.easeInOut(duration: 0.2), value: enabled)
        .onChange(of: game.isAwaitingHuman) { _, awaiting in
            if !awaiting {
                showRaisePanel = false
                return
            }
            #if DEBUG
            // `-qa-raise` opens the panel on your turn so it can be
            // photographed. Debug only, and read once rather than on every turn.
            if Self.qaOpensRaisePanel, let constraints, constraints.canRaise,
               constraints.minRaiseTo < constraints.maxRaiseTo {
                raiseTarget = Double(defaultRaise(constraints))
                showRaisePanel = true
            }
            #endif
        }
    }

    // MARK: Buttons

    private var buttonRow: some View {
        HStack(spacing: 10) {
            actionButton(
                title: localized("action.fold"),
                color: Theme.fold,
                filled: false,
                available: enabled) {
                submit(.fold)
            }

            actionButton(
                title: checkCallTitle,
                color: Theme.call,
                filled: true,
                available: enabled) {
                guard let constraints else { return }
                submit(constraints.canCheck ? .check : .call)
            }

            // Always drawn, only ever disabled: letting the button come and go
            // would resize the whole row the moment it becomes your turn.
            actionButton(
                title: raiseButtonTitle,
                color: Theme.raise,
                filled: true,
                available: enabled && (constraints?.canRaise ?? false)) {
                guard let constraints else { return }
                if showRaisePanel {
                    submit(.raise(to: Int(raiseTarget)))
                } else if constraints.minRaiseTo >= constraints.maxRaiseTo {
                    // Nothing to size — the only legal raise is the whole stack.
                    submit(.raise(to: constraints.maxRaiseTo))
                } else {
                    raiseTarget = Double(defaultRaise(constraints))
                    showRaisePanel = true
                    Haptics.tap()
                }
            }
        }
        .frame(height: Self.buttonHeight)
    }

    private var checkCallTitle: String {
        guard let constraints, enabled else { return localized("action.check") }
        if constraints.canCheck { return localized("action.check") }
        if constraints.toCall >= game.players[game.humanSeat].chips {
            return localized("action.callAllIn")
        }
        return String(localized: "action.call \(constraints.toCall.chipText)")
    }

    private var raiseButtonTitle: String {
        guard let constraints, enabled else { return localized("action.raise") }
        let opening = constraints.isOpeningBet
        guard showRaisePanel else {
            // Say what the tap will actually do when shoving is the only option.
            if constraints.canRaise && constraints.minRaiseTo >= constraints.maxRaiseTo {
                return localized("action.allIn")
            }
            return localized(opening ? "action.bet" : "action.raise")
        }

        let amount = Int(raiseTarget)
        if amount >= constraints.maxRaiseTo { return localized("action.allIn") }
        return opening
            ? String(localized: "action.betAmount \(amount.chipText)")
            : String(localized: "action.raiseAmount \(amount.chipText)")
    }

    private func actionButton(title: String, color: Color, filled: Bool,
                              available: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: scaled(17), weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                // Swap the label outright. Without this the enable/disable
                // animation cross-fades "Raise" into "Bet" and both render at once.
                .contentTransition(.identity)
                .animation(nil, value: title)
                .foregroundStyle(filled ? Color.black.opacity(0.85) : color)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if filled {
                        Capsule().fill(
                            LinearGradient(colors: [color.opacity(1), color.opacity(0.75)],
                                           startPoint: .top, endPoint: .bottom))
                    } else {
                        ZStack {
                            Capsule().fill(color.opacity(0.14))
                            Capsule().strokeBorder(color.opacity(0.85), lineWidth: 1.8)
                        }
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .opacity(available ? 1 : 0.35)
        .shadow(color: available && filled ? color.opacity(0.35) : .clear, radius: 8, y: 3)
    }

    // MARK: Raise panel

    /// Deliberately compact: the panel slides up over the felt's lower edge, and
    /// anything taller would cover your hole cards while you size the bet.
    private func raisePanel(_ constraints: ActionConstraints) -> some View {
        let range = Double(constraints.minRaiseTo)...Double(max(constraints.maxRaiseTo, constraints.minRaiseTo + 1))

        return VStack(spacing: Self.panelSpacing) {
            HStack {
                Text(constraints.isOpeningBet ? "raisePanel.bet" : "raisePanel.raiseTo")
                    .font(.system(size: scaled(12), weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.subtleText)
                Spacer()
                Text(Int(raiseTarget).chipText)
                    .font(.system(size: scaled(21), weight: .black, design: .rounded))
                    .foregroundStyle(Theme.goldBright)
                    // Sizing a bet scrubs this figure continuously, so the
                    // rolling digits are the most restless thing on screen.
                    .contentTransition(reduceMotion ? .identity : .numericText(value: raiseTarget))
                    .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: raiseTarget)
                Spacer()
                Button {
                    showRaisePanel = false
                    Haptics.tap()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: scaled(19)))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                .accessibilityLabel(Text("a11y.closeRaisePanel"))
            }
            .frame(height: Self.rowHeight)

            Slider(value: $raiseTarget, in: range, step: sliderStep(constraints)) { editing in
                isDraggingSlider = editing
            }
            .tint(Theme.gold)
            .accessibilityLabel(constraints.isOpeningBet
                                ? Text("raisePanel.bet") : Text("raisePanel.raiseTo"))
            .accessibilityValue(Text(verbatim: Int(raiseTarget).chipText))
            .frame(height: Self.rowHeight)
            .onChange(of: raiseTarget) { _, _ in
                // Detent feedback only while dragging — preset buttons tap themselves.
                if isDraggingSlider { Haptics.tap() }
            }

            HStack(spacing: 8) {
                presetButton("preset.min", value: constraints.minRaiseTo)
                presetButton("preset.halfPot", value: potRaise(fraction: 0.5, constraints))
                presetButton("preset.threeQuarterPot", value: potRaise(fraction: 0.75, constraints))
                presetButton("preset.pot", value: potRaise(fraction: 1.0, constraints))
                presetButton("preset.allIn", value: constraints.maxRaiseTo, danger: true)
            }
            .frame(height: Self.rowHeight)
        }
        .padding(Self.panelPadding)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.09, green: 0.11, blue: 0.17).opacity(0.97))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)))
        .shadow(color: .black.opacity(0.5), radius: 14, y: 5)
    }

    private func presetButton(_ title: LocalizedStringKey, value: Int, danger: Bool = false) -> some View {
        let clamped = clampRaise(value)
        return Button {
            raiseTarget = Double(clamped)
            Haptics.tap()
        } label: {
            Text(title)
                .font(.system(size: scaled(12), weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(danger ? Theme.allInRed : Theme.cream)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    Capsule().fill(Color.white.opacity(Int(raiseTarget) == clamped ? 0.18 : 0.07)))
        }
        .buttonStyle(.plain)
    }

    // MARK: Helpers

    private func sliderStep(_ constraints: ActionConstraints) -> Double {
        let span = constraints.maxRaiseTo - constraints.minRaiseTo
        if span > 4000 { return 25 }
        if span > 800 { return 10 }
        return 5
    }

    private func clampRaise(_ value: Int) -> Int {
        guard let constraints else { return value }
        return min(max(value, constraints.minRaiseTo), constraints.maxRaiseTo)
    }

    /// Standard pot-sized raise: call + fraction of (pot after calling).
    private func potRaise(fraction: Double, _ constraints: ActionConstraints) -> Int {
        let myBet = game.players[game.humanSeat].betThisStreet
        let potAfterCall = game.totalPot + constraints.toCall
        let target = myBet + constraints.toCall + Int(Double(potAfterCall) * fraction)
        let rounded = target >= 100 ? (target / 10) * 10 : (target / 5) * 5
        return clampRaise(rounded)
    }

    private func defaultRaise(_ constraints: ActionConstraints) -> Int {
        constraints.isOpeningBet
            ? clampRaise(potRaise(fraction: 0.66, constraints))
            : clampRaise(potRaise(fraction: 0.75, constraints))
    }

    private func submit(_ action: PlayerAction) {
        Haptics.tap()
        showRaisePanel = false
        game.submitHumanAction(action)
    }
}
