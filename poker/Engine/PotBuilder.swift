import Foundation

/// Builds main + side pots from each player's total investment in the hand.
/// Folded players' chips are dead money that flows into the pots they helped build.
nonisolated enum PotBuilder {

    nonisolated struct Pot: Sendable, Equatable {
        var amount: Int
        var eligibleSeats: [Int]   // seat ids of live players who can win this pot
    }

    /// - Parameter players: all players; uses `totalInvested`, `isInHand` and `id`.
    /// - Returns: pots ordered main pot first, then side pots.
    static func build(players: [Player]) -> [Pot] {
        var remaining: [Int: Int] = [:]
        for p in players where p.totalInvested > 0 {
            remaining[p.id] = p.totalInvested
        }

        let liveSeats = players.filter(\.isInHand).map(\.id)
        var pots: [Pot] = []

        while true {
            let liveWithChips = liveSeats.filter { (remaining[$0] ?? 0) > 0 }
            guard !liveWithChips.isEmpty else { break }

            // The smallest live contribution defines this pot's layer.
            let level = liveWithChips.map { remaining[$0]! }.min()!
            var amount = 0
            for (seat, value) in remaining where value > 0 {
                let take = min(value, level)
                amount += take
                remaining[seat] = value - take
            }
            pots.append(Pot(amount: amount, eligibleSeats: liveWithChips))
        }

        // Safety net: any leftover dead money joins the last pot. If every live
        // player somehow contributed nothing, the folded chips still have to go
        // somewhere, so open a pot for whoever is left rather than losing them.
        let leftover = remaining.values.reduce(0, +)
        if leftover > 0 {
            if pots.isEmpty {
                pots.append(Pot(amount: leftover,
                                eligibleSeats: liveSeats.isEmpty ? players.map(\.id) : liveSeats))
            } else {
                pots[pots.count - 1].amount += leftover
            }
        }

        // Merge consecutive layers with identical eligibility (no all-in between them).
        var merged: [Pot] = []
        for pot in pots {
            if var last = merged.last, Set(last.eligibleSeats) == Set(pot.eligibleSeats) {
                last.amount += pot.amount
                merged[merged.count - 1] = last
            } else {
                merged.append(pot)
            }
        }
        return merged
    }
}
