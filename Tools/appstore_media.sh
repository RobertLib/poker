#!/bin/bash
#
# appstore_media.sh — regenerates every screenshot and App Preview in AppStore/.
#
#     Tools/appstore_media.sh                 # screenshots + previews
#     Tools/appstore_media.sh screenshots     # screenshots only
#     Tools/appstore_media.sh video           # previews only
#
# Needs Xcode, the simulators named below and ImageMagick (`brew install
# imagemagick`) for the lossless PNG squeeze. Everything is driven by the `-shot`
# launch argument handled in poker/Support/ScreenshotScenes.swift, which is
# `#if DEBUG` only — so this builds Debug, and none of it exists in the build
# that goes to the App Store.
#
# Output goes to AppStore/screenshots/<locale>/<device>/ and
# AppStore/preview/<locale>/<device>.mp4, where <device> is iphone-6.9,
# iphone-6.5 or ipad-13. Override the root with OUT_ROOT=… to try things out
# without touching the set you are about to upload.
#
set -euo pipefail

MODE="${1:-all}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_ROOT="${OUT_ROOT:-$ROOT/AppStore}"
WORK="${WORK:-$(mktemp -d -t acehigh-appstore)}"
BID=cz.rob.poker

# Every device records its App Store slot size natively, so unlike the previews
# below, nothing here is scaled or cropped:
#   iPhone 17 Pro Max → 1320 × 2868, one of the three sizes Connect takes for 6.9"
#   iPhone 11 Pro Max → 1242 × 2688, one of the two it takes for 6.5"
#   iPad Pro 13" (M5) → 2064 × 2752, one of the two it takes for iPad 13"
#
# Apple derives every *smaller* size from those itself — but only within a slot.
# The slot is picked per upload in Connect, and a listing sitting on the 6.5"
# slot refuses a 6.9" file outright: "derives the rest" means the 5.5" and 6.1"
# previews it shows on the store page, not the file you hand it. So both iPhone
# sizes are shot, which costs one more pass and means the right file is already
# on disk whichever slot Connect is showing.
IPHONE_NAME="iPhone 17 Pro Max"
IPHONE65_NAME="iPhone 11 Pro Max"
IPAD_NAME="iPad Pro 13-inch (M5)"
IPHONE_SHOT_SIZE=(1320 2868)
IPHONE65_SHOT_SIZE=(1242 2688)
IPAD_SHOT_SIZE=(2064 2752)

# Xcode ships the iPhone 11 Pro Max device *type* but no ready-made device for
# it, so the 6.5" one is created on demand (see ensure_device). iOS 26 still runs
# on that hardware, which is why the current runtime pairs with it at all.
IPHONE65_TYPE=com.apple.CoreSimulator.SimDeviceType.iPhone-11-Pro-Max

# App Preview render sizes — the only two App Store Connect takes for these
# devices, and *not* the devices' own resolutions. See AppStore/screenshots.md
# before changing either.
IPHONE_VIDEO_SIZE=(886 1920)
IPAD_VIDEO_SIZE=(1200 1600)

# Previews must carry stereo AAC at 256 kbps and silence does not satisfy the
# check, so a bed is synthesised — the app itself ships no audio at all.
PREVIEW_MUSIC="${PREVIEW_MUSIC-$WORK/bed.wav}"
PREVIEW_GAIN="${PREVIEW_GAIN:-0.55}"

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }

udid_for() {
    # Device lines are indented four spaces and read "<name> (<udid>) (<state>)".
    # Matched as a fixed string, because names like "iPad Pro 13-inch (M5)" carry
    # brackets of their own; the trailing " (" keeps "iPhone 17" from matching
    # "iPhone 17 Pro Max".
    xcrun simctl list devices available \
        | grep -F "    $1 (" \
        | grep -oE '[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}' \
        | head -n 1 || true
}

ensure_device() { # ensure_device <name> <device-type-id> -> udid on stdout
    local udid; udid="$(udid_for "$1")"
    if [ -z "$udid" ]; then
        # Newest installed runtime. simctl refuses a pairing the runtime does
        # not support, so a device type that has aged out fails here rather than
        # producing something that never boots. Messages go to stderr, because
        # the caller reads this function's stdout.
        local rt
        rt="$(xcrun simctl list runtimes available \
              | grep -oE 'com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]+' \
              | tail -n 1)"
        [ -n "$rt" ] || { echo "no iOS simulator runtime installed" >&2; return 1; }
        echo "  creating simulator '$1' on ${rt##*.}" >&2
        xcrun simctl create "$1" "$2" "$rt" >/dev/null || return 1
        udid="$(udid_for "$1")"
    fi
    printf '%s' "$udid"
}

boot_and_install() {
    local udid="$1"
    xcrun simctl boot "$udid" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
    xcrun simctl install "$udid" "$APP"
    # The table hides the status bar, but the menus and sheets do not, so pin it
    # rather than photograph a real clock and a draining battery.
    xcrun simctl status_bar "$udid" override --time "9:41" \
        --batteryState charged --batteryLevel 100 --wifiMode active --wifiBars 3 >/dev/null 2>&1 || true
}

locale_args() {
    case "$1" in
        cs)    printf '%s\0%s\0%s\0%s\0' -AppleLanguages "(cs)" -AppleLocale cs_CZ ;;
        en-US) printf '%s\0%s\0%s\0%s\0' -AppleLanguages "(en-US)" -AppleLocale en_US ;;
    esac
}

launch() { # launch <udid> <locale> <args...>
    local udid="$1" loc="$2"; shift 2
    local largs=()
    while IFS= read -r -d '' a; do largs+=("$a"); done < <(locale_args "$loc")
    xcrun simctl terminate "$udid" "$BID" >/dev/null 2>&1 || true
    xcrun simctl launch "$udid" "$BID" "${largs[@]}" "$@" >/dev/null
}

# A posed hand is a real hand: it takes as long to arrive as the deal, the blinds
# and two streets of betting take, which differs per pose and per device. The app
# drops a marker file when the moment being photographed is actually on screen
# (Shots.markReady), so nothing here has to sleep for a guess.
container_for() { xcrun simctl get_app_container "$1" "$BID" data; }

clear_ready() { rm -f "$(container_for "$1")/Documents/shot-ready" 2>/dev/null || true; }

wait_ready() { # wait_ready <udid> <timeout-seconds>
    local marker="$(container_for "$1")/Documents/shot-ready"
    local waited=0
    while [ ! -f "$marker" ] && [ "$waited" -lt "$2" ]; do
        sleep 1
        waited=$((waited + 1))
    done
    # stderr, because the caller reads this function's stdout.
    [ -f "$marker" ] || { echo "  !! pose never became ready (${2}s)" >&2; return 1; }
    printf '%s' "$waited"
}

# ---------------------------------------------------------------- build

say "Building Debug for the simulator"
xcodebuild -project "$ROOT/poker.xcodeproj" -scheme poker \
    -configuration Debug -sdk iphonesimulator \
    -destination "platform=iOS Simulator,name=$IPHONE_NAME" \
    -derivedDataPath "$WORK/dd" build >/dev/null
APP="$WORK/dd/Build/Products/Debug-iphonesimulator/poker.app"

IPHONE_UDID="$(udid_for "$IPHONE_NAME")"
IPAD_UDID="$(udid_for "$IPAD_NAME")"
[ -n "$IPHONE_UDID" ] || { echo "no simulator named '$IPHONE_NAME'"; exit 1; }
[ -n "$IPAD_UDID" ]   || { echo "no simulator named '$IPAD_NAME'"; exit 1; }

# ---------------------------------------------------------------- screenshots

# name|extra launch arguments. The pose itself lives in the shot catalogue in
# ScreenshotScenes.swift; only `-qa-raise` is a view-level flag, because opening
# the bet panel is the action bar's own business.
SHOTS=(
    "01-table|"
    "02-showdown|"
    "03-raise|-qa-raise"
    "04-setup|"
    "05-allin|"
    "06-rules|"
    "07-stats|"
    "08-menu|"
)

shoot() { # shoot <udid> <locale> <device-dir> <W> <H>
    local udid="$1" loc="$2" dev="$3" w="$4" h="$5"
    local dir="$OUT_ROOT/screenshots/$loc/$dev"
    mkdir -p "$dir"
    for entry in "${SHOTS[@]}"; do
        local name="${entry%%|*}" extra="${entry#*|}"
        clear_ready "$udid"
        # shellcheck disable=SC2086
        launch "$udid" "$loc" -shot "$name" $extra
        local waited
        waited="$(wait_ready "$udid" 90)" || exit 1
        xcrun simctl io "$udid" screenshot "$dir/$name.png" >/dev/null 2>&1
        local size
        size="$(magick identify -format '%wx%h' "$dir/$name.png")"
        printf '  %-12s %-10s ready in %2ss\n' "$name" "$size" "$waited"
        # Both devices record their slot size, so a mismatch means the simulator
        # is not the one this script expects rather than something to paper over.
        if [ "$size" != "${w}x${h}" ]; then
            echo "     !! expected ${w}x${h} — wrong simulator or a changed runtime"
            exit 1
        fi
    done
    xcrun simctl terminate "$udid" "$BID" >/dev/null 2>&1 || true
}

if [ "$MODE" = all ] || [ "$MODE" = screenshots ]; then
    command -v magick >/dev/null \
        || { echo "needs ImageMagick (brew install imagemagick)"; exit 1; }
    # Only the screenshots need the 6.5" device — the preview is one file for
    # every iPhone slot — so it is created here rather than next to the others.
    IPHONE65_UDID="$(ensure_device "$IPHONE65_NAME" "$IPHONE65_TYPE" || true)"
    [ -n "$IPHONE65_UDID" ] \
        || { echo "no simulator named '$IPHONE65_NAME', and creating one failed"; exit 1; }
    boot_and_install "$IPHONE_UDID"
    boot_and_install "$IPHONE65_UDID"
    boot_and_install "$IPAD_UDID"
    for loc in cs en-US; do
        say "Screenshots — iPhone 6.9\" / $loc"
        shoot "$IPHONE_UDID" "$loc" iphone-6.9 "${IPHONE_SHOT_SIZE[@]}"
        say "Screenshots — iPhone 6.5\" / $loc"
        shoot "$IPHONE65_UDID" "$loc" iphone-6.5 "${IPHONE65_SHOT_SIZE[@]}"
        say "Screenshots — iPad 13\" / $loc"
        shoot "$IPAD_UDID" "$loc" ipad-13 "${IPAD_SHOT_SIZE[@]}"
    done

    # The simulator writes RGBA even though every pixel is opaque, and App Store
    # Connect wants screenshots without transparency. Dropping the channel leaves
    # the picture untouched and saves about a third of the size — verified rather
    # than assumed, and anything that is not identical is left alone.
    say "Squeezing PNGs (lossless)"
    while IFS= read -r f; do
        magick "$f" -alpha off -depth 8 -strip \
                    -define png:compression-level=9 \
                    -define png:compression-filter=5 "$f.opt"
        if [ "$(magick compare -metric AE "$f" "$f.opt" null: 2>&1 | awk '{print $1}')" = "0" ]; then
            mv "$f.opt" "$f"
        else
            rm -f "$f.opt"
            echo "  left as-is (not identical): $f"
        fi
    done < <(find "$OUT_ROOT/screenshots" -name '*.png')
    du -sh "$OUT_ROOT/screenshots"
fi

# ---------------------------------------------------------------- previews

# name|seconds|launch arguments. Recording starts the moment the app is launched,
# so the clip covers the app's own launch animation too — the cut points below
# are measured from there.
#
# The two hands play themselves: `preview-hand` and `preview-allin` have no
# `holdAt`, so your seat calls its way to the showdown and the whole thing runs
# without touch input. Recording longer than the hand takes is deliberate; the
# cut is made afterwards.
CLIPS=(
    "p1-hand|30|-shot preview-hand"
    "p2-allin|24|-shot preview-allin"
    "p3-menu|7|-shot 08-menu"
)

# Cut points, in seconds into each recording. Every window is chosen to hold
# something *moving* from its first frame to its last: cards being dealt, chips
# flying, the board coming out, the pot being pushed. The hands are dealt from a
# stacked deck and the opposition is scripted, so the timeline is the same on
# every run — but the iPad reaches each state a little sooner than the iPhone,
# which is why the two have their own points.
#
# Two things bound the windows, and both were learned the hard way:
#
#   * The showdown clip is short on purpose. The confetti flies for about two
#     seconds and then the banner just sits there, so a five-second window spent
#     three of them on a still picture.
#   * Nothing may reach past about 21 s into a recording. The files report ~30 s
#     and the tail is not reliably decodable — a range that crosses it is clamped
#     and the finished preview holds one frame for the difference, while every
#     step reports success.
#
# After any change to pacing, to the poses or to the animations, look at the
# frames either side of each cut before uploading — Tools/appstore_frames.swift
# pulls them out. Nothing here fails loudly: a stale window just goes still.
IPHONE_CUTS=(p1-hand:1.5:6.5 p1-hand:9.6:15.1 p1-hand:19.2:22.0
             p2-allin:6.6:13.6 p3-menu:2.0:3.8)
IPAD_CUTS=(p1-hand:1.3:6.3 p1-hand:9.3:14.8 p1-hand:18.9:21.7
           p2-allin:6.3:13.3 p3-menu:2.0:3.8)

record() { # record <udid> <locale> <clipdir>
    local udid="$1" loc="$2" dir="$3"
    mkdir -p "$dir"
    for entry in "${CLIPS[@]}"; do
        IFS='|' read -r name secs args <<<"$entry"
        clear_ready "$udid"
        # shellcheck disable=SC2086
        launch "$udid" "$loc" $args
        xcrun simctl io "$udid" recordVideo --codec h264 --force "$dir/$name.mp4" >/dev/null 2>&1 &
        local pid=$!
        sleep "$secs"
        kill -INT $pid 2>/dev/null || true
        wait $pid 2>/dev/null || true
        sleep 1
        printf '  %-10s %s\n' "$name" "$(avmediainfo "$dir/$name.mp4" | awk '/^Duration:/{print $2 "s"}')"
    done
    xcrun simctl terminate "$udid" "$BID" >/dev/null 2>&1 || true
}

assemble() { # assemble <clipdir> <out.mp4> <W> <H> <cut...>
    local dir="$1" out="$2" w="$3" h="$4"; shift 4
    mkdir -p "$(dirname "$out")"
    local specs=()
    for cut in "$@"; do specs+=("$dir/${cut%%:*}.mp4:${cut#*:}"); done
    swift "$ROOT/Tools/appstore_video.swift" "$out" "$w" "$h" "${specs[@]}"
    # What comes out of the cut is the right size and the wrong everything else
    # for App Store Connect — too high a profile, too fast a bit rate and no
    # audio at all. This pins the lot to Apple's table.
    swift "$ROOT/Tools/appstore_conform.swift" "$out" "$w" "$h" \
        ${PREVIEW_MUSIC:+"$PREVIEW_MUSIC"} "$PREVIEW_GAIN"
}

if [ "$MODE" = all ] || [ "$MODE" = video ]; then
    boot_and_install "$IPHONE_UDID"
    boot_and_install "$IPAD_UDID"
    if [ -n "$PREVIEW_MUSIC" ] && [ ! -f "$PREVIEW_MUSIC" ]; then
        say "Synthesising the music bed"
        python3 "$ROOT/Tools/gen_preview_music.py" "$PREVIEW_MUSIC" 30
    fi
    for loc in cs en-US; do
        say "Preview — iPhone 6.9\" / $loc"
        record "$IPHONE_UDID" "$loc" "$WORK/clips/iphone-$loc"
        assemble "$WORK/clips/iphone-$loc" "$OUT_ROOT/preview/$loc/iphone-6.9.mp4" \
            "${IPHONE_VIDEO_SIZE[@]}" "${IPHONE_CUTS[@]}"

        say "Preview — iPad 13\" / $loc"
        record "$IPAD_UDID" "$loc" "$WORK/clips/ipad-$loc"
        assemble "$WORK/clips/ipad-$loc" "$OUT_ROOT/preview/$loc/ipad-13.mp4" \
            "${IPAD_VIDEO_SIZE[@]}" "${IPAD_CUTS[@]}"
    done
fi

say "Done. Working files in $WORK"
