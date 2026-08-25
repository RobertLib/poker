# Screenshots and App Preview

The media is **not made by hand and is not in git** — the scripts below produce
it. Uploading is manual: in App Store Connect drag the files into the *App
Preview and Screenshots* section (language switch at the top, one locale at a
time).

## What the scripts produce

| What | Where | Resolution | Count |
|---|---|---|---|
| iPhone 6.9" screenshots | `screenshots/<locale>/iphone-6.9/` | 1320 × 2868 | 8 |
| iPhone 6.5" screenshots | `screenshots/<locale>/iphone-6.5/` | 1242 × 2688 | 8 |
| iPad 13" screenshots | `screenshots/<locale>/ipad-13/` | 2064 × 2752 | 8 |
| The same with captions | `screenshots-captioned/<locale>/<device>/` | same | 8 + 8 + 8 |
| iPhone App Preview | `preview/<locale>/iphone-6.9.mp4` | 886 × 1920, 30 fps, 22.1 s, AAC | 1 |
| iPad 13" App Preview | `preview/<locale>/ipad-13.mp4` | 1200 × 1600, 30 fps, 22.1 s, AAC | 1 |

**Upload the set that matches the slot Connect is showing you.** The iPhone
screenshot slot is chosen per upload, and it rejects a file of the other slot's
size out of hand — `iphone-6.9/` goes into *iPhone 6.9" Display*, `iphone-6.5/`
into *iPhone 6.5" Display*, and neither substitutes for the other. The App
Preview has no such split: the one 886 × 1920 file is what Apple lists for the
6.9", 6.5", 6.3" and 6.1" displays alike, so `iphone-6.9.mp4` is the video for
every iPhone slot in spite of its name.

The locales are `cs` and `en-US`, everything in portrait. `en-GB` gets no media of
its own — upload the `en-US` set into it.

```bash
Tools/appstore_media.sh              # screenshots and videos
Tools/appstore_media.sh screenshots  # screenshots only (~8 min)
Tools/appstore_media.sh video        # videos only (~10 min)
Tools/appstore_captions.sh           # paints captions onto finished screenshots (~1 min)
```

**Upload either the captioned set or the plain one** — both have the same file
names and order, they differ only in the band at the top. Captions are not
compulsory, but they lift conversion, and for this app they are where the "no ads,
no purchases" promise gets to be said out loud.

`appstore_media.sh` needs Xcode, the *iPhone 17 Pro Max* and *iPad Pro 13-inch
(M5)* simulators, ImageMagick (`brew install imagemagick`) and Python 3 (for the
preview's music bed). The third device, *iPhone 11 Pro Max*, is the 6.5" one —
Xcode ships the device type but not a ready-made simulator for it, so the script
creates it on the newest installed runtime the first time it needs it and leaves
it there. It builds Debug, because everything it drives lives under
`#if DEBUG`. `appstore_captions.sh` only repaints finished PNGs and needs neither
a simulator nor a build.

The screenshots are 8-bit PNGs with no alpha channel (the simulator writes one
even when every pixel is opaque, and App Store Connect does not want
transparency) and have been through a lossless recompression — verified with
`magick compare -metric AE` = 0, and anything that does not compare identical is
left as it came out.

### Why it is not in git

Around 200 MB of images and video are output, not source — the source is this
description, the scripts in `Tools/` and the shot catalogue in
[`poker/Support/ScreenshotScenes.swift`](../poker/Support/ScreenshotScenes.swift).
A PNG is already compressed, so git cannot shrink it and it would stay in the
history for good.

App Store Connect keeps the record of what was actually shipped with each
version. If you ever need the exact files locally as well, attach them as a ZIP
to the release on the matching tag — that keeps them out of the repository
history.

## What Apple requires

The app targets iPhone and iPad (`TARGETED_DEVICE_FAMILY = "1,2"`), so **two
sets** of screenshots are mandatory. Apple derives every smaller size itself.

| Slot | Resolution (portrait) | Count |
|---|---|---|
| **iPhone 6.9"** ← what we upload | 1260 × 2736, 1290 × 2796 or **1320 × 2868** | 1–10 |
| **iPhone 6.5"** ← what we upload | 1284 × 2778 or **1242 × 2688** | 1–10 |
| **iPad 13"** ← what we upload | **2064 × 2752** or 2048 × 2732 | 1–10 |

Only one iPhone set is compulsory, but **"Apple derives the smaller sizes" does
not mean the slots are interchangeable at upload time.** It derives what the
store *page* shows on a smaller phone; the slot you are dragging into still takes
its own sizes and nothing else, so a 1320 × 2868 file dropped on the 6.5" slot is
refused with "the dimensions are wrong" and no hint that the file is fine and the
slot is the mismatch. Shooting both sizes costs one extra pass and removes the
question.

Every simulator records its slot size natively — 1320 × 2868, 1242 × 2688 and
2064 × 2752 are all on Apple's accepted list — so **nothing here is scaled or
cropped**, and the script fails loudly if a capture comes out at another size
rather than quietly resampling it. That is the whole reason those three devices
are named and not any others: 6.9" and 6.5" are not the same aspect ratio
(0.4602 against 0.4621), so a resize between them cannot be anything but a crop
or a squash.

PNG or JPEG, no transparency, no rounded corners, no device frame (a frame is
allowed, but it has to be part of the image and must not cover the content).
They are ordered the way you upload them — **the first two are all most people
will ever see** in search results, which is why they are the table and the
showdown rather than the menu.

The App Preview is optional, and its specification is stricter than the one for
screenshots — every line of it is enforced on upload, so it is worth reading as a
checklist rather than as advice:

| | |
|---|---|
| Resolution | **iPhone 886 × 1920, iPad 13" 1200 × 1600** (portrait) |
| Video | H.264 **High Profile Level 4.0**, progressive, 30 fps — or ProRes 422 HQ |
| Bit rate | 10–12 Mbps VBR (H.264) |
| Audio | stereo AAC, **256 kbps**, 44.1 or 48 kHz — **required** |
| Length | 15–30 s, at most 500 MB, `.mp4` / `.m4v` / `.mov` |

Three of those cost an upload each to learn. **The preview is not the device's own
resolution** — 886 × 1920 is the accepted portrait size, and a file at 1320 × 2868
is refused however good it looks. One thing that is *not* a trap: unlike the
screenshots, the video does not care which iPhone slot it goes into. Apple lists
886 × 1920 for the 6.9", 6.5", 6.3" and 6.1" displays alike, so the same file
serves all of them. **Level 4.0 is a ceiling**: at the device's resolution the
encoder has to reach Level 5.0, which is out of spec on its own. And audio is the
third: the simulator records none, and Connect treats a file with no usable audio
as an unsupported audio *configuration* — which is why the error it reports
mentions audio even when the real problem is the picture. A silent track does not
buy you out of it either, because AAC compresses digital silence to about 2 kbps
against the 256 kbps asked for.

Which is a problem for this app in particular, because **Ace High ships no audio
at all** — the sound effects are synthesised at launch, so there is no track in
the bundle to put under the trailer. Hence
[`Tools/gen_preview_music.py`](../Tools/gen_preview_music.py), which synthesises
one in the same spirit: a slow ii-V-I-VI in D minor at 76 BPM, Rhodes-ish tines
over a plucked bass with a brushed shaker, mixed quiet and dull on purpose so it
sits under the chips and cards rather than over them. It is ours, so there is
nothing to attribute and no licence to carry.
[`Tools/appstore_conform.swift`](../Tools/appstore_conform.swift) loops it under
the cut and pins every row of the table above.

## The set (8 images)

The order is also the upload order. Each name is a scene in the catalogue in
[`ScreenshotScenes.swift`](../poker/Support/ScreenshotScenes.swift), and the
arguments can be entered by hand in Xcode too: **Product → Scheme → Edit Scheme →
Run → Arguments → Arguments Passed On Launch**.

| # | File | What is on screen | Arguments |
|---|---|---|---|
| 1 | `01-table` | Six seats, 960 in the pot, facing a 380 bet on the turn holding the ace-high flush | `-shot 01-table` |
| 2 | `02-showdown` | Kings full of nines takes 4,120; winning cards lit, confetti up | `-shot 02-showdown` |
| 3 | `03-raise` | The bet panel open on the flop — slider, ½ / ¾ / Pot, All-In. Sapphire felt | `-shot 03-raise -qa-raise` |
| 4 | `04-setup` | New game: five opponents with their taglines, difficulty, stacks, blinds | `-shot 04-setup` |
| 5 | `05-allin` | Rex shoves 3,520 into your aces. Garnet felt, four-colour deck | `-shot 05-allin` |
| 6 | `06-rules` | How to Play: Hold'em in sixty seconds, your moves, hand rankings in cards | `-shot 06-rules` |
| 7 | `07-stats` | Statistics, filled in | `-shot 07-stats` |
| 8 | `08-menu` | The main menu, with a game to continue and "Offline · No ads · Just poker" | `-shot 08-menu` |

Between them the eight cover the ace-high flush the app is named after, a
showdown, bet sizing, an all-in, the table setup, the rules reference, the
statistics and the promise — three different felts and both deck styles, so the
set is not eight pictures of the same green oval.

### How a pose is built, and why it is not a mock

Each scene is a *real hand of poker* that happens to be dealt the same way every
time. It is assembled only from hooks the engine already exposes to the tests:

| Hook | What the pose uses it for |
|---|---|
| `deckProvider` + `Deck(stacked:)` | the exact hole cards and runout |
| `_setDealerForTesting(before:)` | pins the button, so the deal order is known |
| `PokerGame(config:restoring:)` | the stacks, and the hand number that picks the blind level |
| `aiActionOverride` | scripts the opposition, street by street |

The one thing added for this was `aiActionOverride`, which answers for the AI
seats *only* — your turn still goes through the ordinary human path, so the action
bar appears and waits exactly as it would for a real tap. That is what makes shots
1, 3 and 5 possible at all.

Two consequences worth knowing before you edit a pose:

- **Everything is keyed by street, never by turn order.** Turn order depends on
  the button, on who has folded, and on whether a raise reopened the action. A
  positional script would quietly photograph the wrong moment the first time any
  of that changed. Unscripted seats check if they can and call if they cannot —
  never fold, because a pose that folds itself out photographs an empty table.
- **A pose that stops being legal stops rendering**, which is the point. The
  engine sanitises illegal requests, so if a rule change makes a scripted raise
  impossible the shot changes visibly rather than becoming subtly wrong.

Deck slots are worked out from the deal: the engine deals two passes starting to
the left of the button and takes no burn cards, so with `n` seats a seat `s` gets
slots `o` and `n + o`, where `o` is how far it sits after the button, and the
board follows at `2n`. Slots nobody asked for are filled from the rest of the deck
in a fixed order. For a pose that reaches a showdown, **specify every seat's hole
cards** — otherwise a filler hand can beat yours and the banner says something
else.

### Why the script never sleeps for a guess

A posed hand takes as long to arrive as the deal, the blinds and two streets of
betting take, which is a different length on every pose, on every device and at
every game speed. Sleeping for a fixed time is how you get a screenshot of the
flop when you wanted the turn — which is exactly what happened while this was
being built.

So the app tells the script when it is ready: `Shots.markReady()` drops
`Documents/shot-ready` in the app container once the moment being photographed is
actually on screen, after a short delay for the last animation to land, and
`wait_ready` in `appstore_media.sh` polls for it with a 90 s timeout. Table shots
report in 9–20 s, menus and sheets in 2–3 s.

The consequence for editing: **a new scene has to mark itself ready**, or the
script waits 90 s and then stops with `pose never became ready`. Poses that hold
on a street do it from `.humanTurn`; poses that play to the end do it from
`.handFinished`.

## Captions on the images

[`Tools/appstore_captions.sh`](../Tools/appstore_captions.sh) makes them from the
plain set into `screenshots-captioned/`.

Layout: a band of text at the top, below it the shrunken screenshot on the same
near-black the app's own background gradient starts from (`Theme.backgroundTop`),
with a hairline gold border and a soft shadow. The game shot is scaled, never
cropped — so neither the blinds header at the top nor the action bar at the bottom
loses anything. Sizes are proportional to the image, so the iPhone and iPad
versions are laid out the same way.

The text is Arial Bold, given as a **file path and not a font name**: the Homebrew
ImageMagick has no fontconfig type map, so `-font Arial-Bold` fails, drops the
caption, and still exits 0. It is also the only bold face on a stock macOS with
complete Czech diacritics — Arial Rounded Bold has neither `ť` nor `ě`, and SF
only renders in regular through ImageMagick.

| # | English | Czech |
|---|---|---|
| 1 | Real No-Limit Hold'em. Offline. | Opravdový No-Limit Hold'em. Offline. |
| 2 | Win it with the best five cards. | Vyhraj to nejlepší pěticí karet. |
| 3 | Bet any size you like. Or shove. | Sázej, kolik chceš. Nebo všechno. |
| 4 | Six opponents, six styles. | Šest soupeřů, šest stylů. |
| 5 | Side pots, split pots, dead button. | Side poty, dělené poty, dead button. |
| 6 | All ten hands, drawn out in cards. | Všech deset kombinací, vykreslených kartami. |
| 7 | Every hand you have ever played. | Každé rozdání, cos kdy zahrál. |
| 8 | No ads. No purchases. Ever. | Bez reklam. Bez nákupů. Nikdy. |

The line breaks are written by hand in the `en_caption` / `cs_caption` functions,
so that no single word is left hanging on the second line. The arc is deliberate:
open on what the app is, close on what it does not do.

## App Preview (video)

Pure gameplay, no logo and no title cards — it opens on the cards being dealt,
because the first few seconds are what decide. Five cuts, 22.1 s:

| # | Clip | Window | What is on screen |
|---|---|---|---|
| 1 | `p1-hand` | 1.5–6.5 | the deal itself, then the pre-flop betting at a full table |
| 2 | `p1-hand` | 9.6–15.1 | the flop and the turn, with chips going in |
| 3 | `p1-hand` | 19.2–22.0 | the showdown: cards up, pot pushed, confetti |
| 4 | `p2-allin` | 6.6–13.6 | a shove into your aces and the runout |
| 5 | `p3-menu` | 2.0–3.8 | the menu, closing on "Offline · No ads · Just poker" |

Two of those numbers are the way they are because of mistakes worth not
repeating. **The showdown clip is short on purpose** — the confetti flies for
about two seconds and then the banner just sits there, so the five-second window
it started as spent three of them on a still picture. And **nothing may reach past
about 21 s into a recording**: the files report ~30 s, but the tail is not
reliably decodable, and a range that crosses it is clamped, leaving the finished
preview holding a single frame for the difference while every step in the chain
reports success.

Both hands play themselves: `preview-hand` and `preview-allin` have no `holdAt`,
so your seat calls its way to the showdown and the whole thing runs without touch
input. Both are dealt from a stacked deck against a scripted opposition, so the
timeline is the same on every run — which is why the cut points above still line
up after a regeneration. The iPad has its own points, because it reaches each
state a little sooner than the iPhone.

Every window is chosen to hold something *moving* from its first frame to its
last: cards being dealt, chips flying, the board coming out, the pot being
pushed. **After any change to pacing, to the poses or to the animations, extract
the first and last frame of each window and look at them before uploading.**
Nothing here fails loudly — a stale window just goes still, and a pose that has
been re-scripted simply shows something else.

[`Tools/appstore_frames.swift`](../Tools/appstore_frames.swift) pulls the frames
out — a tool rather than a line of `ffmpeg`, because ffmpeg is not installed on a
stock macOS and this needs nothing that is not already here. Point it at the
finished preview and read the cut boundaries off the running total (0, 5.0, 10.5,
13.3, 20.3, 22.1):

```bash
swift Tools/appstore_frames.swift AppStore/preview/en-US/iphone-6.9.mp4 \
    /tmp/frames 0.2 4.8 5.2 10.3 10.7 13.1 13.5 20.1 20.5 22.0
magick montage /tmp/frames/*.png -tile 5x -geometry 250x+6+6 \
    -font "/System/Library/Fonts/Supplemental/Arial Bold.ttf" /tmp/sheet.png
```

Or at a raw clip in `$WORK/clips/<device>-<locale>/`, which is where the windows
are actually chosen.

The simulator records at ~72 fps, which App Store Connect rejects;
[`Tools/appstore_video.swift`](../Tools/appstore_video.swift) recuts the
recording, scales it to the target resolution and exports H.264 at 30 fps.

What comes out of that step is the right size and nothing else Connect wants: the
export preset picks its own profile and bit rate, and there is no audio at all.
[`Tools/appstore_conform.swift`](../Tools/appstore_conform.swift) rewrites the
file in place against the table above — High 4.0, inside the 10–12 Mbps band, with
a stereo AAC bed at 256 kbps:

```bash
python3 Tools/gen_preview_music.py /tmp/bed.wav 30
swift Tools/appstore_conform.swift AppStore/preview/en-US/iphone-6.9.mp4 886 1920 \
    /tmp/bed.wav 0.55
```

The bed is looped to the length of the cut and faded at both ends; the fourth
argument sets the gain. Leave the file out and the track is silent — which the
tool still writes, but Connect will not accept it, so the argument is effectively
required.

**The bit rate needs the all-intra trick, and this app needs it more than most.**
`AVVideoAverageBitRateKey` is a ceiling, not a target: the encoder spends what the
picture needs. A poker table is a flat green oval that barely moves, so asking for
14 Mbps with an ordinary one-second GOP measured **3.6 Mbps** — a third of the way
under Apple's floor. Setting `AVVideoMaxKeyFrameIntervalKey: 1` removes temporal
prediction, so every frame takes an equal share of the average and the request
becomes the delivered figure: 11.5 asked, 11.5 measured, ~31 MB for 22 s. Both
numbers are well inside Level 4.0 and nowhere near Connect's 500 MB. Do not
"optimise" the GOP back without measuring — a GOP of 2 was tried and came out at
26.5 Mbps, out of spec on its own.

One trap lives in the cut, and it costs an hour to find because the export reports
success: a clip of a screen that never moves gets a very long GOP, and asking for
a range that starts mid-GOP is silently dropped once the segment sits at a
non-zero offset in the composition — the finished file holds the last frame of the
*preceding* clip for those seconds instead. The composition itself looks correct;
only the finished file shows it. The menu clip here starts at 2.0 s rather than 0
and does move (the suits drift across the background), but if you ever add a clip
of a genuinely still screen, start it on a keyframe.
