#!/usr/bin/env python3
"""Generate apps/strata/source/Field.mc: the "Strata" pattern from the
owner's laser-cut planter (good-tools/tools/wall-planter/index.html,
PATTERNS.strata) laid over a 454 px round screen.

The noise, the hash, the random generator and the layer rules are ported
line for line, in pixels instead of millimetres (the planter's box is
234 mm wide; here 1 mm is 454/234 px). Lines run across the disc from
near the top; each one is the line above plus a gap that the noise
squeezes and opens; every fourth line is the accent. The layers part
round a clearing for each reading (ISLANDS, the moon's first so the
readings' partings have the last word), like water round a stone,
so the readings sit on clean black. Pebbles sit where the layers open
up, away from the time and the clearings. Each layer keeps its run
inside the disc and one sample past each end, so it reaches the rim.

    python3 designs/gen_strata.py [seed]      # default 7, the planter's "Variation 7"

Regenerate rather than edit the output. The watch scales it to 416 px.
"""
import sys
from pathlib import Path

SIZE = 454
STEP = 8                                    # px between samples along a line
TOP = int(SIZE * 0.02)                      # the first layer, right at the top
TIME_BAND = (int(SIZE * 0.36), int(SIZE * 0.65))    # the time sits here: no pebbles, nor in a row under it
MM = SIZE / 234.0                           # the planter's millimetre, in pixels
SP = 3.6 * MM                               # base gap between layers (the planter's 4.8 mm, packed closer for the small screen)
NOISE_A = 40 * MM                           # noise cell along the first line
NOISE_B = 36 * MM                           # noise cell along the rest
PEBBLE_GAP = 4.2 * MM                       # a layer gap wide enough for a pebble
MAX_PEBBLES = 48
CHUNK = 1000                                # samples to an array in Field.mc
CX = CY = SIZE / 2.0
R = SIZE / 2.0 - 3.0

FLATTEN = 0.3                               # how much of the way to level the layers round a clearing (unless it says)
PUSH = 1.15                                 # the parting clears this much of a clearing (unless it says)


class Island:
    """A clearing the layers part around, like water round a stone, so a
    reading sits on clean black with no halo. Centre (x, y), reach (how far,
    in heights, more than 1, the parting relaxes into the layers round it;
    or a pair, above and below),
    its upper and lower halves, how hard it pushes and how far it levels
    the layers first. A half is (shape, half width, height, taper[, offset
    x]) as fractions of SIZE, or a list of them (as high as the highest
    there), so a clearing can be narrow above and wide below. A "box" is
    flat over its half width and eases down to nothing over its taper
    beyond it; a "bump" is a raised cosine over its half width."""

    def __init__(self, x, y, reach, upper, lower, push=None, flatten=None):
        self.x, self.y, self.reach, self.upper, self.lower = x, y, reach, upper, lower
        self.push = PUSH if push is None else push
        self.flatten = FLATTEN if flatten is None else flatten


# Each clearing fits what it holds, with the widest values (a "MON DEC 28"
# date, 180 bpm, 12.4 mi) and a margin of MARGIN, measured on the
# preview's render, so the layers come right up to every reading. The
# moon's goes first, so the readings' partings have the last word. The
# same layout as StrataView's.
MARGIN = 0.012
MOON_ISLAND = Island(0.50, 0.862, 1.15, ("bump", 0.130, 0.094, 0), ("bump", 0.130, 0.094, 0))
# The sun's time (arrow left, bell right) over the date, easing out over
# about twice its height either side and levelled only a little, so the
# layers slope in like a valley
POOL_ISLAND = Island(0.50, 0.195, 2.0, ("box", 0.145 + MARGIN, 0.069 + MARGIN, 0.15),
                     ("box", 0.211 + MARGIN, 0.085 + MARGIN, 0.20))
# The readings: four slots, each any kind the settings offer, so one
# clearing fits the widest of any kind in every slot (from -0.068 to
# +0.116 of a slot's centre, its unit hung off the right): flat under the
# numbers and units, and over them a low floor with a mound rising to
# each cue, so the layers dip only a little between the columns. It is
# wide, so it levels the layers a little more to keep it flat.
ROW_Y = 0.680
CUES = (0.186, 0.391, 0.596, 0.801)
ROW_LEFT, ROW_RIGHT = CUES[0] - 0.068, CUES[-1] + 0.116


def mound(x):
    return ("bump", 0.09, 0.050 + MARGIN, 0, x - 0.5)


# It reaches down only briefly, so it does not push its layers into the moon
ROW_ISLAND = Island(0.50, ROW_Y, (1.6, 1.15),
                    [("box", (CUES[-1] - CUES[0]) / 2, 0.014, 0.06, (CUES[0] + CUES[-1]) / 2 - 0.5)] + [mound(x) for x in CUES],
                    ("box", (ROW_RIGHT - ROW_LEFT) / 2 + MARGIN, 0.056 + MARGIN, 0.16, (ROW_LEFT + ROW_RIGHT) / 2 - 0.5),
                    push=1.2, flatten=0.4)
ISLANDS = [MOON_ISLAND, POOL_ISLAND, ROW_ISLAND]
AOD_ISLANDS = [MOON_ISLAND, POOL_ISLAND]   # always-on shows no readings: its layers run on under the time
CUT = 1.0                                   # and any layer still inside it is cut there
SLIVER = 10                                 # samples (80 px) a piece cut at both ends needs to be kept


# ---- the planter's seeded noise, with JavaScript's 32-bit integer rules

def to_int32(x):
    x &= 0xFFFFFFFF
    return x - (1 << 32) if x >= (1 << 31) else x


def to_uint32(x):
    return x & 0xFFFFFFFF


def imul(a, b):
    return to_int32((a & 0xFFFFFFFF) * (b & 0xFFFFFFFF))


def hash2(i, j, seed):
    h = imul(i, 374761393) + imul(j, 668265263) + imul(seed, 1442695041)
    h = imul(to_int32(h) ^ to_int32(to_uint32(h) >> 13), 1274126177)
    return to_uint32(to_int32(h) ^ to_int32(to_uint32(h) >> 16)) / 4294967296


def vnoise(x, y, seed):
    xi, yi = int(x // 1), int(y // 1)
    xf, yf = x - xi, y - yi
    u = xf * xf * (3 - 2 * xf)
    v = yf * yf * (3 - 2 * yf)
    a = hash2(xi, yi, seed)
    b = hash2(xi + 1, yi, seed)
    c = hash2(xi, yi + 1, seed)
    d = hash2(xi + 1, yi + 1, seed)
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v


def fbm(x, y, seed):
    return (vnoise(x, y, seed) * 0.57
            + vnoise(x * 2.03, y * 2.03, seed + 7) * 0.29
            + vnoise(x * 4.1, y * 4.1, seed + 13) * 0.14)


def rng(seed):
    state = [to_uint32(seed) or 1]

    def next_value():
        s = state[0]
        s = to_uint32(imul(to_int32(s) ^ to_int32(s >> 15), 2246822519) + 0x9E3779B9)
        s ^= s >> 13
        state[0] = to_uint32(s)
        return state[0] / 4294967296
    return next_value


# ---- the layers

def inside(x, y, margin=0.0):
    reach = R - margin
    return (x - CX) ** 2 + (y - CY) ** 2 < reach * reach


def half(profile, cx, x):
    """A profile's height at x, in px (0 outside it); a list of profiles is
    as high as the highest of them there."""
    import math
    if isinstance(profile, list):
        return max(half(p, cx, x) for p in profile)
    shape, a, b, taper = profile[:4]
    dx = profile[4] if len(profile) > 4 else 0.0
    u = abs(x - (cx + dx) * SIZE) / SIZE
    if shape == "bump":
        return b * SIZE * 0.5 * (1.0 + math.cos(math.pi * u / a)) if u < a else 0.0
    if u <= a:
        return b * SIZE
    if u < a + taper:
        return b * SIZE * 0.5 * (1.0 + math.cos(math.pi * (u - a) / taper))
    return 0.0


def height(profile):
    """A profile's greatest height, as a fraction of SIZE."""
    return max(height(p) for p in profile) if isinstance(profile, list) else profile[2]


def chord(island, x, side):
    """How far the clearing reaches above (side -1) or below (+1) its
    centre at x, in px."""
    return half(island.upper if side < 0 else island.lower, island.x, x)


def inside_clearing(island, x, y, margin=1.0):
    cy = island.y * SIZE
    side = -1 if y < cy else 1
    return abs(y - cy) < margin * chord(island, x, side)


def straddle(raw, island, xs):
    """The layer just above the island's centre at its middle (the next one
    is just below), or None."""
    cy = island.y * SIZE
    mid = min(range(len(xs)), key=lambda i: abs(xs[i] - island.x * SIZE))
    above = max((k for k, ys in enumerate(raw) if ys[mid] < cy), default=None)
    if above is None or above + 1 >= len(raw):
        return None
    return above


def flatten(raw, island, xs):
    """Level the layers round an island part of the way (its flatten), so its
    clearing lies nearly flat but still follows the grain: shift each
    column toward the two layers straddling the centre sitting evenly
    about it, most at the centre's height and less further up and down,
    and not at all beyond the island's ends."""
    import math
    above = straddle(raw, island, xs)
    if above is None:
        return raw
    cy = island.y * SIZE
    tall = max(height(island.upper), height(island.lower)) * SIZE
    spread = 2.5 * tall
    upper, lower = raw[above], raw[above + 1]
    weights = [island.flatten * min(1.0, 3.0 * max(chord(island, x, -1), chord(island, x, 1)) / tall) for x in xs]
    return [[y - ((upper[i] + lower[i]) / 2 - cy) * weights[i] * math.exp(-((y - cy) / spread) ** 2)
             for i, y in enumerate(ys)] for ys in raw]


def part(raw, island, xs):
    """Push the layers apart round an island. Each layer keeps to its side
    of the parting, which runs between the two layers that straddle the
    centre, flat where it can; a layer moves by the clearing's height on
    its side at the parting, less further off, so the layers gather round
    the rim and relax away from it, never crossing (reach is over 1)."""
    import math
    above = straddle(raw, island, xs)
    if above is None:
        return raw
    cy = island.y * SIZE
    upper, lower = raw[above], raw[above + 1]
    out = []
    for k, ys in enumerate(raw):
        side = -1 if k <= above else 1
        reach = (island.reach[0 if side < 0 else 1] if isinstance(island.reach, tuple) else island.reach) \
            * height(island.upper if side < 0 else island.lower) * SIZE
        moved = []
        for i, (x, y) in enumerate(zip(xs, ys)):
            h = island.push * chord(island, x, side)
            if h == 0.0:
                moved.append(y)
                continue
            m = min(max(cy, upper[i] + 0.5), lower[i] - 0.5)
            moved.append(y + side * h * math.exp(-abs(y - m) / reach))
        out.append(moved)
    return out


def runs(xs, ys, islands):
    """(first, last) of each run of samples to keep: inside the disc and
    out of every clearing. A run that meets the rim keeps one sample past
    it, so the round screen trims the layer there."""
    disc = [inside(x, y) for x, y in zip(xs, ys)]
    clear = [not any(inside_clearing(c, x, y, CUT) for c in islands) for x, y in zip(xs, ys)]
    keep = [d and c for d, c in zip(disc, clear)]
    out = []
    start = None
    for i, flag in enumerate(keep + [False]):
        if flag and start is None:
            start = i
        elif not flag and start is not None:
            first, last = start, i - 1
            start = None
            rim = False
            if first > 0 and not disc[first - 1]:
                first -= 1
                rim = True
            if last + 1 < len(xs) and not disc[last + 1]:
                last += 1
                rim = True
            # A sliver cut off at both ends would float on its own: drop it
            if last > first and (rim or last - first >= SLIVER):
                out.append((first, last))
    return out


def generate(seed, islands=None):
    islands = islands or ISLANDS
    xs = [i * STEP for i in range(SIZE // STEP + 2)]
    prev = [TOP + 4 * MM + 3 * MM * fbm(x / NOISE_A, 0.3, seed) for x in xs]
    n_est = (SIZE - TOP) / SP
    raw, pebbles = [], []
    for k in range(200):
        lowest = min(prev)
        if lowest > SIZE + 60:
            break
        raw.append(prev)
        g = SP * (0.6 + 0.8 * min(1.0, k / n_est))
        nxt = [p + g * (0.3 + 1.4 * fbm(x / NOISE_B + k * 0.11, k * 0.53 + 3, seed)) for x, p in zip(xs, prev)]
        r = rng(seed * 31 + k)
        i = 1
        while i < len(xs) - 1:
            gap = nxt[i] - prev[i]
            if gap > PEBBLE_GAP and r() < 0.22:
                px, py = xs[i], (prev[i] + nxt[i]) / 2
                rx, ry = gap * (0.28 + 0.2 * r()), gap * 0.22
                r()   # the planter's rotation, which the watch cannot draw
                pebbles.append((k, i, (py - prev[i]) / gap, rx, ry))
                i += 1
            i += 1
        prev = nxt
    for island in islands:
        raw = part(flatten(raw, island, xs), island, xs)
    global PARTED
    PARTED = intrusions([(k, 0, ys) for k, ys in enumerate(raw)], islands)
    # Keep each layer's runs inside the disc and out of the clearings
    lines = []
    for k, ys in enumerate(raw):
        for first, last in runs(xs, ys, islands):
            lines.append((k, first, ys[first:last + 1]))
    # The pebbles ride with their layers; none where a reading is
    placed = []
    for k, i, f, rx, ry in pebbles:
        if k + 1 >= len(raw):
            continue
        px, py = xs[i], raw[k][i] + f * (raw[k + 1][i] - raw[k][i])
        in_band = TIME_BAND[0] - ry < py < TIME_BAND[1] + ry
        on_island = any(inside_clearing(c, x, py, 1.0) for c in islands for x in (px - rx - 6, px, px + rx + 6)) or \
            any(inside_clearing(c, px, py + dy, 1.0) for c in islands for dy in (-ry - 8, ry + 8))
        if inside(px, py, rx + 4) and not in_band and not on_island:
            placed.append((px, py, rx, ry))
    pebbles = placed
    # Scatter the pebbles so they appear here and there as the count grows
    r = rng(seed * 977 + 1)
    for i in range(len(pebbles) - 1, 0, -1):
        j = int(r() * (i + 1))
        pebbles[i], pebbles[j] = pebbles[j], pebbles[i]
    return lines, pebbles[:MAX_PEBBLES]


def intrusions(lines, islands=None):
    """For each clearing, how many layer samples fall inside it: a
    reading's clearing should have none."""
    return [sum(1 for _, first, ys in lines for i, y in enumerate(ys)
                if inside_clearing(c, (first + i) * STEP, y, 0.999)) for c in (islands or ISLANDS)]


def rows(values, per_row=20):
    out = []
    for i in range(0, len(values), per_row):
        out.append("        " + ", ".join(str(v) for v in values[i:i + per_row]) + ",")
    return "\n".join(out)


def main():
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 7
    lines, pebbles = generate(seed)
    parted = PARTED
    aod = [line for line in generate(seed, AOD_ISLANDS)[0] if line[0] % 8 == 7]
    first = [f for _, f, _ in lines]
    length = [len(ys) for _, _, ys in lines]
    accent = [1 if k % 4 == 3 else 0 for k, _, _ in lines]
    ys = [int(round(y * 10)) for _, _, line in lines + aod for y in line]
    pebble_values = [int(round(v)) for p in pebbles for v in p]
    # The samples in chunks: monkeyc's type checker overflows its stack on
    # one long array literal
    starts = range(0, len(ys), CHUNK)
    chunks = "\n".join(f"    const Y{n} = [\n{rows(ys[i:i + CHUNK])}\n    ];\n" for n, i in enumerate(starts))
    names = ", ".join(f"Y{n}" for n in range(len(starts)))
    out = Path(__file__).resolve().parent.parent / "apps" / "strata" / "source" / "Field.mc"
    out.write_text(f"""import Toybox.Lang;

// Generated by designs/gen_strata.py (seed {seed}): the planter's "Strata"
// pattern over a {SIZE} px round screen, {len(lines)} pieces of layers, {len(pebbles)} pebbles,
// and the {len(aod)} pieces always-on draws. A layer may come in pieces where it
// was cut at a clearing. FIRST is the index of a piece's first sample (its
// x is FIRST * STEP), LENGTH its number of samples, ACCENT 1 for the
// pieces of every fourth layer; AOD_FIRST and AOD_LENGTH the same for
// always-on's pieces (every eighth layer, parted round the sun line, the
// date and the moon only). The samples, in tenths of a pixel, run piece
// after piece, the always-on ones last, CHUNK to an array (chunks()).
// PEBBLES is x, y, rx, ry in pixels in a scattered order. Regenerate
// rather than edit.
module Field {{

    const SIZE = {SIZE};
    const STEP = {STEP};
    const COUNT = {len(lines)};
    const AOD_COUNT = {len(aod)};
    const CHUNK = {CHUNK};

    const FIRST = [
{rows(first)}
    ];

    const LENGTH = [
{rows(length)}
    ];

    const ACCENT = [
{rows(accent)}
    ];

    const AOD_FIRST = [
{rows([f for _, f, _ in aod])}
    ];

    const AOD_LENGTH = [
{rows([len(y) for _, _, y in aod])}
    ];

{chunks}
    function chunks() as Array<Array<Number>> {{
        return [{names}] as Array<Array<Number>>;
    }}

    const PEBBLES = [
{rows(pebble_values)}
    ];
}}
""")
    print(f"{out}: {len(lines)} pieces ({sum(length)} samples), {len(aod)} always-on pieces, {len(pebbles)} pebbles, seed {seed}")
    print(f"samples inside each clearing after parting: {parted}; after the cut (want 0): {intrusions(lines)}")


if __name__ == "__main__":
    main()
