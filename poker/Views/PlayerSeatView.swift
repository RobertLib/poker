import SwiftUI

// MARK: - Opponent seat

struct OpponentSeatView: View {
    let player: Player
    let metrics: SeatMetrics
    let isActive: Bool
    let isWinner: Bool
    let winningCards: Set<Card>
    let deckPoint: CGPoint
    let seatPoint: CGPoint
    var fourColor: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var avatarSize: CGFloat { metrics.avatar }
    private var cardWidth: CGFloat { metrics.cardWidth }
    private var scale: CGFloat { metrics.scale }

    var body: some View {
        VStack(spacing: metrics.spacing) {
            ZStack(alignment: .top) {
                // Hole cards behind/above the avatar
                holeCards
                    .offset(y: -metrics.cardOverhang)

                avatar
            }
            .frame(height: max(avatarSize, metrics.cardHeight))

            infoPlate
        }
        .overlay(alignment: .topTrailing) {
            if player.isAllIn && !player.isEliminated {
                Text("label.allIn")
                    .font(.system(size: 9 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6 * scale)
                    .padding(.vertical, 2.5 * scale)
                    .background(Capsule().fill(Theme.allInRed))
                    .offset(x: 14 * scale, y: -4 * scale)
            }
        }
        .opacity(player.isEliminated ? 0.32 : (player.hasFolded ? 0.5 : 1))
        .animation(.easeInOut(duration: 0.3), value: player.hasFolded)
        .animation(.easeInOut(duration: 0.3), value: player.isEliminated)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: player.name))
        .accessibilityValue(Text(verbatim: seatDescription))
    }

    /// One spoken summary per seat: chips, and whatever state the seat is in.
    private var seatDescription: String {
        if player.isEliminated { return localized("a11y.seat.out") }
        var parts = [player.chips.chipText]
        if player.isAllIn { parts.append(localized("action.allIn")) }
        if player.hasFolded { parts.append(localized("action.fold")) }
        if player.revealedCards, !player.holeCards.isEmpty {
            parts.append(player.holeCards.map(\.spokenName).joined(separator: ", "))
        }
        if let action = player.lastAction { parts.append(action.text) }
        if isActive { parts.append(localized("a11y.seat.thinking")) }
        return parts.joined(separator: ", ")
    }

    private var holeCards: some View {
        HStack(spacing: -cardWidth * 0.45) {
            ForEach(Array(player.holeCards.enumerated()), id: \.element.id) { index, card in
                FlipCardView(card: card,
                             faceUp: player.revealedCards,
                             width: cardWidth,
                             fourColor: fourColor)
                    .rotationEffect(.degrees(index == 0 ? -7 : 7))
                    .overlay {
                        if isWinner && player.revealedCards && !winningCards.contains(card) {
                            RoundedRectangle(cornerRadius: cardWidth * 0.13)
                                .fill(Color.black.opacity(0.45))
                        }
                    }
                    .overlay {
                        if player.revealedCards && winningCards.contains(card) {
                            RoundedRectangle(cornerRadius: cardWidth * 0.13)
                                .strokeBorder(Theme.goldBright, lineWidth: 2)
                                .shadow(color: Theme.goldBright, radius: 5)
                        }
                    }
                    .dealAnimation(from: deckPoint, to: seatPoint)
            }
        }
        // Folded and busted players have no live hand, so show no cards —
        // otherwise a knocked-out seat keeps a pair of ghost cards under "OUT".
        .opacity(player.hasFolded || player.isEliminated ? 0 : 1)
        .animation(.easeOut(duration: 0.35), value: player.hasFolded)
        .animation(.easeOut(duration: 0.35), value: player.isEliminated)
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(colors: [Color(white: 0.22), Color(white: 0.12)],
                                   startPoint: .top, endPoint: .bottom))
            Text(player.emoji)
                .font(.system(size: avatarSize * 0.56))
                .saturation(player.isEliminated ? 0 : 1)

            if isActive {
                Circle()
                    .strokeBorder(Theme.goldBright, lineWidth: 2.5)
                    .shadow(color: Theme.goldBright.opacity(0.8), radius: 6)
                ThinkingDots(scale: scale)
                    .offset(y: avatarSize * 0.30)
            } else {
                Circle()
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 1.5)
            }

            if player.isEliminated {
                Text("label.out")
                    .font(.system(size: 13 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .rotationEffect(.degrees(-16))
            }

            if isWinner {
                Circle()
                    .strokeBorder(Theme.goldBright, lineWidth: 3)
                    .shadow(color: Theme.goldBright, radius: 8)
            }
        }
        .frame(width: avatarSize, height: avatarSize)
    }

    private var infoPlate: some View {
        VStack(spacing: 0) {
            Text(verbatim: player.name)
                .font(.system(size: 11 * scale, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.cream)
            Text(player.isEliminated ? "—" : player.chips.chipText)
                .font(.system(size: 12 * scale, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.goldBright)
                // The digits roll vertically, so Reduce Motion just gets the
                // new number. The opacity fades either side of this stay: a
                // cross-fade is what the setting asks for in place of movement.
                .contentTransition(reduceMotion ? .identity : .numericText(value: Double(player.chips)))
                .animation(reduceMotion ? nil : .spring(duration: 0.5), value: player.chips)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 9 * scale)
        // Fixed height so TableLayout's block-height model matches what is drawn.
        .frame(height: metrics.plateHeight)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.55))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)))
    }
}

// MARK: - Action bubble

struct ActionBubble: View {
    let label: ActionLabel
    var scale: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(verbatim: label.text)
            .font(.system(size: 11 * scale, weight: .bold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(label.isAggressive ? Color.black.opacity(0.85) : Theme.cream)
            .padding(.horizontal, 8 * scale)
            .frame(maxHeight: .infinity)
            .background(Capsule().fill(bubbleColor))
            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.5).combined(with: .opacity))
    }

    private var bubbleColor: Color {
        switch label {
        case .fold: return Color(white: 0.3)
        case .check, .call: return Theme.call
        case .bet, .raise: return Theme.raise
        case .allIn: return Theme.allInRed
        case .smallBlind, .bigBlind: return Color(white: 0.25)
        }
    }
}

// MARK: - Dealer button

struct DealerButtonView: View {
    var scale: CGFloat = 1
    /// A *dead* button: it sits on a knocked-out seat this hand, so it is drawn
    /// faded — still readable as position, clearly not a player.
    var isDead = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(colors: isDead
                                   ? [Color(white: 0.62), Color(white: 0.48)]
                                   : [.white, Color(white: 0.82)],
                                   startPoint: .top, endPoint: .bottom))
            Text(verbatim: "D")
                .font(.system(size: 10 * scale, weight: .black, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.75))
        }
        .frame(width: 17 * scale, height: 17 * scale)
        .opacity(isDead ? 0.55 : 1)
        .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
    }
}

// MARK: - Thinking indicator

struct ThinkingDots: View {
    var scale: CGFloat = 1

    @State private var phase = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 3 * scale) {
            ForEach(0..<3, id: \.self) { i in
                // Reduce Motion holds all three lit rather than cycling: the
                // dots are only there to say the seat is deciding, and the gold
                // ring around the avatar says it too.
                Circle()
                    .fill(Theme.cream.opacity(reduceMotion ? 0.85 : (phase == i ? 1 : 0.3)))
                    .frame(width: 4 * scale, height: 4 * scale)
            }
        }
        .padding(.horizontal, 6 * scale)
        .padding(.vertical, 4 * scale)
        .background(Capsule().fill(Color.black.opacity(0.5)))
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(280))
                withAnimation(.easeInOut(duration: 0.2)) {
                    phase = (phase + 1) % 3
                }
            }
        }
    }
}
