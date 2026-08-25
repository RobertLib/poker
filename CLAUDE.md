# Working in this repo

"Ace High" — an offline No-Limit Hold'em game for iOS. SwiftUI, no dependencies,
no network, no bundled assets. See [README.md](README.md) for the source layout
and the QA launch arguments.

## Always run the tests

```sh
xcodebuild test -project poker.xcodeproj -scheme poker \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Check which simulators exist before picking one — `xcodebuild -list` names the
scheme, and the destination list in the error output names the devices. Note that
piping `xcodebuild` into `tail`/`grep` gives you *that* command's exit status, so
capture the log and check `$?` separately or a failing run will look green.

The suite is not a formality here: the poker rules, the table geometry and both
localisations are all specified by tests rather than by prose. A change to
`Engine/`, `AIBrain` or `TableLayout` that you have not run the tests on is
unverified.

## TableLayout is fitted first, then solved

`TableLayout` in [poker/Views/GameView.swift](poker/Views/GameView.swift) derives
every position on the felt from one rectangle. Its constants were tuned as a set,
so changing one moves seats, bets, bubbles, the board and the banner together.

The fitted constants are the answer on every real device, but they are not the
whole layout: four things are **solved** in `init`, in this order, and each one
depends on the last.

| Solver | What it does | When it deviates from the fit |
|---|---|---|
| `solveScale` | gives up scale until the seat blocks clear each other | window too short for the arc |
| `solveSeatPosition` | pulls a seat inward until its cards are on the felt | crowded arc, small felt |
| `solveBubbleSpots` | steps a bubble sideways, in toward the middle first | bubble would land on the next seat's cards |
| `solveBetSpots` | walks the seat→pot line for a clear spot for the chips | corridor blocked by furniture or the pot |

Every solver returns the fitted answer untouched when the fitted answer already
clears. That is the property to preserve: **a change must not move anything on a
table that already fits.** `nothingOverlapsOnAnyReachableWindow` sweeps every
window from 320×320 (the smallest iPadOS can produce) to the 540pt width cap, at
every seat count, and demands genuine non-overlap rather than a tolerance —
there used to be a band from 380 to 400pt wide where seat 1's block bit 12×6pt
out of seat 2's bubble, and iPhone SE with five opponents cleared by 0.18pt.

- `TableLayoutTests` is the arbiter — run it, don't eyeball the simulator.
- To check you have not reshuffled a table that was already fine, dump every
  number the layout publishes for the five device sizes before and after and
  diff them. Expect zero differences; a difference is only ever acceptable where
  the sweep says the old numbers overlapped.
- Below 320×320 the layout degrades rather than guarantees: `solveBetSpot` falls
  back to the least-crowded spot it saw, scored by area. Don't chase those sizes;
  the system cannot hand us one.

## The AI is stochastic

`AIBrain` estimates equity by Monte Carlo and adds difficulty noise, so any test
that counts its decisions is a statistical test. Assert on outcomes with real
headroom (both sides pinned) rather than comparing two counts that can both land
on zero — that is what made `aMarginalHandRespectsANarrowRange` flaky before.

To measure the AI without the simulator in the way, `Card`, `HandEvaluator`,
`GameModels`, `Localization` and `AIBrain` compile standalone:

```sh
swiftc -O -o /tmp/aicheck main.swift \
  poker/Models/Card.swift poker/Models/HandEvaluator.swift \
  poker/Models/GameModels.swift poker/Support/Localization.swift \
  poker/Engine/AIBrain.swift
```

## App Store media is generated from real hands

`AppStore/` holds the store texts; `Tools/appstore_media.sh` builds the
screenshots and the App Preview from the `-shot <name>` poses in
`poker/Support/ScreenshotScenes.swift` (all `#if DEBUG`). A pose is a real hand
dealt from a stacked deck against a scripted opposition — it uses the engine's
existing test hooks plus `aiActionOverride`, which answers for the AI seats only
so your turn still goes through the ordinary human path.

- Poses are keyed by **street, never by turn order**. Turn order depends on the
  button, on who folded and on whether a raise reopened the action, so a
  positional script photographs the wrong moment as soon as any of that changes.
- The app signals when a pose is on screen (`Shots.markReady`) and the script
  waits for that marker. Do not replace it with a sleep; the arrival time differs
  per pose, per device and per game speed.
- A new scene must mark itself ready, or the run stops with
  `pose never became ready`.
- Read `AppStore/screenshots.md` before touching any of it — the Apple
  specifications in there each cost an upload to learn.

## Conventions

- The engine owns the rules and never imports SwiftUI. `Engine/` and `Models/`
  are `nonisolated` value types plus one `@MainActor @Observable` class.
- Every user-facing string goes through the string catalog. Czech inflects, so
  ranks take a `RankForm` and suits agree with the rank's gender — don't
  concatenate. Multi-placeholder formats must be positional.
- Comments explain *why* a constant or a branch is the way it is, especially
  where a poker rule or a fitted number is non-obvious. Match that density.
- `snapshot()` is written at hand boundaries by `GameSession` and mid-hand when
  you leave the table, where committed chips are deliberately forfeit. The same
  forfeit is written when the app leaves the foreground (`scenePhase`), because
  SwiftUI does not call `onDisappear` for that and a process the system kills
  while suspended would otherwise resume from the previous hand boundary —
  handing the abandoned hand back.
  `backgroundingMidHandCannotRewindToTheLastHandBoundary` is what holds it shut.
- Accessibility has two rules the fitted layout makes non-obvious:
  - **Reduce Motion.** Anything that moves reads
    `\.accessibilityReduceMotion` and substitutes a cross-fade, or nothing.
    That covers every `.transition(.move/.scale)`,
    `contentTransition(.numericText)` and always-on `TimelineView`; `Motion` in
    `Theme.swift` serves the two places with no environment to read. New
    animation needs the same treatment.
  - **Dynamic Type.** Only the felt is pinned — `.dynamicTypeSize(.large)` on
    `feltContent`, whose positions are absolute. `TableChrome` scales up to
    `ActionBarView.maxDynamicTypeSize` and the overlays are not pinned at all.
    Every chrome size derives from one `@ScaledMetric`, so the fitted
    proportions survive; its footprint under the felt is
    `ActionBarView.barHeight` + `panelHeight`, which `TableLayoutTests` reads
    rather than restates. Don't pin a wider subtree than the maths requires.
