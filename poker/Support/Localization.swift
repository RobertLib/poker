import Foundation

// MARK: - Shorthand

/// The app ships English and Czech. Every user-facing string goes through here
/// (or through a SwiftUI `Text` literal, which localises itself).
nonisolated func localized(_ key: String.LocalizationValue) -> String {
    String(localized: key)
}

// MARK: - Card ranks

/// Czech inflects, so a rank cannot be dropped into a sentence in one fixed
/// form. Each phrase below picks the case it needs; English fills every slot
/// with one of its two forms.
nonisolated enum RankForm {
    /// "King" / "král" — the plain naming form.
    case singular
    /// "Kings" / "králové" — a set of them, as the subject.
    case plural
    /// "Kings" / "králů" — "a pair *of kings*".
    case pluralPossessive
    /// "King" / "krále" — "a straight *to the king*".
    case singularTarget
}

nonisolated extension Rank {

    func name(_ form: RankForm) -> String {
        switch form {
        case .singular: return localized(.init("rank.\(key).singular"))
        case .plural: return localized(.init("rank.\(key).plural"))
        case .pluralPossessive: return localized(.init("rank.\(key).pluralPossessive"))
        case .singularTarget: return localized(.init("rank.\(key).singularTarget"))
        }
    }

    /// Grammatical gender of the rank's noun, which Czech suit adjectives
    /// have to agree with.
    var gender: GrammaticalGender {
        switch self {
        case .king, .jack: return .masculine
        case .ace: return .neuter
        default: return .feminine
        }
    }

    /// Stable, language-independent identifier used to build catalog keys.
    var key: String {
        switch self {
        case .two: return "two"
        case .three: return "three"
        case .four: return "four"
        case .five: return "five"
        case .six: return "six"
        case .seven: return "seven"
        case .eight: return "eight"
        case .nine: return "nine"
        case .ten: return "ten"
        case .jack: return "jack"
        case .queen: return "queen"
        case .king: return "king"
        case .ace: return "ace"
        }
    }
}
