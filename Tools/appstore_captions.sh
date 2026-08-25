#!/bin/bash
#
# appstore_captions.sh — paints captions onto the finished screenshots.
#
#     Tools/appstore_captions.sh
#
# Reads AppStore/screenshots/<locale>/<device>/*.png and writes
# AppStore/screenshots-captioned/<locale>/<device>/*.png with the same names, so
# either set can be uploaded and the order is unchanged. Needs only ImageMagick
# — no simulator and no build.
#
# Layout: a band of text at the top, below it the shrunken screenshot on the same
# near-black the app's own background gradient starts from, with a hairline gold
# border and a soft shadow. The game shot is never cropped, only scaled down, so
# neither the blinds header at the top nor the action bar at the bottom loses
# anything.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IN_ROOT="${IN_ROOT:-$ROOT/AppStore/screenshots}"
OUT_ROOT="${OUT_ROOT:-$ROOT/AppStore/screenshots-captioned}"

command -v magick >/dev/null || { echo "needs ImageMagick (brew install imagemagick)"; exit 1; }
[ -d "$IN_ROOT" ] || { echo "no screenshots in $IN_ROOT — run Tools/appstore_media.sh first"; exit 1; }

# From Theme.swift: backgroundTop, gold, cream. The band is the app's own
# background rather than an invented marketing colour, so the caption reads as
# part of the app and not as a sticker on top of it.
BG='#0E1220'
GOLD='#E3B852'
CREAM='#F5F0E1'

# Arial Bold is the only bold face on a stock macOS with complete Czech
# diacritics — Arial Rounded Bold has neither ť nor ě, and ImageMagick renders SF
# in regular only. Given as a path, not as a name: the Homebrew build has no
# fontconfig type map, so `-font Arial-Bold` fails and takes the caption with it
# while still exiting 0.
FONT="${FONT:-/System/Library/Fonts/Supplemental/Arial Bold.ttf}"
[ -f "$FONT" ] || { echo "no font at $FONT — set FONT=/path/to/font.ttf"; exit 1; }

# The captions. Two lines each, broken by hand: leaving one word alone on the
# second line looks like an accident. Order matches the shot order.
en_caption() {
    case "$1" in
        01-table)    printf 'Real No-Limit Hold%s%sem.\nOffline.' "'" "" ;;
        02-showdown) printf 'Win it with the best\nfive cards.' ;;
        03-raise)    printf 'Bet any size you like.\nOr shove.' ;;
        04-setup)    printf 'Six opponents,\nsix styles.' ;;
        05-allin)    printf 'Side pots, split pots,\ndead button.' ;;
        06-rules)    printf 'All ten hands,\ndrawn out in cards.' ;;
        07-stats)    printf 'Every hand you\nhave ever played.' ;;
        08-menu)     printf 'No ads. No purchases.\nEver.' ;;
    esac
}

cs_caption() {
    case "$1" in
        01-table)    printf 'Opravdový No-Limit\nHold%sem. Offline.' "'" ;;
        02-showdown) printf 'Vyhraj to nejlepší\npěticí karet.' ;;
        03-raise)    printf 'Sázej, kolik chceš.\nNebo všechno.' ;;
        04-setup)    printf 'Šest soupeřů,\nšest stylů.' ;;
        05-allin)    printf 'Side poty, dělené poty,\ndead button.' ;;
        06-rules)    printf 'Všech deset kombinací,\nvykreslených kartami.' ;;
        07-stats)    printf 'Každé rozdání,\ncos kdy zahrál.' ;;
        08-menu)     printf 'Bez reklam.\nBez nákupů. Nikdy.' ;;
    esac
}

caption_for() { # caption_for <locale> <name>
    case "$1" in
        cs) cs_caption "$2" ;;
        *)  en_caption "$2" ;;
    esac
}

paint() { # paint <in.png> <out.png> <locale> <name>
    local src="$1" dst="$2" loc="$3" name="$4"
    local W H
    # The newline matters: `read` returns non-zero at EOF without one, and under
    # `set -e` that ends the run with no output at all.
    read -r W H < <(magick identify -format '%w %h\n' "$src")

    # Proportions, not pixels, so an iPhone and an iPad shot are laid out the
    # same way rather than the iPad getting a band a third of the height.
    local band=$((H * 19 / 100))          # text area at the top
    local pad=$((W * 6 / 100))            # margin below the shrunken shot
    local point=$((W * 62 / 1000))        # caption size
    local inner_h=$((H - band - pad))
    local text lines offset
    text="$(caption_for "$loc" "$name")"
    # The text is centred in the band by hand. A line of Arial Bold occupies
    # about 1.25 × its point size, and `-interline-spacing` adds a fifth of one
    # between lines; without this the caption clings to the top of the band and
    # leaves an obvious hole above the picture.
    lines="$(printf '%s\n' "$text" | awk 'END { print NR }')"
    offset=$(( (band - (lines * point * 125 / 100 + (lines - 1) * point / 5)) / 2 ))
    [ "$offset" -lt 0 ] && offset=0

    # The shot is fitted to the space left under the band — to height, never to
    # width, so it is scaled and not cropped: the blinds header at the top and
    # the action bar at the bottom both have to survive. Composited at an
    # explicit offset rather than gravity-extended, so the margin below it is the
    # one asked for instead of nothing.
    magick -size "${W}x${H}" "xc:$BG" \
        \( "$src" -resize "x${inner_h}" \
                  -bordercolor "$GOLD" -border 2 \
                  \( +clone -background black -shadow 55x"$((W / 90))"+0+"$((W / 160))" \) \
                  +swap -background none -layers merge +repage \) \
        -gravity north -geometry "+0+${band}" -composite \
        -font "$FONT" -pointsize "$point" -fill "$CREAM" \
        -interline-spacing "$((point / 5))" \
        -gravity north -annotate "+0+${offset}" "$text" \
        -alpha off -depth 8 -strip \
        -define png:compression-level=9 "$dst"
}

for loc_dir in "$IN_ROOT"/*; do
    [ -d "$loc_dir" ] || continue
    loc="$(basename "$loc_dir")"
    for dev_dir in "$loc_dir"/*; do
        [ -d "$dev_dir" ] || continue
        dev="$(basename "$dev_dir")"
        out="$OUT_ROOT/$loc/$dev"
        mkdir -p "$out"
        printf '\n\033[1m%s / %s\033[0m\n' "$loc" "$dev"
        for src in "$dev_dir"/*.png; do
            name="$(basename "$src" .png)"
            paint "$src" "$out/$name.png" "$loc" "$name"
            printf '  %-12s %s\n' "$name" "$(magick identify -format '%wx%h' "$out/$name.png")"
        done
    done
done

du -sh "$OUT_ROOT"
