import SwiftUI
import Testing
@testable import poker

/// `TableLayout` places every piece of furniture with absolute maths that was
/// fitted, not guessed: one configuration that keeps seats, hole cards, bets,
/// bubbles, the board, the pot and the banner apart on every screen size and
/// seat count. These tests pin that down so a nudge to one constant cannot
/// quietly reintroduce an overlap somewhere else.
@Suite("Table layout")
@MainActor
struct TableLayoutTests {

    /// Screens the game has to fit, already reduced the way `GameView` does it.
    private static let screens: [(name: String, size: CGSize)] = [
        ("iPhone SE", CGSize(width: 375, height: 667)),
        ("iPhone 13 mini", CGSize(width: 375, height: 812)),
        ("iPhone 17", CGSize(width: 393, height: 852)),
        ("iPhone 17 Pro Max", CGSize(width: 440, height: 956)),
        ("iPad (capped)", CGSize(width: 540, height: 1188)),
    ]

    /// An iPad window dragged shorter than any device is tall. `GameView` caps
    /// the width at 540 but takes whatever height the window gives it, so the
    /// felt has to stay solvable even once there is no longer room for the
    /// controls beneath it. Before the felt had a minimum height, 540x420 put
    /// the board on top of two seats and 540x300 collapsed the felt to 4pt.
    private static let shortWindows: [(name: String, size: CGSize)] = [
        ("iPad tile 540x700", CGSize(width: 540, height: 700)),
        ("iPad tile 540x600", CGSize(width: 540, height: 600)),
        ("iPad tile 540x460", CGSize(width: 540, height: 460)),
        ("iPad tile 420x420", CGSize(width: 420, height: 420)),
        ("iPad tile 420x380", CGSize(width: 420, height: 380)),
        ("iPad tile 320x320", CGSize(width: 320, height: 320)),
    ]

    private static var everyLayout: [(name: String, size: CGSize)] { screens + shortWindows }

    private static let seatCounts = [1, 2, 3, 4, 5]

    /// The smallest window the system can hand `GameView`, and therefore the
    /// floor the layout has to hold at.
    ///
    /// 320pt in each direction: Split View's narrow pane and Slide Over are both
    /// 320pt wide at full height, and iPadOS will not resize a Stage Manager
    /// window below 320pt either way. `GameView` caps the width at 540 and takes
    /// the height it is given, so everything from this square up to the cap is
    /// reachable — which is what `nothingOverlapsOnAnyReachableWindow` sweeps.
    private static let minimumWindow = CGSize(width: 320, height: 320)
    private static let maximumWidth: CGFloat = 540

    private struct Piece {
        let name: String
        let rect: CGRect
    }

    /// Everything drawn on the felt, as bounding boxes.
    private func pieces(_ layout: TableLayout, opponents: Int) -> [Piece] {
        var result: [Piece] = []
        let metrics = layout.seatMetrics

        for seat in 1...opponents {
            let anchor = layout.seatPosition(seat)
            let halfWidth = max(80 * layout.scale, metrics.cardWidth * 1.55) / 2
            let height = metrics.blockHeight + metrics.cardOverhang
            result.append(Piece(name: "seat \(seat)", rect: CGRect(
                x: anchor.x - halfWidth,
                y: anchor.y - metrics.blockHeight / 2 - metrics.cardOverhang,
                width: halfWidth * 2, height: height)))

            let bubble = layout.bubblePosition(seat)
            result.append(Piece(name: "bubble \(seat)", rect: CGRect(
                x: bubble.x - layout.bubbleSize.width / 2,
                y: bubble.y - layout.bubbleSize.height / 2,
                width: layout.bubbleSize.width, height: layout.bubbleSize.height)))

            let bet = layout.betPosition(seat)
            result.append(Piece(name: "bet \(seat)", rect: CGRect(
                x: bet.x - layout.betStackSize.width / 2,
                y: bet.y - layout.betStackSize.height / 2,
                width: layout.betStackSize.width, height: layout.betStackSize.height)))
        }

        let boardWidth = layout.boardCardWidth * 5 + 7 * 4
        result.append(Piece(name: "board", rect: CGRect(
            x: layout.boardCenter.x - boardWidth / 2,
            y: layout.boardCenter.y - layout.boardCardHeight / 2,
            width: boardWidth, height: layout.boardCardHeight)))

        result.append(Piece(name: "pot", rect: layout.potBounds))

        // The result banner. `GameView` caps it at `tableRect.width - 40` and
        // centres it, so that cap is its widest possible footprint. It shares
        // the band with the human's own bet — which is why seat 0's bet is not
        // in this list — but nothing else may be in there with it.
        let bannerWidth = layout.tableRect.width - 40
        result.append(Piece(name: "banner", rect: CGRect(
            x: layout.bannerCenter.x - bannerWidth / 2,
            y: layout.bannerCenter.y - layout.bannerHeight / 2,
            width: bannerWidth, height: layout.bannerHeight)))

        let holeWidth = layout.humanCardWidth * 2 - layout.humanCardWidth * 0.32
        let holeHeight = layout.humanCardWidth * 1.42
        result.append(Piece(name: "your cards", rect: CGRect(
            x: layout.humanCardsCenter.x - holeWidth / 2,
            y: layout.humanCardsCenter.y - holeHeight / 2,
            width: holeWidth, height: holeHeight)))

        return result
    }

    /// The worst overlap between any two pieces, measured as the smaller side of
    /// the intersection — the depth of the bite one takes out of the other.
    /// 0 means nothing touches anything.
    private func worstOverlap(_ layout: TableLayout, opponents: Int) -> (bite: CGFloat, what: String) {
        let pieces = pieces(layout, opponents: opponents)
        var bite: CGFloat = 0
        var what = "nothing"
        for i in pieces.indices {
            for j in (i + 1)..<pieces.count {
                let overlap = pieces[i].rect.intersection(pieces[j].rect)
                guard !overlap.isNull else { continue }
                let depth = min(overlap.width, overlap.height)
                if depth > bite {
                    bite = depth
                    what = "\(pieces[i].name) overlaps \(pieces[j].name) by \(overlap.size)"
                }
            }
        }
        return (bite, what)
    }

    @Test func nothingOverlapsOnAnySupportedTable() {
        for screen in Self.everyLayout {
            for opponents in Self.seatCounts {
                let layout = TableLayout(size: screen.size, opponentCount: opponents)
                let (bite, what) = worstOverlap(layout, opponents: opponents)
                #expect(bite < 0.01, "\(screen.name), \(opponents) opponents: \(what)")
            }
        }
    }

    /// Every window the system can hand the app, not just the handful that were
    /// once convenient to name.
    ///
    /// Regression, and the reason this is a sweep: the fit used to hold on the
    /// five devices and break a few points to either side of them. At 380x667
    /// with five opponents seat 1's block took a 12x6pt bite out of seat 2's
    /// bubble, and that band ran from 380 to 400pt wide at every height up to
    /// ~700. iPhone SE itself passed only because the tolerance above used to be
    /// a whole point — the real clearance there was 0.18pt.
    @Test func nothingOverlapsOnAnyReachableWindow() {
        var worst: (bite: CGFloat, where_: String) = (0, "nothing")
        for width in stride(from: Self.minimumWindow.width, through: Self.maximumWidth, by: 5) {
            for height in stride(from: Self.minimumWindow.height, through: 1200, by: 20) {
                for opponents in Self.seatCounts {
                    let size = CGSize(width: width, height: height)
                    let layout = TableLayout(size: size, opponentCount: opponents)
                    let (bite, what) = worstOverlap(layout, opponents: opponents)
                    if bite > worst.bite {
                        worst = (bite, "\(Int(width))x\(Int(height)), \(opponents) opponents: \(what)")
                    }
                }
            }
        }
        #expect(worst.bite < 0.01, "worst overlap anywhere in the reachable range — \(worst.where_)")
    }

    @Test func everySeatKeepsItsCardsOnTheFelt() {
        for screen in Self.everyLayout {
            for opponents in Self.seatCounts {
                let layout = TableLayout(size: screen.size, opponentCount: opponents)
                let metrics = layout.seatMetrics
                let felt = layout.tableRect

                for seat in 1...opponents {
                    let anchor = layout.seatPosition(seat)
                    let cardsTop = anchor.y - metrics.blockHeight / 2 - metrics.cardOverhang
                    let plateBottom = anchor.y + metrics.blockHeight / 2
                    #expect(cardsTop >= felt.minY,
                            "\(screen.name), \(opponents) opponents: seat \(seat) deals over the rail")
                    #expect(plateBottom <= felt.maxY,
                            "\(screen.name), \(opponents) opponents: seat \(seat) hangs off the bottom")
                    #expect(anchor.x - 40 * layout.scale >= felt.minX)
                    #expect(anchor.x + 40 * layout.scale <= felt.maxX)
                }
            }
        }
    }

    /// The band between the board and your cards holds the result banner while a
    /// hand is over, and your own bet while one is running. They never coexist,
    /// but the band still has to be tall enough for either.
    @Test func theResultBandIsUsable() {
        for screen in Self.everyLayout {
            for opponents in Self.seatCounts {
                let layout = TableLayout(size: screen.size, opponentCount: opponents)
                // `bannerHeight` is a `max(30, ...)`, so asking whether it is at
                // least 30 asks nothing. The band is what can run out: it has to
                // be tall enough for the banner the layout says it will hold.
                let bandTop = layout.boardCenter.y + layout.boardCardHeight / 2
                let bandBottom = layout.humanCardsCenter.y - layout.humanCardWidth * 1.42 / 2
                #expect(bandBottom - bandTop >= layout.bannerHeight,
                        "\(screen.name), \(opponents) opponents: a \(layout.bannerHeight)pt banner in a \(bandBottom - bandTop)pt band")
                let bandCentre = layout.bannerCenter.y
                #expect(bandCentre > bandTop)
                #expect(bandCentre < layout.humanCardsCenter.y)
            }
        }
    }

    /// The space under the felt is not slack: it is what the action bar and the
    /// bet-sizing panel slide into. If the felt grew to fill it, opening the
    /// panel would cover your hole cards. Real devices only — a window dragged
    /// shorter than any of them has no room to promise.
    @Test func theBandUnderTheFeltFitsTheControls() {
        // Sourced from `ActionBarView` rather than restated, so growing a row
        // there cannot leave this test measuring the old footprint.
        let actionBar = ActionBarView.barHeight
        let raisePanel = ActionBarView.panelHeight

        for screen in Self.screens {
            for opponents in Self.seatCounts {
                let layout = TableLayout(size: screen.size, opponentCount: opponents)
                let available = screen.size.height - layout.tableRect.maxY
                #expect(available >= actionBar + raisePanel,
                        "\(screen.name), \(opponents) opponents: only \(available)pt under the felt")
            }
        }
    }

    /// Regression: the insets above and below the felt were fixed, so a window
    /// shorter than their sum drove the felt to zero — and then negative —
    /// height. They now give way in proportion instead. Device sizes must be
    /// untouched by that: every one of them has room for the full chrome.
    @Test func aShortWindowShrinksTheChromeRatherThanTheFelt() {
        for screen in Self.screens {
            let layout = TableLayout(size: screen.size, opponentCount: 4)
            // The felt starts at the top inset, or lower still when the aspect
            // cap leaves it centred in the space — never above it.
            #expect(layout.tableRect.minY >= 78,
                    "\(screen.name): chrome must keep its full size on a real device")
        }

        for window in Self.shortWindows {
            let layout = TableLayout(size: window.size, opponentCount: 5)
            // The felt keeps its minimum height, or the whole window when the
            // window is shorter than that minimum and there is nothing left to
            // give — never less.
            #expect(layout.tableRect.height >= min(370, window.size.height) - 0.5,
                    "\(window.name): felt collapsed to \(layout.tableRect.height)")
            #expect(layout.tableRect.minY >= 0)
            #expect(layout.tableRect.maxY <= window.size.height + 1,
                    "\(window.name): felt hangs out of the window")
        }
    }

    /// Adding a seat only ever shrinks the furniture, and it never goes below
    /// the hard floor.
    ///
    /// The floor is **not** 0.64, which is easy to misread from `fittedScale`:
    /// the clamp sits under `fit`, and the crowding factor still applies below
    /// it, so five opponents bottom out at 0.64 × 0.88 = 0.563. `solveScale`
    /// then gives up more still — down to `TableLayout.minScale` — on a window
    /// too short for the seat arc to fit at the fitted size.
    @Test func furnitureShrinksAsTheTableFillsUp() {
        for screen in Self.screens {
            let scales = Self.seatCounts.map {
                TableLayout(size: screen.size, opponentCount: $0).scale
            }
            #expect(scales == scales.sorted(by: >),
                    "\(screen.name): a busier table must not use bigger furniture: \(scales)")
            #expect(scales.allSatisfy { $0 > 0.5 && $0 <= 1 },
                    "\(screen.name): no real device should need the arc-driven reduction: \(scales)")
        }

        // Anywhere at all, including windows that do force the reduction.
        for window in Self.everyLayout {
            for opponents in Self.seatCounts {
                let scale = TableLayout(size: window.size, opponentCount: opponents).scale
                #expect(scale >= 0.44 && scale <= 1,
                        "\(window.name), \(opponents) opponents: scale \(scale) out of range")
            }
        }
    }
}

// MARK: - Diagnostics

@Suite("Table layout diagnostics", .disabled("run manually while tuning the layout"))
@MainActor
struct TableLayoutDiagnostics {
    @Test func dumpGeometry() {
        for (name, size) in [("iPhone 17", CGSize(width: 393, height: 852)),
                             ("iPhone 13 mini", CGSize(width: 375, height: 812))] {
            for opponents in [2, 3, 4, 5] {
                let l = TableLayout(size: size, opponentCount: opponents)
                print("--- \(name) \(opponents) opp  scale=\(String(format: "%.2f", l.scale)) felt=\(l.tableRect)")
                print("    centre=\(l.center) pot=\(l.potCenter) potH=\(l.potHeight) betSize=\(l.betStackSize)")
                for seat in 1...opponents {
                    print("    seat \(seat): anchor=\(fmt(l.seatPosition(seat))) bet=\(fmt(l.betPosition(seat)))")
                }
            }
        }
    }
    private func fmt(_ p: CGPoint) -> String {
        String(format: "(%.0f, %.0f)", p.x, p.y)
    }
}
