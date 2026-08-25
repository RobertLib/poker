import SwiftUI

// MARK: - Confetti

struct ConfettiView: View {
    /// Incrementing this triggers a new burst.
    let burst: Int

    @State private var particles: [Particle] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Particle: Identifiable {
        let id = UUID()
        let x: CGFloat            // 0–1 horizontal start
        let hue: Double
        let size: CGFloat
        let spin: Double
        let fallDuration: Double
        let drift: CGFloat
        let shape: Int
        let startedAt: Date
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(paused: particles.isEmpty)) { timeline in
                Canvas { context, size in
                    let now = timeline.date
                    for particle in particles {
                        let t = now.timeIntervalSince(particle.startedAt) / particle.fallDuration
                        guard t >= 0, t <= 1 else { continue }
                        let eased = t * t * 0.6 + t * 0.4
                        let y = -40 + eased * (size.height + 90)
                        let x = particle.x * size.width + sin(t * 6 + particle.spin) * particle.drift
                        let opacity = t > 0.8 ? (1 - t) / 0.2 : 1

                        var item = context
                        item.opacity = opacity
                        item.translateBy(x: x, y: y)
                        item.rotate(by: .radians(particle.spin + t * 9))

                        let rect = CGRect(x: -particle.size / 2, y: -particle.size / 2,
                                          width: particle.size, height: particle.size * (particle.shape == 0 ? 0.55 : 1))
                        let color = Color(hue: particle.hue, saturation: 0.75, brightness: 0.95)
                        if particle.shape == 2 {
                            item.fill(Circle().path(in: rect), with: .color(color))
                        } else {
                            item.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
                        }
                    }
                }
            }
        }
        .onChange(of: burst) { old, new in
            // Ninety particles falling across the screen is the one effect with
            // no gentler version of itself, so Reduce Motion simply skips it.
            // Nothing is lost: the win is already announced by the banner, the
            // sound and the haptic.
            guard new > old, !reduceMotion else { return }
            // The size of the jump is the size of the burst. `GameSession` bumps
            // this by one for a big pot and by three for winning the tournament,
            // and testing `new > old` alone threw that away — the finale fell
            // exactly as heavily as any other good hand. Ninety is the fitted
            // unit; the cap is what stops a run of bursts arriving together from
            // putting hundreds of particles on the canvas at once.
            spawn(count: 90 * min(new - old, 3))
        }
    }

    private func spawn(count: Int) {
        let now = Date()
        var fresh: [Particle] = []
        for _ in 0..<count {
            fresh.append(Particle(
                x: CGFloat.random(in: 0...1),
                hue: [0.12, 0.14, 0.55, 0.0, 0.33, 0.75].randomElement()!,
                size: CGFloat.random(in: 6...12),
                spin: Double.random(in: 0...(2 * .pi)),
                fallDuration: Double.random(in: 2.2...3.8),
                drift: CGFloat.random(in: 12...44),
                shape: Int.random(in: 0...2),
                startedAt: now))
        }
        particles.append(contentsOf: fresh)

        // Trim finished particles later.
        Task {
            try? await Task.sleep(for: .seconds(4.2))
            particles.removeAll { Date().timeIntervalSince($0.startedAt) > $0.fallDuration }
        }
    }
}

// MARK: - Game Over

struct GameOverOverlay: View {
    let session: GameSession
    let onRematch: () -> Void
    let onExit: () -> Void

    private var won: Bool { session.game.gameOverHumanWon == true }

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()

            VStack(spacing: 20) {
                Text(verbatim: won ? "🏆" : "💀")
                    .font(.system(size: 64))
                    .accessibilityHidden(true)

                Text(won ? "gameOver.won.title" : "gameOver.lost.title")
                    .font(.system(.largeTitle, design: .rounded, weight: .black))
                    .foregroundStyle(won ? Theme.goldBright : Theme.cream)
                    .kerning(2)

                Text(won ? "gameOver.won.body" : "gameOver.lost.body")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(Theme.subtleText)
                    .multilineTextAlignment(.center)

                VStack(spacing: 8) {
                    statRow("gameOver.handsPlayed", "\(session.game.handNumber)")
                    statRow("gameOver.finalBlinds", "\(session.game.blindLevel.smallBlind.chipText)/\(session.game.blindLevel.bigBlind.chipText)")
                    if won {
                        statRow("gameOver.chipsWon", session.game.players[session.game.humanSeat].chips.chipText)
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 22)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(red: 0.09, green: 0.11, blue: 0.17))
                        .overlay(RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)))

                VStack(spacing: 10) {
                    Button(won ? "gameOver.playAgain" : "gameOver.rematch") {
                        Haptics.chips()
                        onRematch()
                    }
                    .buttonStyle(GoldButtonStyle())

                    Button("gameOver.backToMenu") {
                        Haptics.tap()
                        onExit()
                    }
                    .buttonStyle(GoldButtonStyle(prominent: false))
                }
                .padding(.top, 6)
            }
            .padding(30)
            .frame(maxWidth: 360)
        }
    }

    private func statRow(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(.footnote, design: .rounded, weight: .medium))
                .foregroundStyle(Theme.subtleText)
            Spacer()
            Text(verbatim: value)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.cream)
        }
        .frame(minWidth: 200, idealWidth: 230, maxWidth: 300)
        .accessibilityElement(children: .combine)
    }
}
