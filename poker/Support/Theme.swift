import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Reduce Motion

/// Almost everything on the felt moves: cards fly in from the deck, chips
/// travel to the pot, the winner's plate springs, confetti falls. `Reduce
/// Motion` asks for none of it, so the views that exist to move read
/// `\.accessibilityReduceMotion` and fall back to a cross-fade — which is the
/// substitution Apple's guidance asks for — or to no change at all.
///
/// This is for the handful of places with no environment to read: `GameSession`
/// drives `showGameOver` and the toast from outside the view tree.
enum Motion {
    @MainActor
    static var isReduced: Bool {
        #if canImport(UIKit)
        UIAccessibility.isReduceMotionEnabled
        #else
        false
        #endif
    }

    /// `animation`, or a plain fade of the same length when motion is reduced.
    @MainActor
    static func fading(_ animation: Animation, over duration: Double) -> Animation {
        isReduced ? .easeInOut(duration: duration) : animation
    }
}

// MARK: - Felt color themes

enum FeltTheme: String, CaseIterable, Codable, Identifiable {
    case emerald = "Emerald"
    case sapphire = "Sapphire"
    case garnet = "Garnet"
    case midnight = "Midnight"

    var id: String { rawValue }

    var displayName: String { localized(.init("felt.\(rawValue.lowercased())")) }

    var center: Color {
        switch self {
        case .emerald: return Color(red: 0.10, green: 0.44, blue: 0.27)
        case .sapphire: return Color(red: 0.09, green: 0.28, blue: 0.48)
        case .garnet: return Color(red: 0.42, green: 0.12, blue: 0.16)
        case .midnight: return Color(red: 0.15, green: 0.18, blue: 0.28)
        }
    }

    var edge: Color {
        switch self {
        case .emerald: return Color(red: 0.04, green: 0.24, blue: 0.14)
        case .sapphire: return Color(red: 0.03, green: 0.13, blue: 0.26)
        case .garnet: return Color(red: 0.20, green: 0.05, blue: 0.08)
        case .midnight: return Color(red: 0.06, green: 0.08, blue: 0.14)
        }
    }
}

// MARK: - Palette

enum Theme {
    // Backgrounds
    static let backgroundTop = Color(red: 0.055, green: 0.07, blue: 0.115)
    static let backgroundBottom = Color(red: 0.09, green: 0.11, blue: 0.18)

    // Accents
    /// Mirrored by `Assets.xcassets/AccentColor`, which is what tints the
    /// controls the app does not style itself — the confirmation dialogs and the
    /// sheet toolbars. Change one and change the other, or the system furniture
    /// goes back to being blue in a gold app.
    static let gold = Color(red: 0.89, green: 0.72, blue: 0.32)
    static let goldBright = Color(red: 0.98, green: 0.84, blue: 0.45)
    static let goldDark = Color(red: 0.62, green: 0.47, blue: 0.18)
    static let cream = Color(red: 0.96, green: 0.94, blue: 0.88)
    static let subtleText = Color.white.opacity(0.55)

    // Cards
    static let cardFace = Color(red: 0.99, green: 0.98, blue: 0.95)
    static let cardRed = Color(red: 0.78, green: 0.11, blue: 0.17)
    static let cardBlack = Color(red: 0.12, green: 0.12, blue: 0.16)
    static let cardBlue = Color(red: 0.13, green: 0.33, blue: 0.70)   // 4-color deck diamonds
    static let cardGreen = Color(red: 0.10, green: 0.48, blue: 0.25)  // 4-color deck clubs
    static let cardBack = Color(red: 0.52, green: 0.12, blue: 0.16)
    static let cardBackDark = Color(red: 0.33, green: 0.06, blue: 0.09)

    // Actions
    static let fold = Color(red: 0.72, green: 0.25, blue: 0.25)
    static let call = Color(red: 0.20, green: 0.52, blue: 0.55)
    static let raise = Color(red: 0.80, green: 0.62, blue: 0.22)
    static let allInRed = Color(red: 0.85, green: 0.22, blue: 0.28)

    // Chips by denomination
    static func chipColor(for amount: Int) -> (main: Color, accent: Color) {
        switch amount {
        case ..<25: return (Color(red: 0.82, green: 0.83, blue: 0.85), Color(red: 0.35, green: 0.38, blue: 0.45))
        case ..<100: return (Color(red: 0.80, green: 0.24, blue: 0.24), .white)
        case ..<500: return (Color(red: 0.16, green: 0.42, blue: 0.72), .white)
        case ..<2000: return (Color(red: 0.15, green: 0.55, blue: 0.34), .white)
        case ..<10000: return (Color(red: 0.18, green: 0.18, blue: 0.22), Theme.gold)
        default: return (Color(red: 0.50, green: 0.24, blue: 0.60), .white)
        }
    }

    static var backgroundGradient: LinearGradient {
        LinearGradient(colors: [backgroundTop, backgroundBottom],
                       startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Suit colors

extension Card {
    func color(fourColor: Bool) -> Color {
        if fourColor {
            switch suit {
            case .hearts: return Theme.cardRed
            case .diamonds: return Theme.cardBlue
            case .clubs: return Theme.cardGreen
            case .spades: return Theme.cardBlack
            }
        }
        return suit.isRed ? Theme.cardRed : Theme.cardBlack
    }
}

// MARK: - Reusable styles

struct GoldButtonStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration, prominent: prominent)
    }

    /// The label wrapped in a view of its own, purely so it has an environment
    /// to read: a `ButtonStyle` is not a `View` and cannot see
    /// `\.accessibilityReduceMotion`, and the press feedback here is a scale.
    /// Named `Content` rather than `Body`: a nested `Body` collides with
    /// `ButtonStyle`'s own associated type and stops the conformance compiling.
    private struct Content: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(prominent ? Color.black.opacity(0.82) : Theme.gold)
                .padding(.vertical, 14)
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity)
                .background {
                    if prominent {
                        Capsule().fill(
                            LinearGradient(colors: [Theme.goldBright, Theme.gold, Theme.goldDark],
                                           startPoint: .top, endPoint: .bottom))
                    } else {
                        ZStack {
                            Capsule().fill(Color.white.opacity(0.06))
                            Capsule().strokeBorder(Theme.gold.opacity(0.6), lineWidth: 1.5)
                        }
                    }
                }
                .shadow(color: prominent ? Theme.gold.opacity(0.35) : .clear, radius: 10, y: 3)
                // Reduce Motion keeps the feedback and drops the movement: the
                // button dims on touch instead of shrinking. Taking the press
                // away entirely would leave a tap with no answer at all, which
                // is worse than the thing being avoided.
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
                .opacity(configuration.isPressed && reduceMotion ? 0.72 : 1)
                .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.2),
                           value: configuration.isPressed)
        }
    }
}
