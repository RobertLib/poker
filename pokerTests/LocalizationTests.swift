import Foundation
import Testing
@testable import poker

/// The app ships English and Czech. Nothing here checks translation quality —
/// it checks the things that silently break a shipped localisation: a key that
/// exists in one language but not the other, and a format string whose
/// placeholders do not match the code that fills them in.
@Suite("Localisation")
@MainActor
struct LocalizationTests {

    private static let languages = ["en", "cs"]

    private static func table(_ language: String) throws -> [String: String] {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"),
                                "\(language).lproj is missing from the app bundle")
        let strings = try #require(NSDictionary(contentsOfFile: path + "/Localizable.strings") as? [String: String],
                                   "\(language) has no compiled strings table")
        return strings
    }

    @Test func bothLanguagesShip() throws {
        for language in Self.languages {
            let strings = try Self.table(language)
            #expect(strings.count > 150, "\(language) only has \(strings.count) strings")
        }
    }

    @Test func everyKeyIsTranslatedInEveryLanguage() throws {
        let english = try Self.table("en")
        let czech = try Self.table("cs")

        let missingFromCzech = Set(english.keys).subtracting(czech.keys).sorted()
        #expect(missingFromCzech.isEmpty, "not translated into Czech: \(missingFromCzech)")

        let missingFromEnglish = Set(czech.keys).subtracting(english.keys).sorted()
        #expect(missingFromEnglish.isEmpty, "Czech-only keys: \(missingFromEnglish)")
    }

    /// A translation that drops or reorders a placeholder produces garbage — or
    /// crashes — at runtime, and only on the device set to that language.
    @Test func placeholdersSurviveTranslation() throws {
        let english = try Self.table("en")
        let czech = try Self.table("cs")

        func specifiers(_ format: String) -> Int {
            var count = 0
            var index = format.startIndex
            while let found = format[index...].firstIndex(of: "%") {
                let next = format.index(after: found)
                guard next < format.endIndex else { break }
                if format[next] != "%" { count += 1 }
                index = format.index(after: next)
            }
            return count
        }

        for (key, source) in english {
            guard let translation = czech[key] else { continue }
            let expected = specifiers(source)
            let actual = specifiers(translation)
            #expect(expected == actual,
                    "\(key): en has \(expected) placeholders, cs has \(actual) — \"\(translation)\"")
        }
    }

    /// Multi-placeholder formats must be positional, because Czech reorders them.
    @Test func multiArgumentFormatsArePositional() throws {
        for language in Self.languages {
            for (key, value) in try Self.table(language) {
                let plain = value.components(separatedBy: "%@").count - 1
                let positional = value.components(separatedBy: "$@").count - 1
                if plain + positional > 1 {
                    #expect(plain == 0,
                            "\(language) \(key): \"\(value)\" mixes bare and positional placeholders")
                }
            }
        }
    }

    /// A counted noun needs one form per plural category, and a catalog entry
    /// that has them compiles to a `.stringsdict` instead of the `.strings`
    /// table — which is exactly why the checks above cannot see it. Czech takes
    /// three forms across 1…5 (1 soupeř / 2–4 soupeři / 5 soupeřů) and English
    /// two; a single form reads "1 opponents" and "1 soupeřů".
    @Test func countedNounsAgreeWithTheirNumber() throws {
        // The picker offers one to five opponents, so every one of those has to
        // come out right — not just the plural the string was written in.
        let expectedForms = ["en": 2, "cs": 3]

        for language in Self.languages {
            let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
            let bundle = try #require(Bundle(path: path))
            let locale = Locale(identifier: language)

            var forms: Set<String> = []
            for count in 1...5 {
                let text = String(localized: "a11y.opponentCount \(count)",
                                  bundle: bundle, locale: locale)
                #expect(!text.contains("a11y."), "\(language) \(count) fell through: \(text)")
                #expect(text.contains("\(count)"), "\(language) \(count) lost the number: \(text)")
                // The noun alone, so 1 and 2 differing only by the digit does
                // not count as two forms.
                forms.insert(text.replacingOccurrences(of: "\(count)", with: ""))
            }
            #expect(forms.count == expectedForms[language],
                    "\(language) uses \(forms.count) form(s) across 1…5: \(forms.sorted())")
        }
    }

    /// Every rank has to answer in all four grammatical forms, and no two forms
    /// may collapse in Czech — that is what would give "pár králové".
    @Test func everyRankHasEveryForm() {
        for rank in Rank.allCases {
            for form in [RankForm.singular, .plural, .pluralPossessive, .singularTarget] {
                let name = rank.name(form)
                #expect(!name.isEmpty)
                #expect(!name.contains("rank."), "\(rank) \(form) fell through to its key: \(name)")
            }
        }
    }

    @Test func everySuitHasEveryGender() {
        for suit in Suit.allCases {
            for gender in [GrammaticalGender.masculine, .feminine, .neuter] {
                let name = suit.name(agreeingWith: gender)
                #expect(!name.isEmpty)
                #expect(!name.contains("suit."), "\(suit) \(gender) fell through to its key: \(name)")
            }
        }
    }

    @Test func everyCardCanBeSpoken() {
        for card in Card.fullDeck {
            let spoken = card.spokenName
            #expect(!spoken.isEmpty)
            #expect(!spoken.contains("card.name"), "\(card) fell through to its key: \(spoken)")
            #expect(!spoken.contains("%"), "\(card) left a placeholder behind: \(spoken)")
        }
    }

    /// Anything the UI shows through a plain `Text(String)` has to be localised
    /// before it gets there, so none of it may leak a raw key.
    @Test func runtimeBuiltStringsAreResolved() {
        for category in HandCategory.allCases {
            #expect(!category.displayName.contains("hand."), "\(category): \(category.displayName)")
        }
        for street in Street.allCases {
            #expect(!street.displayName.contains("street."))
        }
        for difficulty in Difficulty.allCases {
            #expect(!difficulty.displayName.contains("difficulty."))
        }
        for speed in BlindSpeed.allCases {
            #expect(!speed.displayName.contains("blindSpeed."))
        }
        for speed in GameSpeed.allCases {
            #expect(!speed.displayName.contains("gameSpeed."))
        }
        for felt in FeltTheme.allCases {
            #expect(!felt.displayName.contains("felt."))
        }
        for profile in AIProfile.roster {
            #expect(!profile.tagline.contains("opponent."), "\(profile.id): \(profile.tagline)")
        }
        for label: ActionLabel in [.smallBlind(5), .bigBlind(10), .fold, .check,
                                   .call(20), .bet(40), .raise(80), .allIn(500)] {
            #expect(!label.text.contains("bubble."), "\(label.text)")
            #expect(!label.text.contains("action."), "\(label.text)")
            #expect(!label.text.contains("%"), "\(label.text)")
        }
    }

    /// Hand names are assembled from a template plus rank forms; if either side
    /// is missing the player sees a key or a stray placeholder mid-game.
    @Test func everyHandNameResolves() {
        var rng = SplitMix64(seed: 4242)
        var deck = Card.fullDeck
        for _ in 0..<3_000 {
            for i in 0..<7 {
                deck.swapAt(i, i + Int(rng.next(upperBound: UInt64(deck.count - i))))
            }
            let name = HandEvaluator.evaluate(Array(deck.prefix(7))).name
            #expect(!name.isEmpty)
            #expect(!name.contains("hand.name"), "unresolved template: \(name)")
            #expect(!name.contains("%"), "stray placeholder: \(name)")
        }
    }
}
