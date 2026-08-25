import SwiftUI

// MARK: - Seat metrics

/// Sizes for one opponent seat. Derived by `TableLayout` so the layout math and
/// the rendered view can never drift apart.
struct SeatMetrics: Equatable {
    let avatar: CGFloat
    let cardWidth: CGFloat
    let plateHeight: CGFloat
    let spacing: CGFloat
    let scale: CGFloat

    var cardHeight: CGFloat { cardWidth * 1.42 }
    /// How far the hole cards peek above the avatar.
    var cardOverhang: CGFloat { cardWidth * 0.62 }
    /// Height of the avatar + plate block, which `.position` centres on the seat anchor.
    var blockHeight: CGFloat { max(avatar, cardHeight) + spacing + plateHeight }
}

// MARK: - Table layout math

/// Every position on the table is derived here from one felt rectangle, so the
/// whole board scales together. Furniture shrinks on small screens and as the
/// table fills up, which is what keeps seats, bets, bubbles, the board and the
/// result banner from overlapping on anything from an iPhone SE to an iPad.
struct TableLayout {
    let size: CGSize
    let opponentCount: Int

    /// Seat anchors, bubbles and chip positions are solved once per layout pass:
    /// the seat search is iterative, and the bubbles and the chips each have to
    /// be placed as a set so neighbouring ones do not land on top of each other.
    ///
    /// Order matters — the scale has to settle before anything is placed on the
    /// felt, bubbles avoid the solved seats, and the chips avoid both.
    private var solvedScale: CGFloat = 1
    private var seatAnchors: [CGPoint] = []
    private var bubbleSpots: [CGPoint] = []
    private var betSpots: [CGPoint] = []

    init(size: CGSize, opponentCount: Int) {
        self.size = size
        self.opponentCount = opponentCount
        solvedScale = solveScale()
        seatAnchors = (0...max(opponentCount, 0)).map { solveSeatPosition($0) }
        bubbleSpots = solveBubbleSpots()
        betSpots = solveBetSpots()
    }

    private static let topInset: CGFloat = 78
    private static let bottomInset: CGFloat = 218
    /// Smallest felt the seat arc still solves on. Fitted, not guessed: below
    /// roughly this the arc flattens until the upper seats collide with their
    /// neighbours' action bubbles.
    private static let minFeltHeight: CGFloat = 370

    // Reference furniture sizes, all multiplied by `scale`.
    private static let refAvatar: CGFloat = 52
    private static let refOpponentCard: CGFloat = 30
    private static let refPlate = CGSize(width: 80, height: 34)
    private static let refBubble = CGSize(width: 92, height: 22)
    private static let refHumanCard: CGFloat = 84
    private static let refPotHeight: CGFloat = 52

    // MARK: Felt

    var tableRect: CGRect {
        let (top, bottom) = Self.chromeInsets(forHeight: size.height)
        let available = max(size.height - top - bottom, min(Self.minFeltHeight, size.height))
        let width = size.width - 24
        // Cap the aspect so tall screens (notably iPad) don't stretch the felt
        // into dead space below the board.
        let height = min(available, width * 1.5)
        return CGRect(x: 12, y: top + (available - height) / 2,
                      width: width, height: height)
    }

    /// Chrome keeps its full size while the window has room for it. Below that —
    /// an iPad tile dragged short — the insets give way in proportion instead,
    /// because a felt squeezed into the leftover gap collapses: seat anchors go
    /// past each other and the board lands on top of them.
    private static func chromeInsets(forHeight height: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        let chrome = topInset + bottomInset
        guard height - chrome < minFeltHeight else { return (topInset, bottomInset) }
        let squeeze = max(min((height - minFeltHeight) / chrome, 1), 0)
        return (topInset * squeeze, bottomInset * squeeze)
    }

    var center: CGPoint { CGPoint(x: tableRect.midX, y: tableRect.midY) }

    /// 1 = full size. Falls with the felt's size, with every seat past three,
    /// and — only where the arc would otherwise fold in on itself — as far again
    /// as it takes to keep the seats apart. Solved in `init`; see `solveScale`.
    var scale: CGFloat { solvedScale }

    /// The fitted value, before any arc-driven reduction.
    ///
    /// Note the floor sits under `fit` rather than under the result, so the
    /// crowding factor still applies below it: five opponents bottom out at
    /// 0.64 × 0.88 = 0.563, not at 0.64. That is deliberate — a busy table has
    /// to give up more than a heads-up one — but it means 0.64 is the floor on
    /// how small the *felt* may make the furniture, not on the furniture itself.
    private static func fittedScale(felt: CGRect, opponentCount: Int) -> CGFloat {
        let fit = min(felt.width / 378, felt.height / 578)
        let crowding = 1 - 0.06 * CGFloat(max(0, opponentCount - 3))
        return max(0.64, min(1, fit)) * crowding
    }

    /// Hard floor. Below this the plates stop being readable, so a window too
    /// small even for this keeps the floor and accepts the crowding.
    private static let minScale: CGFloat = 0.44

    /// The fitted scale, given up only as far as it takes to keep the seat
    /// blocks off each other.
    ///
    /// On every real device, and on every window with room for the arc, the
    /// fitted value already clears and is returned untouched. It is windows
    /// shorter than the arc needs — an iPad tile barely 300pt tall — that force
    /// the issue: `seatRadii` flattens faster than the blocks shrink, so at some
    /// point neighbouring seats sit on top of one another. Shrinking the whole
    /// table is the graceful way out, and it is self-correcting: a smaller scale
    /// both narrows the blocks and *widens* the vertical radius, because the
    /// radius subtracts `64 * scale`.
    private func solveScale() -> CGFloat {
        let fitted = Self.fittedScale(felt: tableRect, opponentCount: opponentCount)
        guard opponentCount > 1 else { return fitted }
        for candidate in stride(from: fitted, to: Self.minScale, by: -0.02) {
            if seatBlocksClear(at: candidate) { return candidate }
        }
        return Self.minScale
    }

    private func seatBlocksClear(at scale: CGFloat) -> Bool {
        let metrics = metrics(at: scale)
        let boxes = (1...opponentCount).map {
            seatBlockBounds(at: solveSeatPosition($0, metrics: metrics), metrics: metrics)
        }
        for i in boxes.indices {
            for j in (i + 1)..<boxes.count where boxes[i].intersects(boxes[j]) {
                return false
            }
        }
        return true
    }

    // MARK: Seats

    var seatMetrics: SeatMetrics { metrics(at: scale) }

    private func metrics(at scale: CGFloat) -> SeatMetrics {
        SeatMetrics(avatar: Self.refAvatar * scale,
                    cardWidth: Self.refOpponentCard * scale,
                    plateHeight: Self.refPlate.height * scale,
                    spacing: 4 * scale,
                    scale: scale)
    }

    /// Angles in degrees; 270 = top centre. Symmetric about the top, leaving the
    /// bottom arc for the human. Any unexpected count falls back to an even spread.
    static func opponentAngles(for count: Int) -> [Double] {
        switch count {
        case 1: return [270]
        case 2: return [225, 315]
        case 3: return [205, 270, 335]
        case 4: return [190, 235, 305, 350]
        case 5: return [188, 224, 270, 316, 352]
        default:
            guard count > 0 else { return [] }
            let start = 184.0, span = 172.0
            return (0..<count).map { start + span * Double($0) / Double(max(count - 1, 1)) }
        }
    }

    private func seatRadii(at scale: CGFloat) -> CGSize {
        CGSize(width: tableRect.width / 2 - 28 * scale,
               height: tableRect.height / 2 - max(64 * scale, tableRect.height * 0.12))
    }

    func seatPosition(_ seatID: Int) -> CGPoint {
        if seatAnchors.indices.contains(seatID) { return seatAnchors[seatID] }
        return solveSeatPosition(seatID)
    }

    private func solveSeatPosition(_ seatID: Int) -> CGPoint {
        solveSeatPosition(seatID, metrics: seatMetrics)
    }

    /// Takes its metrics rather than reading `scale`, so `solveScale` can ask
    /// where the seats would land at a scale that is not the current one.
    private func solveSeatPosition(_ seatID: Int, metrics: SeatMetrics) -> CGPoint {
        let scale = metrics.scale
        if seatID == 0 {
            return CGPoint(x: center.x, y: tableRect.maxY - 34 * scale)
        }
        let angles = Self.opponentAngles(for: opponentCount)
        guard !angles.isEmpty else { return center }
        let index = min(max(seatID - 1, 0), angles.count - 1)
        let radians = angles[index] * .pi / 180
        let radii = seatRadii(at: scale)
        var point = CGPoint(x: center.x + radii.width * cos(radians),
                            y: center.y + radii.height * sin(radians))

        // Draw the seat toward the middle until its whole block — hole cards
        // included — sits on the felt. Without this, upper seats deal their
        // cards over the rail and off the table.
        for _ in 0..<14 {
            if feltContains(seatBounds(at: point, metrics: metrics)) { break }
            point = CGPoint(x: center.x + (point.x - center.x) * 0.94,
                            y: center.y + (point.y - center.y) * 0.94)
        }
        return point
    }

    private func seatBounds(at point: CGPoint, metrics: SeatMetrics) -> CGRect {
        let halfWidth = max(Self.refPlate.width * metrics.scale,
                            metrics.cardWidth * 2 - metrics.cardWidth * 0.45) / 2
        return CGRect(x: point.x - halfWidth,
                      y: point.y - metrics.blockHeight / 2 - metrics.cardOverhang,
                      width: halfWidth * 2,
                      height: metrics.blockHeight + metrics.cardOverhang)
    }

    /// Rounded-rectangle containment against the felt, with a comfortable margin.
    private func feltContains(_ rect: CGRect) -> Bool {
        let margin: CGFloat = 8
        let radius = min(tableRect.width, tableRect.height) * 0.44
        let inner = CGRect(x: tableRect.minX + radius, y: tableRect.minY + radius,
                           width: max(tableRect.width - radius * 2, 0),
                           height: max(tableRect.height - radius * 2, 0))
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
        for corner in corners {
            let anchor = CGPoint(x: min(max(corner.x, inner.minX), inner.maxX),
                                 y: min(max(corner.y, inner.minY), inner.maxY))
            let dx = corner.x - anchor.x, dy = corner.y - anchor.y
            if dx == 0 && dy == 0 {
                guard tableRect.insetBy(dx: margin, dy: margin).contains(corner) else { return false }
            } else if (dx * dx + dy * dy).squareRoot() > radius - margin {
                return false
            }
        }
        return true
    }

    // MARK: Bets & bubbles

    /// Deliberately narrow. The chips travel down a corridor between the seat's
    /// own furniture and the pot, and on a crowded small screen that corridor is
    /// only about sixty points wide.
    var betStackSize: CGSize { CGSize(width: 62 * scale, height: 30 * scale) }

    /// Chips a player has pushed out sit in the first clear spot on the line
    /// from their seat toward the middle of the table.
    ///
    /// This is a search rather than a formula on purpose. `seatPosition` pulls
    /// crowded seats inward to keep their hole cards on the felt, so the space
    /// between a seat and the pot varies with both the screen and the number of
    /// players — a fixed fraction of that distance used to drop the chips onto
    /// the seat plate, its action bubble or the pot itself.
    func betPosition(_ seatID: Int) -> CGPoint {
        // The human's chips go in the open band between the board and their cards.
        if seatID == 0 { return CGPoint(x: center.x, y: resultBand.midY) }
        if betSpots.indices.contains(seatID - 1) { return betSpots[seatID - 1] }
        return solveBetSpot(seatID, avoiding: [])
    }

    /// Places every opponent's chips in turn, each avoiding the ones already
    /// down. Solving them together is what keeps two neighbours' stacks apart.
    private func solveBetSpots() -> [CGPoint] {
        guard opponentCount > 0 else { return [] }
        var placed: [CGRect] = []
        var spots: [CGPoint] = []
        for seat in 1...opponentCount {
            let spot = solveBetSpot(seat, avoiding: placed)
            spots.append(spot)
            placed.append(CGRect(x: spot.x - betStackSize.width / 2,
                                 y: spot.y - betStackSize.height / 2,
                                 width: betStackSize.width, height: betStackSize.height))
        }
        return spots
    }

    private func solveBetSpot(_ seatID: Int, avoiding placed: [CGRect]) -> CGPoint {
        let seat = seatPosition(seatID)
        let dx = center.x - seat.x, dy = center.y - seat.y
        let travel = (dx * dx + dy * dy).squareRoot()
        guard travel > 1 else { return seat }
        let ux = dx / travel, uy = dy / travel

        // Everything the chips must not land on: this seat's own furniture, the
        // board and pot in the middle, and every other seat's furniture.
        var obstacles = [seatBlockBounds(at: seat), bubbleBounds(seatID), potBounds, boardBounds]
        for other in 1...max(opponentCount, 1) where other != seatID {
            obstacles.append(seatBlockBounds(at: seatPosition(other)))
            obstacles.append(bubbleBounds(other))
        }
        obstacles.append(contentsOf: placed)

        let gap = 4 * scale
        let size = betStackSize
        let felt = tableRect.insetBy(dx: 10 * scale, dy: 10 * scale)
        // Sideways room as well as forward room: on a crowded table the straight
        // line from a side seat to the middle runs right through the pot, while a
        // few points off to one side is wide open.
        let sidesteps: [CGFloat] = [0, -14, 14, -28, 28, -42, 42].map { $0 * scale }

        // The emptiest spot seen so far, for the felt too small to have a clear
        // one. Scored by area, so "off the felt" and "on the pot" are the same
        // currency and the two can be traded off.
        var fallback: (centre: CGPoint, cost: CGFloat)?
        let stackArea = size.width * size.height

        var distance = 6 * scale
        while distance < travel {
            for sidestep in sidesteps {
                let centre = CGPoint(x: seat.x + ux * distance - uy * sidestep,
                                     y: seat.y + uy * distance + ux * sidestep)
                let box = CGRect(x: centre.x - size.width / 2 - gap,
                                 y: centre.y - size.height / 2 - gap,
                                 width: size.width + gap * 2, height: size.height + gap * 2)
                if felt.contains(box), !obstacles.contains(where: { $0.intersects(box) }) {
                    return centre
                }
                let stack = CGRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2,
                                   width: size.width, height: size.height)
                let cost = obstacles.reduce(0) { $0 + Self.overlapArea($1, stack) }
                    + (stackArea - Self.overlapArea(tableRect, stack))
                if cost < (fallback?.cost ?? .greatestFiniteMagnitude) {
                    fallback = (centre, cost)
                }
            }
            // Unscaled on purpose, unlike the start of the walk: the step is the
            // search's resolution, not a size on the felt. Scaling it looks like
            // the consistent thing to do and is not — it moves where the chips
            // land on every one of the five reference sizes, iPhone 17 and 17
            // Pro Max included. The sweep says the spots it finds now do not
            // overlap, so there is nothing to buy for that.
            distance += 3
        }
        // Every spot on the line is taken. Take the emptiest one rather than a
        // fixed fraction of the way in: on a felt this small the chips have to
        // touch something, and the corner of the pot beats the middle of it.
        return fallback?.centre
            ?? CGPoint(x: seat.x + ux * travel * 0.45, y: seat.y + uy * travel * 0.45)
    }

    private static func overlapArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let overlap = a.intersection(b)
        return overlap.isNull ? 0 : overlap.width * overlap.height
    }

    var boardBounds: CGRect {
        let width = boardCardWidth * 5 + 7 * 4
        return CGRect(x: boardCenter.x - width / 2, y: boardCenter.y - boardCardHeight / 2,
                      width: width, height: boardCardHeight)
    }

    /// The seat's avatar, hole cards and name plate.
    private func seatBlockBounds(at anchor: CGPoint) -> CGRect {
        seatBlockBounds(at: anchor, metrics: seatMetrics)
    }

    private func seatBlockBounds(at anchor: CGPoint, metrics: SeatMetrics) -> CGRect {
        let halfWidth = max(Self.refPlate.width * metrics.scale, metrics.cardWidth * 1.55) / 2
        return CGRect(x: anchor.x - halfWidth,
                      y: anchor.y - metrics.blockHeight / 2 - metrics.cardOverhang,
                      width: halfWidth * 2,
                      height: metrics.blockHeight + metrics.cardOverhang)
    }

    private func bubbleBounds(_ seatID: Int) -> CGRect {
        let centre = bubblePosition(seatID)
        return CGRect(x: centre.x - bubbleSize.width / 2, y: centre.y - bubbleSize.height / 2,
                      width: bubbleSize.width, height: bubbleSize.height)
    }

    var bubbleSize: CGSize {
        CGSize(width: Self.refBubble.width * scale, height: Self.refBubble.height * scale)
    }

    /// Just below the seat plate, nudged away from the middle of the table.
    ///
    /// The fitted spot is the whole answer on any felt with room for it, and a
    /// seat that fits keeps it exactly. Where it does not fit the bubble has to
    /// move, because it hangs *below* its plate and the seat arc puts the next
    /// seat around and below that: on a narrow window, or with five seats on a
    /// short felt, the fitted spot lands on the neighbour's hole cards. So it
    /// steps sideways until it is clear — in toward the middle of the table
    /// first, since the neighbour it is dropping onto is always the one further
    /// out, and toward the rail only if the middle is taken too.
    func bubblePosition(_ seatID: Int) -> CGPoint {
        guard seatID > 0 else { return fittedBubblePosition(seatID) }
        if bubbleSpots.indices.contains(seatID - 1) { return bubbleSpots[seatID - 1] }
        return solveBubbleSpot(seatID, avoiding: [])
    }

    private func fittedBubblePosition(_ seatID: Int) -> CGPoint {
        let seat = seatPosition(seatID)
        let metrics = seatMetrics
        return CGPoint(x: clampedBubbleX(seat.x + (seat.x - center.x) * 0.02),
                       y: seat.y + metrics.blockHeight / 2 + bubbleSize.height / 2 + 2 * scale)
    }

    /// A bubble never leaves the window, however crowded the felt gets.
    private func clampedBubbleX(_ x: CGFloat) -> CGFloat {
        let halfWidth = bubbleSize.width / 2
        return min(max(x, halfWidth + 6), size.width - halfWidth - 6)
    }

    /// Places every opponent's bubble in turn, each avoiding the ones already
    /// down — two neighbours whose fitted spots both collide must not escape
    /// onto the same patch of felt.
    private func solveBubbleSpots() -> [CGPoint] {
        guard opponentCount > 0 else { return [] }
        var placed: [CGRect] = []
        var spots: [CGPoint] = []
        for seat in 1...opponentCount {
            let spot = solveBubbleSpot(seat, avoiding: placed)
            spots.append(spot)
            placed.append(bubbleBox(at: spot))
        }
        return spots
    }

    private func bubbleBox(at centre: CGPoint) -> CGRect {
        CGRect(x: centre.x - bubbleSize.width / 2, y: centre.y - bubbleSize.height / 2,
               width: bubbleSize.width, height: bubbleSize.height)
    }

    private func solveBubbleSpot(_ seatID: Int, avoiding placed: [CGRect]) -> CGPoint {
        let home = fittedBubblePosition(seatID)
        guard opponentCount > 0 else { return home }

        // A bubble is *meant* to touch its own seat's plate, so that block is not
        // an obstacle. Everybody else's furniture, the board and the pot are.
        var obstacles = [potBounds, boardBounds]
        for other in 1...opponentCount where other != seatID {
            obstacles.append(seatBlockBounds(at: seatPosition(other)))
        }
        obstacles.append(contentsOf: placed)

        func isClear(_ centre: CGPoint) -> Bool {
            !obstacles.contains { $0.intersects(bubbleBox(at: centre)) }
        }

        if isClear(home) { return home }

        let inward: CGFloat = center.x >= home.x ? 1 : -1
        for step in stride(from: 8.0, through: 60.0, by: 4.0) {
            for direction in [inward, -inward] {
                let candidate = CGPoint(x: clampedBubbleX(home.x + CGFloat(step) * scale * direction),
                                        y: home.y)
                if isClear(candidate) { return candidate }
            }
        }
        // Nothing clear anywhere along the row: sit as far in toward the middle as
        // the search reached. That is the emptiest direction on a crowded table,
        // and it beats leaving the bubble on a neighbour's cards.
        return CGPoint(x: clampedBubbleX(home.x + 60 * scale * inward), y: home.y)
    }

    func dealerButtonPosition(_ seatID: Int) -> CGPoint {
        let seat = seatPosition(seatID)
        let metrics = seatMetrics
        if seatID == 0 {
            return CGPoint(x: center.x - humanHoleWidth / 2 - 18 * scale, y: seat.y - 24 * scale)
        }
        // Beside the avatar, toward the middle — clear of the plate, the bubble
        // (below) and the hole cards (above).
        let sideways = abs(seat.x - center.x) < 30 * scale
            ? -(metrics.avatar * 0.85)
            : (seat.x < center.x ? metrics.avatar * 0.8 : -metrics.avatar * 0.8)
        return CGPoint(x: seat.x + sideways, y: seat.y - metrics.plateHeight * 0.5)
    }

    // MARK: Board, pot, banner

    var boardCardWidth: CGFloat {
        min((tableRect.width - 60) / 5.35, 54) * min(1, scale * 1.10)
    }
    var boardCardHeight: CGFloat { boardCardWidth * 1.42 }
    var boardCenter: CGPoint {
        CGPoint(x: center.x, y: center.y + tableRect.height * 0.13)
    }

    var potHeight: CGFloat { potSize.height }
    /// Declared, not intrinsic, so `PotView` and the bet-placement search agree
    /// on how much room the pot takes up.
    var potSize: CGSize { CGSize(width: 132 * scale, height: Self.refPotHeight * scale) }
    var potBounds: CGRect {
        CGRect(x: potCenter.x - potSize.width / 2, y: potCenter.y - potSize.height / 2,
               width: potSize.width, height: potSize.height)
    }
    var potCenter: CGPoint {
        CGPoint(x: center.x,
                y: boardCenter.y - boardCardHeight / 2 - 5 * scale - potHeight / 2)
    }

    var deckPoint: CGPoint { CGPoint(x: center.x, y: potCenter.y - 18 * scale) }

    /// The open strip between the board and the human's cards. Home to the
    /// human's bet while a hand runs, and to the result banner once it ends —
    /// the two never show at the same time.
    private var resultBand: CGRect {
        let top = boardCenter.y + boardCardHeight / 2
        let bottom = humanCardsCenter.y - humanHoleHeight / 2
        return CGRect(x: tableRect.minX, y: top,
                      width: tableRect.width, height: max(bottom - top, 0))
    }

    var bannerCenter: CGPoint { CGPoint(x: center.x, y: resultBand.midY) }
    var bannerHeight: CGFloat { max(30, min(56, resultBand.height - 10)) }

    // MARK: Human

    var humanCardWidth: CGFloat { min(Self.refHumanCard * scale, tableRect.height * 0.13) }
    private var humanHoleHeight: CGFloat { humanCardWidth * 1.42 }
    private var humanHoleWidth: CGFloat { humanCardWidth * 2 - humanCardWidth * 0.32 }

    var humanCardsCenter: CGPoint { seatPosition(0) }

    var humanPlateCenter: CGPoint {
        CGPoint(x: tableRect.minX + 82,
                y: humanCardsCenter.y + humanHoleHeight / 2 - 24)
    }
}

// MARK: - Game View

struct GameView: View {
    let session: GameSession
    let onExit: () -> Void

    @State private var showQuitConfirm = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var game: PokerGame { session.game }
    private var settings: SettingsStore { SettingsStore.shared }

    var body: some View {
        GeometryReader { geo in
            // Phone-like proportions even on iPad: constrain and centre the play area.
            let contentSize = CGSize(width: min(geo.size.width, 540),
                                     height: min(geo.size.height, min(geo.size.width, 540) * 2.2))
            let layout = TableLayout(size: contentSize, opponentCount: game.players.count - 1)

            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                gameContent(layout: layout)
                    .frame(width: contentSize.width, height: contentSize.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                toastOverlay

                ConfettiView(burst: session.confettiBurst)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()

                if session.showGameOver {
                    GameOverOverlay(session: session, onRematch: { session.rematch() }, onExit: onExit)
                        .transition(reduceMotion ? .opacity
                                    : .opacity.combined(with: .scale(scale: 1.06)))
                }
            }
        }
        .statusBarHidden()
        .onAppear { session.start() }
        .onDisappear { session.stop() }
        // Leaving the foreground is not leaving the table: the game keeps
        // running and this only records where a killed process should resume
        // from. See `GameSession.persistForResume()`.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { session.persistForResume() }
        }
        .confirmationDialog("quit.title", isPresented: $showQuitConfirm, titleVisibility: .visible) {
            Button("quit.leave", role: .destructive) {
                session.stop()
                onExit()
            }
            Button("quit.keepPlaying", role: .cancel) {}
        } message: {
            Text("quit.message")
        }
    }

    private func gameContent(layout: TableLayout) -> some View {
        ZStack {
            feltContent(layout)
                // TableLayout places every piece of furniture with absolute
                // maths fitted for a zero-overlap table, so type on the felt is
                // deliberately fixed. Only on the felt: the chrome below and the
                // overlays above have ordinary layouts and scale normally.
                .dynamicTypeSize(.large)

            TableChrome(game: game, showQuitConfirm: $showQuitConfirm)
                // The chrome is fitted too, but it has room to give — see
                // `ActionBarView.maxDynamicTypeSize` for how much and why.
                .dynamicTypeSize(...ActionBarView.maxDynamicTypeSize)
        }
    }

    private func feltContent(_ layout: TableLayout) -> some View {
        ZStack {
            TableFeltView(rect: layout.tableRect, felt: settings.feltTheme)
                .accessibilityHidden(true)

            communityCardArea(layout)

            PotView(amount: game.pot, scale: layout.scale)
                .position(layout.potCenter)
                // Collapsed first: a bare label on a subtree that publishes
                // several elements of its own is not guaranteed to reach any of
                // them. Same reason as the seats and the human's plate below.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("table.pot \(game.pot.chipText)"))

            seats(layout)

            betStacks(layout)

            if let dealerSeat = dealerVisible {
                let isDead = game.players[dealerSeat].isEliminated
                DealerButtonView(scale: layout.scale, isDead: isDead)
                    // Carries a "D" of its own, which is not what it means.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(isDead ? "a11y.deadButton" : "a11y.dealerButton"))
                    .position(layout.dealerButtonPosition(dealerSeat))
                    .animation(reduceMotion ? nil : .spring(duration: 0.5), value: game.dealerIndex)
            }

            humanArea(layout)

            // Chip flights above everything on the table
            ForEach(session.chipFlights) { flight in
                ChipFlightView(
                    from: resolve(flight.fromSeat, layout: layout, isBetSpot: true),
                    to: resolve(flight.toSeat, layout: layout, isBetSpot: false),
                    amount: flight.amount,
                    scale: layout.scale) {
                    session.removeFlight(flight.id)
                }
            }

            bannerOverlay(layout)
        }
    }

    // MARK: Pieces

    /// The button is shown even when it lands on a knocked-out seat: that is the
    /// dead button, and hiding it would take away position information exactly
    /// when the table is short-handed enough to need it.
    private var dealerVisible: Int? {
        game.handNumber > 0 ? game.dealerIndex : nil
    }

    /// Centre of the i-th board slot.
    private func slot(_ index: Int, width: CGFloat, spacing: CGFloat,
                      totalWidth: CGFloat, layout: TableLayout) -> CGPoint {
        let offset = CGFloat(index) * (width + spacing)
        return CGPoint(x: layout.boardCenter.x - totalWidth / 2 + width / 2 + offset,
                       y: layout.boardCenter.y)
    }

    private func communityCardArea(_ layout: TableLayout) -> some View {
        let width = layout.boardCardWidth
        let spacing: CGFloat = 7
        let totalWidth = width * 5 + spacing * 4
        return ZStack {
            // Placeholder slots
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: width * 0.13)
                    .strokeBorder(Color.white.opacity(0.09), lineWidth: 1.2)
                    .frame(width: width, height: width * 1.42)
                    .position(slot(i, width: width, spacing: spacing, totalWidth: totalWidth, layout: layout))
                    .accessibilityHidden(true)
            }
            ForEach(Array(game.communityCards.enumerated()), id: \.element.id) { i, card in
                let target = slot(i, width: width, spacing: spacing, totalWidth: totalWidth, layout: layout)
                CardFaceView(card: card, width: width, fourColor: settings.fourColorDeck)
                    // A card face is drawn out of separate `Text`s — the two
                    // corner indices and up to ten pips — so without collapsing
                    // it first the spoken name has nothing to attach to and
                    // VoiceOver reads the suit symbol over and over instead.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: card.spokenName))
                    .overlay {
                        if let result = game.handResult, result.wentToShowdown {
                            if result.winningCards.contains(card) {
                                RoundedRectangle(cornerRadius: width * 0.13)
                                    .strokeBorder(Theme.goldBright, lineWidth: 2)
                                    .shadow(color: Theme.goldBright, radius: 6)
                            } else {
                                RoundedRectangle(cornerRadius: width * 0.13)
                                    .fill(Color.black.opacity(0.4))
                            }
                        }
                    }
                    .dealAnimation(from: layout.deckPoint, to: target)
                    .position(target)
            }
        }
    }

    private func seats(_ layout: TableLayout) -> some View {
        ForEach(game.players.filter { !$0.isHuman }) { player in
            let position = layout.seatPosition(player.id)
            OpponentSeatView(
                player: player,
                metrics: layout.seatMetrics,
                isActive: game.activeSeat == player.id,
                isWinner: isWinner(player.id),
                winningCards: game.handResult?.winningCards ?? [],
                deckPoint: layout.deckPoint,
                seatPoint: position,
                fourColor: settings.fourColorDeck)
                .position(position)

            if let action = player.lastAction, !player.isEliminated {
                ActionBubble(label: action, scale: layout.scale)
                    .accessibilityHidden(true)
                    .frame(height: layout.bubbleSize.height)
                    .position(layout.bubblePosition(player.id))
                    .id("\(player.id)-\(action.text)-\(game.handNumber)")
            }
        }
    }

    private func betStacks(_ layout: TableLayout) -> some View {
        ForEach(game.players.filter { $0.betThisStreet > 0 }) { player in
            BetStackView(amount: player.betThisStreet, scale: layout.scale)
                // The chips and the figure beside them are one thing to read,
                // and the figure on its own ("340") says nothing about whose
                // it is — so the stack is collapsed into a single element.
                .accessibilityElement(children: .ignore)
                // Your own seat is named "You", which no sentence about a third
                // party fits: "You bets 340". It gets its own phrasing, and the
                // opponents' is present tense because Czech inflects a past
                // participle for gender and a name does not say which to use —
                // "Rosa vsadil" for two of the six profiles in the roster.
                .accessibilityLabel(player.isHuman
                    ? Text("a11y.yourBet \(player.betThisStreet.chipText)")
                    : Text("a11y.betOf \(player.name) \(player.betThisStreet.chipText)"))
                .position(layout.betPosition(player.id))
                .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
                .animation(reduceMotion ? nil : .spring(duration: 0.35), value: player.betThisStreet)
        }
    }

    private func isWinner(_ seatID: Int) -> Bool {
        guard let result = game.handResult else { return false }
        return (result.winnings[seatID] ?? 0) > 0
    }

    // MARK: Human area

    private func humanArea(_ layout: TableLayout) -> some View {
        let human = game.players[game.humanSeat]
        let cardWidth = layout.humanCardWidth

        return ZStack {
            // Hole cards
            HStack(spacing: -cardWidth * 0.32) {
                ForEach(Array(human.holeCards.enumerated()), id: \.element.id) { index, card in
                    HumanHoleCardView(card: card, width: cardWidth, fourColor: settings.fourColorDeck)
                        // Same as the board: collapse the face into one element
                        // before naming it.
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(verbatim: card.spokenName))
                        .rotationEffect(.degrees(index == 0 ? -5 : 5))
                        .overlay {
                            if let result = game.handResult, result.wentToShowdown, human.isInHand,
                               result.winningCards.contains(card) {
                                RoundedRectangle(cornerRadius: cardWidth * 0.13)
                                    .strokeBorder(Theme.goldBright, lineWidth: 2.5)
                                    .shadow(color: Theme.goldBright, radius: 7)
                            }
                        }
                        .dealAnimation(from: layout.deckPoint, to: layout.humanCardsCenter)
                }
            }
            .opacity(human.hasFolded ? 0.35 : 1)
            .position(layout.humanCardsCenter)

            // Info plate: name + chips
            HStack(spacing: 8) {
                Text(human.emoji)
                    .font(.system(size: 20))
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: human.name)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.cream)
                    Text(human.chips.chipText)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.goldBright)
                        .contentTransition(reduceMotion ? .identity
                                           : .numericText(value: Double(human.chips)))
                        .animation(reduceMotion ? nil : .spring(duration: 0.5), value: human.chips)
                }
                if human.isAllIn {
                    Text("label.allIn")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.allInRed))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.55))
                    .overlay(Capsule().strokeBorder(
                        game.activeSeat == game.humanSeat ? Theme.goldBright : Color.white.opacity(0.12),
                        lineWidth: game.activeSeat == game.humanSeat ? 2 : 1)))
            .shadow(color: game.activeSeat == game.humanSeat ? Theme.goldBright.opacity(0.5) : .clear, radius: 7)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("a11y.yourStack \(human.chips.chipText)"))
            .position(layout.humanPlateCenter)
        }
    }

    // MARK: Overlays

    @ViewBuilder
    private func bannerOverlay(_ layout: TableLayout) -> some View {
        if let result = game.handResult, !session.showGameOver {
            HStack(spacing: 7) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.goldBright)
                Text(verbatim: result.headline)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.cream)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 18)
            .frame(height: layout.bannerHeight)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.78))
                    .overlay(Capsule().strokeBorder(Theme.gold.opacity(0.7), lineWidth: 1.5)))
            .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
            .frame(maxWidth: layout.tableRect.width - 40)
            .position(layout.bannerCenter)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
            .id(game.handNumber)
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = session.toast {
            Text(verbatim: toast)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.85))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Capsule().fill(Theme.goldBright))
                .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 96)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
        }
    }

    private func resolve(_ seat: Int?, layout: TableLayout, isBetSpot: Bool) -> CGPoint {
        guard let seat else { return layout.potCenter }
        return isBetSpot ? layout.betPosition(seat) : layout.seatPosition(seat)
    }
}

// MARK: - Table chrome

/// Everything drawn above and below the felt: the top bar, the hand-strength
/// HUD and the action bar.
///
/// Its own view rather than three helpers on `GameView`, so that `@ScaledMetric`
/// in here reads the Dynamic Type size the chrome is allowed rather than the one
/// the felt is pinned to.
private struct TableChrome: View {
    let game: PokerGame
    @Binding var showQuitConfirm: Bool

    /// One metric drives every size in the chrome, so the proportions it was
    /// fitted with survive Dynamic Type. 100 → percent of the fitted size.
    @ScaledMetric(relativeTo: .body) private var typeScale: CGFloat = 100
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var settings: SettingsStore { SettingsStore.shared }
    private func scaled(_ size: CGFloat) -> CGFloat { size * typeScale / 100 }

    var body: some View {
        VStack(spacing: 6) {
            topBar
            handStrengthBar
            Spacer()
            ActionBarView(game: game)
        }
        // The engine stops estimating the odds while they are hidden, so
        // switching them back on has to ask for a fresh number rather than wait
        // for the next street. Switching them off cancels the estimate in
        // flight. See `PokerGame.oddsProvider`.
        .onChange(of: settings.showOdds) { _, _ in game.refreshHumanEquity() }
    }

    private var topBar: some View {
        HStack {
            Button {
                Haptics.tap()
                showQuitConfirm = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: scaled(15), weight: .bold))
                    .foregroundStyle(Theme.cream.opacity(0.8))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .accessibilityLabel(Text("a11y.leaveTable"))

            Spacer()

            VStack(spacing: 1) {
                Text("topBar.hand \(game.handNumber)")
                    .font(.system(size: scaled(11), weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.subtleText)
                Text("topBar.blinds \(game.blindLevel.smallBlind.chipText) \(game.blindLevel.bigBlind.chipText)")
                    .font(.system(size: scaled(13), weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.gold)
            }

            Spacer()

            Button {
                settings.soundEnabled.toggle()
                Haptics.tap()
            } label: {
                Image(systemName: settings.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: scaled(14), weight: .semibold))
                    .foregroundStyle(Theme.cream.opacity(0.8))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .accessibilityLabel(Text(settings.soundEnabled ? "a11y.muteSound" : "a11y.unmuteSound"))
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .accessibilityElement(children: .contain)
    }

    /// Your hand strength and odds. Sits under the top bar rather than beside your
    /// cards so the raise panel can never cover it.
    @ViewBuilder
    private var handStrengthBar: some View {
        let human = game.players[game.humanSeat]
        if human.isInHand, !human.holeCards.isEmpty, game.isHandInProgress {
            HStack(spacing: 6) {
                if let label = game.humanHandLabel {
                    Text(label)
                        .font(.system(size: scaled(11), weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(Theme.cream)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.5)))
                }
                if settings.showOdds, let equity = game.humanEquity {
                    Text("hud.winChance \(Int((equity * 100).rounded()))")
                        .font(.system(size: scaled(11), weight: .heavy, design: .rounded))
                        .foregroundStyle(equity > 0.5 ? Color(red: 0.45, green: 0.85, blue: 0.5) : Theme.cream.opacity(0.85))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.5)))
                        .contentTransition(reduceMotion ? .identity : .numericText())
                }
            }
            .transition(.opacity)
        }
    }

}

// MARK: - Human hole card (deals face-down, then flips up)

struct HumanHoleCardView: View {
    let card: Card
    let width: CGFloat
    var fourColor: Bool

    @State private var revealed = false

    var body: some View {
        FlipCardView(card: card, faceUp: revealed, width: width, fourColor: fourColor)
            .task {
                try? await Task.sleep(for: .milliseconds(420))
                revealed = true
            }
    }
}

// MARK: - Table felt & rim

struct TableFeltView: View {
    let rect: CGRect
    let felt: FeltTheme

    var body: some View {
        let cornerRadius = min(rect.width, rect.height) * 0.44

        ZStack {
            // Outer rim (wood)
            RoundedRectangle(cornerRadius: cornerRadius + 10)
                .fill(
                    LinearGradient(colors: [
                        Color(red: 0.32, green: 0.20, blue: 0.11),
                        Color(red: 0.19, green: 0.11, blue: 0.06),
                    ], startPoint: .top, endPoint: .bottom))
                .frame(width: rect.width + 22, height: rect.height + 22)
                .shadow(color: .black.opacity(0.6), radius: 18, y: 8)

            RoundedRectangle(cornerRadius: cornerRadius + 4)
                .strokeBorder(Theme.gold.opacity(0.5), lineWidth: 1.5)
                .frame(width: rect.width + 8, height: rect.height + 8)

            // Felt
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    RadialGradient(colors: [felt.center, felt.edge],
                                   center: .center,
                                   startRadius: rect.width * 0.1,
                                   endRadius: rect.height * 0.62))
                .frame(width: rect.width, height: rect.height)

            // Inner betting line
            RoundedRectangle(cornerRadius: cornerRadius * 0.72)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1.5)
                .frame(width: rect.width - 72, height: rect.height - 72)

            Text(verbatim: "♠ ACE HIGH ♠")
                .font(.system(size: 13, weight: .black, design: .serif))
                .kerning(3)
                .foregroundStyle(Color.white.opacity(0.07))
                .offset(y: -rect.height * 0.26)
        }
        .position(x: rect.midX, y: rect.midY)
    }
}
