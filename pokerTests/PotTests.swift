import Foundation
import Testing
@testable import poker

@Suite("Pot building")
struct PotBuilderTests {

    @Test func everyoneMatched() {
        let pots = PotBuilder.build(players: [testPlayer(0, invested: 100), testPlayer(1, invested: 100)])
        #expect(pots.count == 1)
        #expect(pots[0].amount == 200)
        #expect(Set(pots[0].eligibleSeats) == [0, 1])
    }

    @Test func shortAllInMakesASidePot() {
        let pots = PotBuilder.build(players: [
            testPlayer(0, invested: 50), testPlayer(1, invested: 200), testPlayer(2, invested: 200),
        ])
        #expect(pots.count == 2)
        #expect(pots[0].amount == 150)
        #expect(Set(pots[0].eligibleSeats) == [0, 1, 2])
        #expect(pots[1].amount == 300)
        #expect(Set(pots[1].eligibleSeats) == [1, 2], "the short stack cannot win the side pot")
    }

    @Test func foldedChipsStayInThePot() {
        let pots = PotBuilder.build(players: [
            testPlayer(0, invested: 50), testPlayer(1, invested: 200),
            testPlayer(2, invested: 200), testPlayer(3, invested: 120, folded: true),
        ])
        #expect(pots.reduce(0) { $0 + $1.amount } == 570, "dead money is never lost")
        #expect(pots[0].amount == 200)
        #expect(pots[1].amount == 370)
    }

    @Test func threeLevelsOfAllIn() {
        let pots = PotBuilder.build(players: [
            testPlayer(0, invested: 30), testPlayer(1, invested: 80),
            testPlayer(2, invested: 200), testPlayer(3, invested: 200),
        ])
        #expect(pots.count == 3)
        #expect(pots[0].amount == 120 && Set(pots[0].eligibleSeats) == [0, 1, 2, 3])
        #expect(pots[1].amount == 150 && Set(pots[1].eligibleSeats) == [1, 2, 3])
        #expect(pots[2].amount == 240 && Set(pots[2].eligibleSeats) == [2, 3])
    }

    @Test func layersWithTheSameEligibilityMerge() {
        let pots = PotBuilder.build(players: [testPlayer(0, invested: 60), testPlayer(1, invested: 60)])
        #expect(pots.count == 1, "no all-in between the layers means one pot")
    }
}

@Suite("Chip formatting")
struct ChipFormattingTests {

    private static let english = Locale(identifier: "en_US")

    @Test(arguments: [
        (0, "0"), (5, "5"), (950, "950"), (9_999, "9999"),
        (10_000, "10K"), (12_500, "12.5K"),
        // The K/M handover is where the rounding decides, not where the digits
        // do: one decimal place means 999_950 already reads as a million, and
        // the branch has to move with it or that value prints "1000K".
        (999_949, "999.9K"), (999_950, "1M"), (999_999, "1M"),
        (1_000_000, "1M"), (2_400_000, "2.4M"),
    ])
    func formatsChipCounts(amount: Int, expected: String) {
        #expect(amount.chipText(in: Self.english) == expected)
    }

    /// A figure in thousands that has rounded up to a thousand of them is a
    /// million, and has to say so. Sweeping the handover rather than asserting
    /// the one value, because the cutoff follows `trim`'s rounding and would
    /// move again if that ever changed.
    @Test func theThousandsFormNeverReachesAMillion() {
        for amount in stride(from: 10_000, through: 5_000_000, by: 4_999) {
            let text = amount.chipText(in: Self.english)
            guard text.hasSuffix("K") else { continue }
            let figure = Double(text.dropLast())
            #expect(figure != nil && figure! < 1_000, "\(amount) abbreviated to \(text)")
        }
    }

    @Test func staysExactBelowTenThousand() {
        for amount in stride(from: 0, to: 10_000, by: 137) {
            #expect(amount.chipText(in: Self.english) == String(amount))
        }
    }

    /// Regression: the abbreviation was built with `String(format: "%.1f")` and
    /// no locale, which always writes a period. A Czech device wants 12,5K, and
    /// a stack size is on screen constantly.
    @Test func theDecimalSeparatorFollowsTheRegion() {
        let czech = Locale(identifier: "cs_CZ")
        #expect(12_500.chipText(in: czech) == "12,5K")
        #expect(2_400_000.chipText(in: czech) == "2,4M")
        // Whole numbers have no separator to get wrong, in either region.
        #expect(10_000.chipText(in: czech) == "10K")
        #expect(9_999.chipText(in: czech) == "9999")
    }
}
