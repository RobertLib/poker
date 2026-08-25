import SwiftUI

// MARK: - Card geometry

private let cardAspect: CGFloat = 1.42

// MARK: - Card Face

struct CardFaceView: View {
    let card: Card
    let width: CGFloat
    var fourColor = false

    private var height: CGFloat { width * cardAspect }
    private var color: Color { card.color(fourColor: fourColor) }
    private var detailed: Bool { width >= 42 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.13)
                .fill(Theme.cardFace)
                .overlay(
                    RoundedRectangle(cornerRadius: width * 0.13)
                        .strokeBorder(Color.black.opacity(0.14), lineWidth: 0.8))

            if detailed {
                cornerIndex
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, width * 0.065)
                    .padding(.top, width * 0.05)
                cornerIndex
                    .rotationEffect(.degrees(180))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, width * 0.065)
                    .padding(.bottom, width * 0.05)
                centerContent
            } else {
                // Mini card: rank over suit, centered.
                VStack(spacing: -width * 0.04) {
                    Text(card.rank.symbol)
                        .font(.system(size: width * 0.52, weight: .bold, design: .rounded))
                    Text(card.suit.symbol)
                        .font(.system(size: width * 0.44))
                }
                .foregroundStyle(color)
            }
        }
        .frame(width: width, height: height)
        .shadow(color: .black.opacity(0.35), radius: width * 0.05, y: width * 0.03)
    }

    private var cornerIndex: some View {
        VStack(spacing: -width * 0.02) {
            Text(card.rank.symbol)
                .font(.system(size: width * 0.21, weight: .bold, design: .rounded))
            Text(card.suit.symbol)
                .font(.system(size: width * 0.17))
        }
        .foregroundStyle(color)
    }

    @ViewBuilder
    private var centerContent: some View {
        let pipArea = CGSize(width: width * 0.60, height: height * 0.68)
        switch card.rank {
        case .ace:
            Text(card.suit.symbol)
                .font(.system(size: width * 0.62))
                .foregroundStyle(color)
        case .jack, .queen, .king:
            courtContent
        default:
            ZStack {
                ForEach(Array(pipLayout(for: card.rank.rawValue).enumerated()), id: \.offset) { _, pip in
                    Text(card.suit.symbol)
                        .font(.system(size: width * 0.185))
                        .rotationEffect(pip.flipped ? .degrees(180) : .zero)
                        .position(x: pipArea.width * pip.x, y: pipArea.height * pip.y)
                }
            }
            .frame(width: pipArea.width, height: pipArea.height)
            .foregroundStyle(color)
        }
    }

    private var courtContent: some View {
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.06)
                .strokeBorder(color.opacity(0.55), lineWidth: 1.2)
                .frame(width: width * 0.56, height: height * 0.60)
            VStack(spacing: height * 0.015) {
                Image(systemName: card.rank == .jack ? "shield.fill" : "crown.fill")
                    .font(.system(size: width * 0.15))
                    .opacity(0.85)
                Text(card.rank.symbol)
                    .font(.system(size: width * 0.34, weight: .semibold, design: .serif))
            }
            .foregroundStyle(color)
            Text(card.suit.symbol)
                .font(.system(size: width * 0.13))
                .foregroundStyle(color)
                .frame(width: width * 0.56, height: height * 0.60, alignment: .topLeading)
                .offset(x: width * 0.04, y: width * 0.03)
            Text(card.suit.symbol)
                .font(.system(size: width * 0.13))
                .rotationEffect(.degrees(180))
                .foregroundStyle(color)
                .frame(width: width * 0.56, height: height * 0.60, alignment: .bottomTrailing)
                .offset(x: -width * 0.04, y: -width * 0.03)
        }
    }

    /// Traditional pip positions in unit space; `flipped` pips point downward.
    private func pipLayout(for rank: Int) -> [(x: CGFloat, y: CGFloat, flipped: Bool)] {
        let l: CGFloat = 0.18, r: CGFloat = 0.82, c: CGFloat = 0.5
        let top: CGFloat = 0.11, bottom: CGFloat = 0.89
        let midTop: CGFloat = 0.37, midBottom: CGFloat = 0.63
        switch rank {
        case 2: return [(c, top, false), (c, bottom, true)]
        case 3: return [(c, top, false), (c, 0.5, false), (c, bottom, true)]
        case 4: return [(l, top, false), (r, top, false), (l, bottom, true), (r, bottom, true)]
        case 5: return [(l, top, false), (r, top, false), (c, 0.5, false),
                        (l, bottom, true), (r, bottom, true)]
        case 6: return [(l, top, false), (r, top, false), (l, 0.5, false), (r, 0.5, false),
                        (l, bottom, true), (r, bottom, true)]
        case 7: return [(l, top, false), (r, top, false), (c, 0.30, false),
                        (l, 0.5, false), (r, 0.5, false),
                        (l, bottom, true), (r, bottom, true)]
        case 8: return [(l, top, false), (r, top, false), (c, 0.30, false),
                        (l, 0.5, false), (r, 0.5, false), (c, 0.70, true),
                        (l, bottom, true), (r, bottom, true)]
        case 9: return [(l, top, false), (r, top, false), (l, midTop, false), (r, midTop, false),
                        (c, 0.5, false),
                        (l, midBottom, true), (r, midBottom, true), (l, bottom, true), (r, bottom, true)]
        case 10: return [(l, top, false), (r, top, false), (c, 0.24, false),
                         (l, midTop, false), (r, midTop, false),
                         (l, midBottom, true), (r, midBottom, true), (c, 0.76, true),
                         (l, bottom, true), (r, bottom, true)]
        default: return []
        }
    }
}

// MARK: - Card Back

struct CardBackView: View {
    let width: CGFloat

    private var height: CGFloat { width * cardAspect }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.13)
                .fill(Theme.cardFace)
            RoundedRectangle(cornerRadius: width * 0.09)
                .fill(
                    LinearGradient(colors: [Theme.cardBack, Theme.cardBackDark],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(width * 0.055)
            latticePattern
                .clipShape(RoundedRectangle(cornerRadius: width * 0.09).inset(by: width * 0.055))
            Circle()
                .strokeBorder(Theme.gold.opacity(0.75), lineWidth: max(width * 0.014, 0.8))
                .frame(width: width * 0.42)
            Text("♠")
                .font(.system(size: width * 0.24))
                .foregroundStyle(Theme.gold.opacity(0.85))
        }
        .frame(width: width, height: height)
        .shadow(color: .black.opacity(0.35), radius: width * 0.05, y: width * 0.03)
    }

    private var latticePattern: some View {
        Canvas { context, size in
            let spacing = max(size.width / 5.5, 6)
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                path.move(to: CGPoint(x: x + size.height, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
            context.stroke(path, with: .color(.white.opacity(0.14)), lineWidth: 1)
        }
        .frame(width: width, height: height)
    }
}

// MARK: - Flip Card (3D turn between back and face)

struct FlipCardView: View {
    let card: Card?
    let faceUp: Bool
    let width: CGFloat
    var fourColor = false

    @State private var showingFace: Bool
    @State private var angle: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(card: Card?, faceUp: Bool, width: CGFloat, fourColor: Bool = false) {
        self.card = card
        self.faceUp = faceUp
        self.width = width
        self.fourColor = fourColor
        _showingFace = State(initialValue: faceUp)
    }

    var body: some View {
        Group {
            if showingFace, let card {
                CardFaceView(card: card, width: width, fourColor: fourColor)
            } else {
                CardBackView(width: width)
            }
        }
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.32)
        .onChange(of: faceUp) { _, newValue in
            guard newValue != showingFace else { return }
            guard !reduceMotion else {
                // Turning a card over is rotation in depth. Reduce Motion gets
                // the same reveal as a cross-fade, over the same 0.32s.
                withAnimation(.easeInOut(duration: 0.32)) { showingFace = newValue }
                return
            }
            // 89.9° instead of 90° — a perfectly edge-on card makes the
            // projection matrix singular and SwiftUI drops the frame.
            withAnimation(.easeIn(duration: 0.16)) {
                angle = 89.9
            } completion: {
                showingFace = newValue
                angle = -89.9
                withAnimation(.easeOut(duration: 0.16)) {
                    angle = 0
                }
            }
        }
    }
}

// MARK: - Fly-in effect (deal from the deck point)

struct DealEffect: ViewModifier {
    let from: CGPoint
    let to: CGPoint
    var delay: Double = 0

    @State private var arrived = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // Reduce Motion keeps the card where it belongs from the first frame, so
        // all that is left of the deal is the fade — no travel, no tilt.
        let settled = arrived || reduceMotion
        return content
            .rotationEffect(settled ? .zero : .degrees(-14))
            .offset(x: settled ? 0 : from.x - to.x, y: settled ? 0 : from.y - to.y)
            .opacity(arrived ? 1 : 0.35)
            .onAppear {
                withAnimation(reduceMotion
                              ? .easeOut(duration: 0.28).delay(delay)
                              : .spring(duration: 0.42, bounce: 0.18).delay(delay)) {
                    arrived = true
                }
            }
    }
}

extension View {
    func dealAnimation(from: CGPoint, to: CGPoint, delay: Double = 0) -> some View {
        modifier(DealEffect(from: from, to: to, delay: delay))
    }
}
