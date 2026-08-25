# Ace High

An offline No-Limit Texas Hold'em game for iPhone and iPad. SwiftUI, no
dependencies, no network, no assets — the sounds are synthesized at launch and
the cards are drawn with shapes.

You play one seat against up to five AI opponents with distinct personalities,
in a tournament that runs until somebody owns every chip.

## Requirements

- Xcode with an iOS 17 SDK or newer (`IPHONEOS_DEPLOYMENT_TARGET = 17.0`)
- Swift 6 language mode

```sh
open poker.xcodeproj
```

## Tests

```sh
xcodebuild test -project poker.xcodeproj -scheme poker \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

The suite is where the rules actually live, so run it before trusting a change
to the engine, the AI or the table layout:

| Suite | What it pins down |
|---|---|
| Hand evaluator | Every category, kickers, the wheel, and a brute-force cross-check |
| Betting rules | Min-raise tracking, incomplete all-ins, refunds, split pots, side pots |
| Button and blinds | Dead button and dead small blind as players bust out |
| Engine invariants under fuzzing | Whole games of adversarial and illegal input: chips conserved, every pot paid out, no card dealt twice |
| Saving and resuming | Snapshot round-trips, busted seats, mid-hand forfeit |
| AI equity / AI decisions | Monte Carlo equity against known numbers; the AI plays legally and is neither a rock nor a station |
| Odds estimation | The win-probability simulation runs when the HUD shows it and not when it doesn't |
| Table layout | Zero overlap on every screen size and seat count |
| Chip formatting | Abbreviations, and a decimal separator that follows the region |
| Localisation | Both languages ship every key, with matching format placeholders |

## Layout

`TableLayout` in `poker/Views/GameView.swift` derives every position on the felt
from one rectangle. The constants in it were **fitted, not guessed** — nudging
one shifts seats, bets, bubbles, the board and the banner all at once.

The fit is what every real device gets. Where it runs out of room — a narrow iPad
tile, or five seats on a window dragged short — four solvers take over in turn:
the furniture gives up scale until the seats clear each other, a seat is pulled
inward until its cards are on the felt, a bubble steps sideways rather than hang
over the next seat's cards, and the chips walk the line to the pot looking for a
gap. Each one returns the fitted answer untouched when the fitted answer already
works, so a table that fits is never rearranged.

`TableLayoutTests` is what tells you whether that still holds. It sweeps every
window the system can produce — 320×320 up to the 540pt width cap, at every seat
count — and demands real non-overlap, not a tolerance. Run it rather than
eyeballing the simulator.

## Localisation

English and Czech, in `poker/Localizable.xcstrings`. Czech inflects, so ranks and
suits are not single strings: `RankForm` asks for the grammatical case a sentence
needs and `Suit.name(agreeingWith:)` agrees with the rank's gender. Poker jargon
(`Check`, `Flop`, `Turn`, `River`, `Pot`, `All-in`, `SB`/`BB`) stays English in
Czech, because that is what Czech players say.

Multi-placeholder formats must be positional (`%1$@`, `%2$@`) — Czech reorders
them, and `LocalizationTests` fails the build if a translation drops, adds or
un-positions one.

## QA launch arguments

Pass these as scheme arguments to jump straight to a screen or a rigged table:

| Argument | Effect |
|---|---|
| `-qa-game` | Deal in immediately with the default table |
| `-qa-headsup` / `-qa-full` | One opponent / five opponents |
| `-qa-stacked` | Lopsided stacks and turbo blinds, for side pots and bust-outs |
| `-qa-autopilot` | Auto-plays your seat so whole hands run without touch input |
| `-qa-raise` | Opens the bet-sizing panel on your turn |
| `-qa-setup` / `-qa-rules` / `-qa-stats` / `-qa-settings` | Open that screen |

These are Debug-only, like `-shot` below: launch arguments cannot reach a
shipped app, so none of it is built into a Release binary.

`-shot <name>` deals a *named* hand instead: a fixed deck, a pinned
button, known stacks and a scripted opposition, stopping on the street being
photographed. That is what the App Store media is made of — see
[AppStore/screenshots.md](AppStore/screenshots.md) for the catalogue and
[poker/Support/ScreenshotScenes.swift](poker/Support/ScreenshotScenes.swift) for
the poses.

## App Store submission

Everything needed to put the app on the store lives in [AppStore/](AppStore/) —
the texts for all three localisations, the privacy policy, the note for the
reviewer, and what to tick in App Store Connect (including why the age rating is
18+ and not a choice). [AppStore/README.md](AppStore/README.md) is the checklist;
[AppStore/alternatives.md](AppStore/alternatives.md) has the ASO reasoning and
spare copy.

The screenshots and the App Preview are generated, not committed:

```sh
Tools/appstore_media.sh       # screenshots and videos
Tools/appstore_captions.sh    # captions onto the finished screenshots
```

## Layout of the source

```
poker/
  Engine/    PokerGame (the rules), PotBuilder (side pots), AIBrain (equity + personality)
  Models/    Card, HandEvaluator, and the value types the engine speaks in
  Support/   Localization, Theme, SettingsStore/SavedGameStore/StatsStore, SoundManager,
             ScreenshotScenes (Debug only — the App Store poses)
  Views/     GameView + TableLayout, the seats, cards, chips, menus and overlays
AppStore/    App Store Connect texts, privacy policy, reviewer notes
Tools/       screenshot and App Preview generation
```

The engine owns the rules and drives itself through an async loop; it publishes
observable state and emits `GameEvent`s. `GameSession` turns those events into
sounds, haptics, chip flights and statistics, and snapshots the game so it
survives leaving the table. Nothing in `Engine/` or `Models/` imports SwiftUI.
