#!/usr/bin/env python3
"""Writes the music bed for the App Preview.

    Tools/gen_preview_music.py <out.wav> [seconds]

Ace High ships with no audio: the sound effects are synthesised at launch, so
there is no track in the bundle to put under the trailer. App Store Connect
nevertheless *requires* stereo AAC at 256 kbps on an App Preview, and a silent
track does not satisfy it — AAC compresses digital silence to about 2 kbps, two
orders of magnitude under the rate asked for, and Connect reports a file with no
usable audio as an unsupported audio configuration. So the bed is synthesised
here, in the same spirit as the game's own sounds, and looped under the cut by
Tools/appstore_conform.swift.

Stdlib only (`wave`, `math`, `random`) so it runs on a stock macOS Python.

What it plays: a slow ii-V-I-VI turnaround in D minor at 76 BPM — the card-room
cliche, deliberately — as soft Rhodes-ish tines over an upright-bass root, with a
brushed shaker on the off-beats. It is mixed quiet and dull on purpose: it sits
under chip and card sounds in the trailer and must not compete with them.
"""

import math
import random
import struct
import sys
import wave

RATE = 48_000
CHANNELS = 2
BPM = 76.0
BEAT = 60.0 / BPM
BAR = 4 * BEAT

# ii-V-I-VI in D minor, one chord per bar. Semitones from A0 (27.5 Hz), so the
# root sits where an upright bass actually plays.
A0 = 27.5
PROGRESSION = [
    (29, [29, 36, 41, 46]),  # Dm7   D  C  F  A
    (34, [34, 41, 44, 50]),  # G7    G  F  B  E
    (27, [27, 39, 43, 46]),  # Cmaj7 C  B  E  G
    (24, [24, 40, 43, 48]),  # A7    A  C# E  G
]


def hz(semitone: float) -> float:
    return A0 * 2 ** (semitone / 12.0)


def tine(t: float, freq: float) -> float:
    """One Rhodes-ish note: three partials with a fast attack and a long decay.

    The second partial decays twice as fast as the first, which is most of what
    makes an electric piano sound struck rather than blown.
    """
    if t < 0:
        return 0.0
    attack = min(1.0, t / 0.012)
    body = math.exp(-t * 0.85)
    bell = math.exp(-t * 2.4)
    w = 2 * math.pi * freq * t
    return attack * (
        body * math.sin(w)
        + 0.34 * bell * math.sin(2 * w)
        + 0.11 * math.exp(-t * 5.0) * math.sin(4 * w)
    )


def bass(t: float, freq: float) -> float:
    """Plucked root: a sine with a touch of second harmonic and a soft attack."""
    if t < 0:
        return 0.0
    attack = min(1.0, t / 0.02)
    env = math.exp(-t * 1.15)
    w = 2 * math.pi * freq * t
    return attack * env * (math.sin(w) + 0.22 * math.sin(2 * w))


def render(seconds: float, seed: int = 20260827):
    """Returns interleaved float samples for `seconds` of music."""
    noise = random.Random(seed)
    total = int(seconds * RATE)
    left = [0.0] * total
    right = [0.0] * total

    def add(start: float, dur: float, gen, gain: float, pan: float):
        """Mixes one voice in. `pan` is -1 hard left, +1 hard right."""
        i0 = max(0, int(start * RATE))
        i1 = min(total, int((start + dur) * RATE))
        gl = gain * math.sqrt((1.0 - pan) / 2.0)
        gr = gain * math.sqrt((1.0 + pan) / 2.0)
        for i in range(i0, i1):
            value = gen((i - start * RATE) / RATE)
            left[i] += value * gl
            right[i] += value * gr

    bar = 0
    while bar * BAR < seconds:
        root, voicing = PROGRESSION[bar % len(PROGRESSION)]
        t0 = bar * BAR

        # Bass on 1 and on the second half of 3 — walking would pull attention.
        add(t0, BAR, lambda t, f=hz(root): bass(t, f), 0.30, 0.0)
        add(t0 + 2.5 * BEAT, 1.5 * BEAT, lambda t, f=hz(root + 7): bass(t, f), 0.20, 0.0)

        # The chord, spread across the stereo field and struck slightly late on
        # each voice: a perfectly simultaneous chord sounds synthetic.
        for index, semitone in enumerate(voicing):
            pan = -0.5 + index * (1.0 / max(1, len(voicing) - 1))
            stagger = index * 0.014
            add(t0 + stagger, BAR, lambda t, f=hz(semitone + 12): tine(t, f), 0.13, pan)
            # A quiet second voicing on beat 3 keeps the bar from sagging.
            add(t0 + 2 * BEAT + stagger, 2 * BEAT,
                lambda t, f=hz(semitone + 12): tine(t, f), 0.07, -pan)

        # Shaker on the eighths, accented off the beat, with the amplitude
        # jittered so a loop point does not stand out as a mechanical repeat.
        for eighth in range(8):
            at = t0 + eighth * BEAT / 2
            if at >= seconds:
                break
            accent = 0.055 if eighth % 2 else 0.028
            jitter = 1.0 + noise.uniform(-0.18, 0.18)
            seedling = noise.random()

            def shaker(t, level=accent * jitter, s=seedling):
                if t < 0 or t > 0.09:
                    return 0.0
                # Filtered noise: a deterministic hash per sample so the same
                # seed always renders the same file.
                n = math.sin((t * 1e5 + s * 1e4) * 12.9898) * 43758.5453
                return level * (n - math.floor(n) - 0.5) * math.exp(-t * 38.0)

            add(at, 0.1, shaker, 1.0, noise.uniform(-0.35, 0.35))

        bar += 1

    # Soft-knee limiter, then a fade at both ends so the loop join is inaudible.
    peak = max(1e-6, max(max(abs(v) for v in left), max(abs(v) for v in right)))
    scale = 0.72 / peak
    fade = int(0.35 * RATE)
    out = []
    for i in range(total):
        env = 1.0
        if i < fade:
            env = i / fade
        elif i > total - fade:
            env = max(0.0, (total - i) / fade)
        out.append(math.tanh(left[i] * scale) * env)
        out.append(math.tanh(right[i] * scale) * env)
    return out


def main() -> int:
    if not 2 <= len(sys.argv) <= 3:
        print(__doc__.strip().splitlines()[2].strip(), file=sys.stderr)
        return 2
    path = sys.argv[1]
    # Four bars is one full turnaround; conform loops it to the cut's length, so
    # the default only has to be long enough not to loop audibly often.
    seconds = float(sys.argv[2]) if len(sys.argv) > 2 else 4 * BAR * 2

    samples = render(seconds)
    with wave.open(path, "wb") as f:
        f.setnchannels(CHANNELS)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(b"".join(
            struct.pack("<h", max(-32768, min(32767, int(v * 32767)))) for v in samples))
    print(f"→ {path}  {seconds:.1f}s  {RATE} Hz stereo")
    return 0


if __name__ == "__main__":
    sys.exit(main())
