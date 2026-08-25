import SwiftUI

// MARK: - Single chip

struct ChipView: View {
    let amount: Int
    var size: CGFloat = 26

    var body: some View {
        let colors = Theme.chipColor(for: amount)
        ZStack {
            Circle()
                .fill(colors.main)
            Circle()
                .strokeBorder(colors.accent.opacity(0.9),
                              style: StrokeStyle(lineWidth: size * 0.09, dash: [size * 0.18, size * 0.16]))
                .padding(size * 0.045)
            Circle()
                .strokeBorder(colors.accent.opacity(0.55), lineWidth: size * 0.035)
                .padding(size * 0.24)
            Circle()
                .fill(
                    RadialGradient(colors: [.white.opacity(0.22), .clear],
                                   center: .init(x: 0.35, y: 0.3),
                                   startRadius: 0, endRadius: size * 0.5))
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.4), radius: size * 0.08, y: size * 0.06)
    }
}

// MARK: - Bet stack (chips + amount label)

struct BetStackView: View {
    let amount: Int
    var scale: CGFloat = 1

    private var chipSize: CGFloat { 20 * scale }

    private var chipCount: Int {
        switch amount {
        case ..<30: return 1
        case ..<100: return 2
        case ..<400: return 3
        default: return 4
        }
    }

    var body: some View {
        HStack(spacing: 3 * scale) {
            ZStack {
                ForEach(0..<chipCount, id: \.self) { i in
                    ChipView(amount: amount / chipCount, size: chipSize)
                        .offset(y: -CGFloat(i) * chipSize * 0.16)
                }
            }
            Text(amount.chipText)
                .font(.system(size: chipSize * 0.56, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(Theme.cream)
                .padding(.horizontal, 4.5 * scale)
                .padding(.vertical, 2 * scale)
                .background(Capsule().fill(Color.black.opacity(0.45)))
        }
        // Matches TableLayout.betStackSize: the placement search relies on this
        // being the real footprint, not an intrinsic size that might exceed it.
        .frame(width: 62 * scale, height: 30 * scale)
    }
}

// MARK: - Pot display

struct PotView: View {
    let amount: Int
    var scale: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 3 * scale) {
            if amount > 0 {
                HStack(spacing: -7 * scale) {
                    ForEach(0..<min(3 + amount / 300, 6), id: \.self) { i in
                        ChipView(amount: max(amount / 3, 1), size: 21 * scale)
                            .offset(y: i % 2 == 0 ? 0 : -3 * scale)
                    }
                }
                Text("table.pot \(amount.chipText)")
                    .font(.system(size: 14 * scale, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(Theme.goldBright)
                    // A rolling odometer is motion; Reduce Motion gets the new
                    // figure outright.
                    .contentTransition(reduceMotion ? .identity : .numericText(value: Double(amount)))
                    .padding(.horizontal, 12 * scale)
                    .padding(.vertical, 4 * scale)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.4))
                            .overlay(Capsule().strokeBorder(Theme.gold.opacity(0.4), lineWidth: 1)))
            }
        }
        .frame(width: 132 * scale, height: 52 * scale)
        .animation(reduceMotion ? nil : .spring(duration: 0.45), value: amount)
    }
}

// MARK: - Chip flight (animated transfer)

struct ChipFlightView: View {
    let from: CGPoint
    let to: CGPoint
    let amount: Int
    var scale: CGFloat = 1
    let onFinished: () -> Void

    @State private var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                ChipView(amount: amount, size: 20 * scale)
                    .offset(x: CGFloat(i - 1) * 7 * scale, y: CGFloat(i % 2) * -5 * scale)
            }
        }
        // The flight says where the chips went, which is worth keeping — so
        // Reduce Motion still shows them, at the destination, and lets them fade
        // rather than sending them across the table.
        .position(x: reduceMotion ? to.x : from.x + (to.x - from.x) * progress,
                  y: reduceMotion ? to.y : from.y + (to.y - from.y) * progress)
        .opacity(progress < 0.94 ? 1 : 0)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5)) {
                progress = 1
            } completion: {
                onFinished()
            }
        }
    }
}
