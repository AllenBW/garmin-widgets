#!/usr/bin/env python3
"""Generate the Noir face's tubes: every lit thing on the face as baked
masks the watch tints and turns, so the glow is a real blur, not steps.

The watch cannot blur, so each tube is drawn here once per screen width,
white with the light in the alpha channel, in three layers:

- halo: the three Gaussians of the mockup's `neon()` (radii 0.009, 0.030
  and 0.075 of the width at strengths 1.0, 0.78 and 0.34), with a grain
  of noise. The screen has 16 bits a pixel, 32 levels of red and blue, and
  a smooth halo lands on them as bands; the noise breaks the bands into
  grain too fine to see (the simulator shows both: capture and look);
- core: the tube itself;
- thin: the tube in standby, no halo.

The watch draws a layer with `drawBitmap2`: `:tintColor` gives it the
tube's colour (the halo) or `Lib.Neon.core` of it (the core), and
`:transform` turns a hand about the dial's centre with a bilinear filter,
so one upright hand serves every angle. The preview
(designs/preview_noir.py) composes the same layers the same way. The
layers are packed as PNG, the one packing that keeps the light's 256
levels and can still be tinted and turned. Three watches can't pack one
(Forerunner 165, 165 Music, 70), so the face isn't built for them
(scripts/devices.py, NO_PNG).

Writes, never to be edited by hand:

- apps/noir/resources-round-<w>x<w>/drawables/*.png and tubes.xml
- apps/noir/resources-round-<w>x<w>/jsonData/layout.json and layout.xml:
  where each layer's pivot is, and the lettering's cells
- apps/noir/source/Layout.mc: the dial's geometry in fractions of the
  width and the lettering's advances

    uv run -q --with pillow --with numpy python -I designs/gen_noir.py [--check]

--check regenerates in memory and exits 1 if a file differs.
"""
import io
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
APP = ROOT / "apps" / "noir"
WIDTHS = [466, 454, 416, 390, 360]   # fenix 9 Pro 51 mm; fenix 8 47/51 mm; fenix 8 43 mm; Venu 4 41 mm; Forerunner 265S
SS = 4                               # the masks are drawn at four times the scale

# ---------------------------------------------------------------- the dial
# Fractions of the width. A hand is a loop: the outline of a stadium whose
# axis runs from R0 to R1 out from the centre, `wide` across, in tube T.
T = 0.0115                 # the hands' tube: 5 px at 454 (the mockup's loops at their slant)
THIN = 0.0050              # every tube in standby
HOUR = dict(r0=0.075, r1=0.235, wide=0.076)
MINUTE = dict(r0=0.075, r1=0.366, wide=0.042)
TWELVE = dict(x=0.016, r0=0.414, r1=0.470, t=0.0101)     # a pair of strokes
QUARTER = dict(r0=0.424, r1=0.470, t=0.0066, glow=0.7)   # one stroke at 3, 6 and 9

# The halo, as mockups_neon.neon(): Gaussian radii and strengths
SIGMA = (0.009, 0.030, 0.075)
K = (1.0, 0.78, 0.34)
FLOOR = 0.004              # taken off the light, so a halo ends at nothing rather than at an edge
DITHER = 0.036             # noise in the light, peak to peak: one of the screen's 32 levels of a strong colour
TURNED = 1.6               # and this much more in a layer the watch turns: the bilinear filter averages it down

# The date and the look's name, bent from thin tube
TEXT_H = 0.050             # the lettering's height
TEXT_T = 0.0056
TEXT_GLOW = 0.7
TEXT_GAP = 0.24            # between letters, in heights
TEXT_REACH = 0.050         # the lettering's halo is faded out by here (see cell())
DATE_R = 0.235             # the date's centre from the dial's, at 3, else 9, else 6 o'clock
BLOCK = 25.0               # a hand within this many degrees of a place takes it
TITLE_Y = 0.345            # the look's name: this far below the centre, or above while the minute hand is below

# The transition: on a wake a hand sweeps to where it is now in SWEEP ms and up to SWEEP_FAR more the
# further it has to go (half a turn at most), after Lib.Motion's push of 70 ms; a minute turning takes TICK
SWEEP = 300
SWEEP_FAR = 320
TICK = 300


def half(hand):
    """The loop's centre line from its axis."""
    return hand["wide"] / 2 - T / 2


# ---------------------------------------------------------------- lettering
# Single-stroke letters as a sign maker bends them, in a box one unit tall:
# (width, [paths]). Round bowls, one continuous tube where the form allows.

def arc(cx, cy, r, a0, a1, n=None, ry=None):
    """Points on a circle (an ellipse with ry); degrees on the screen, 0
    right, 90 down."""
    ry = r if ry is None else ry
    n = n or max(4, int(abs(a1 - a0) / 9))
    return [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)),
             cy + ry * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]


def bend(pts, r=0.09):
    """Round each corner of a path to radius r, as glass bends."""
    out = [pts[0]]
    for i in range(1, len(pts) - 1):
        (ax, ay), (bx, by), (cx, cy) = pts[i - 1], pts[i], pts[i + 1]
        la, lc = math.hypot(ax - bx, ay - by), math.hypot(cx - bx, cy - by)
        ua, uc = ((ax - bx) / la, (ay - by) / la), ((cx - bx) / lc, (cy - by) / lc)
        cos = max(-1.0, min(1.0, ua[0] * uc[0] + ua[1] * uc[1]))
        ang = math.acos(cos)
        if ang > math.radians(175):
            out.append((bx, by))
            continue
        d = min(r / math.tan(ang / 2), la * 0.45, lc * 0.45)
        rr = d * math.tan(ang / 2)
        p, q = (bx + ua[0] * d, by + ua[1] * d), (bx + uc[0] * d, by + uc[1] * d)
        bis = (ua[0] + uc[0], ua[1] + uc[1])
        bl = math.hypot(*bis)
        o = (bx + bis[0] / bl * rr / math.sin(ang / 2), by + bis[1] / bl * rr / math.sin(ang / 2))
        a0 = math.atan2(p[1] - o[1], p[0] - o[0])
        a1 = math.atan2(q[1] - o[1], q[0] - o[0])
        da = (a1 - a0 + math.pi) % (2 * math.pi) - math.pi
        out += [(o[0] + rr * math.cos(a0 + da * k / 6), o[1] + rr * math.sin(a0 + da * k / 6)) for k in range(7)]
    out.append(pts[-1])
    return out


def turned(glyph, w):
    """A glyph turned half round in its box (6 to 9)."""
    return [[(w - x, 1.0 - y) for x, y in p] for p in glyph]


_O = arc(0.28, 0.28, 0.28, 180, 360) + arc(0.28, 0.72, 0.28, 0, 180) + [(0.0, 0.28)]
_C = arc(0.28, 0.28, 0.28, 318, 180) + arc(0.28, 0.72, 0.28, 180, 42)
_SIX = [arc(0.50, 0.73, 0.50, 258, 180, ry=0.73) + arc(0.27, 0.73, 0.27, 180, -180)]
_P = [(0.0, 1.0), (0.0, 0.0), (0.24, 0.0)] + arc(0.24, 0.26, 0.26, -90, 90) + [(0.0, 0.52)]
LETTERS = {
    "0": (0.56, [_O]),
    "1": (0.30, [bend([(0.0, 0.26), (0.30, 0.0), (0.30, 1.0)], 0.05)]),
    "2": (0.54, [arc(0.27, 0.27, 0.27, 180, 400) + bend([(0.477, 0.444), (0.0, 1.0), (0.54, 1.0)])[1:]]),
    "3": (0.52, [arc(0.25, 0.24, 0.24, -165, 90) + arc(0.25, 0.74, 0.26, -90, 165)]),
    "4": (0.56, [bend([(0.40, 1.0), (0.40, 0.0), (0.0, 0.68), (0.56, 0.68)], 0.06)]),
    "5": (0.52, [bend([(0.48, 0.0), (0.06, 0.0), (0.06, 0.486)], 0.07)[:-1] + arc(0.24, 0.70, 0.28, -130, 150)]),
    "6": (0.54, _SIX),
    "7": (0.54, [bend([(0.0, 0.0), (0.54, 0.0), (0.20, 1.0)])]),
    "8": (0.54, [arc(0.27, 0.23, 0.23, 90, -270) + arc(0.27, 0.73, 0.27, 270, 630)]),
    "9": (0.54, turned(_SIX, 0.54)),
    "-": (0.40, [[(0.0, 0.5), (0.40, 0.5)]]),
    "A": (0.54, [bend([(0.0, 1.0), (0.27, 0.0), (0.54, 1.0)], 0.06), [(0.105, 0.66), (0.435, 0.66)]]),
    "B": (0.50, [[(0.0, 0.0), (0.0, 1.0)], [(0.0, 0.0), (0.22, 0.0)] + arc(0.22, 0.24, 0.24, -90, 90) + [(0.0, 0.48)],
                 arc(0.24, 0.74, 0.26, -90, 90) + [(0.0, 1.0)]]),
    "C": (0.52, [_C]),
    "D": (0.52, [[(0.0, 0.0), (0.0, 1.0)], [(0.0, 0.0), (0.20, 0.0)] + arc(0.20, 0.5, 0.32, -90, 90, ry=0.5) + [(0.0, 1.0)]]),
    "E": (0.46, [bend([(0.46, 0.0), (0.0, 0.0), (0.0, 1.0), (0.46, 1.0)], 0.07), [(0.0, 0.5), (0.38, 0.5)]]),
    "F": (0.46, [bend([(0.46, 0.0), (0.0, 0.0), (0.0, 1.0)], 0.07), [(0.0, 0.5), (0.38, 0.5)]]),
    "G": (0.56, [arc(0.28, 0.28, 0.28, 318, 180) + arc(0.28, 0.72, 0.28, 180, 0)
                 + bend([(0.56, 0.72), (0.56, 0.54), (0.30, 0.54)], 0.07)[1:]]),
    "H": (0.50, [[(0.0, 0.0), (0.0, 1.0)], [(0.50, 0.0), (0.50, 1.0)], [(0.0, 0.5), (0.50, 0.5)]]),
    "I": (0.0, [[(0.0, 0.0), (0.0, 1.0)]]),
    "J": (0.42, [[(0.42, 0.0), (0.42, 0.79)] + arc(0.21, 0.79, 0.21, 0, 180)]),
    "K": (0.50, [[(0.0, 0.0), (0.0, 1.0)], [(0.48, 0.0), (0.0, 0.54), (0.50, 1.0)]]),
    "L": (0.44, [bend([(0.0, 0.0), (0.0, 1.0), (0.44, 1.0)], 0.07)]),
    "M": (0.66, [bend([(0.0, 1.0), (0.0, 0.0), (0.33, 0.62), (0.66, 0.0), (0.66, 1.0)], 0.05)]),
    "N": (0.52, [bend([(0.0, 1.0), (0.0, 0.0), (0.52, 1.0), (0.52, 0.0)], 0.05)]),
    "O": (0.56, [_O]),
    "P": (0.50, [_P]),
    "Q": (0.56, [_O, [(0.34, 0.74), (0.58, 1.04)]]),
    "R": (0.50, [_P, [(0.20, 0.52), (0.50, 1.0)]]),
    "S": (0.52, [arc(0.26, 0.25, 0.25, -32, -270) + arc(0.26, 0.74, 0.26, -90, 152)]),
    "T": (0.50, [[(0.0, 0.0), (0.50, 0.0)], [(0.25, 0.0), (0.25, 1.0)]]),
    "U": (0.50, [[(0.0, 0.0), (0.0, 0.75)] + arc(0.25, 0.75, 0.25, 180, 0) + [(0.50, 0.0)]]),
    "V": (0.52, [bend([(0.0, 0.0), (0.26, 1.0), (0.52, 0.0)], 0.06)]),
    "W": (0.70, [bend([(0.0, 0.0), (0.175, 1.0), (0.35, 0.36), (0.525, 1.0), (0.70, 0.0)], 0.05)]),
    "X": (0.50, [[(0.0, 0.0), (0.50, 1.0)], [(0.50, 0.0), (0.0, 1.0)]]),
    "Y": (0.52, [bend([(0.0, 0.0), (0.26, 0.52), (0.52, 0.0)], 0.06), [(0.26, 0.54), (0.26, 1.0)]]),
    "Z": (0.50, [bend([(0.0, 0.0), (0.50, 0.0), (0.0, 1.0), (0.50, 1.0)], 0.07)]),
}
SPACE = 0.34
DIGITS = "0123456789-"
ALPHA = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
COLS = 9                   # the letters' sheet; the digits' is one row


def text_width(s):
    """A line's width in heights, tube centre to tube centre."""
    return sum(SPACE if c == " " else LETTERS[c][0] for c in s) + TEXT_GAP * (len(s) - 1)


# ---------------------------------------------------------------- masks

def blur(a, sigma):
    """A Gaussian blur of a float array (Pillow's is 8-bit, too coarse for
    the far halo)."""
    n = int(math.ceil(sigma * 3.5))
    k = np.exp(-0.5 * (np.arange(-n, n + 1) / sigma) ** 2)
    k /= k.sum()
    for axis in (0, 1):
        pad = [(0, 0), (0, 0)]
        pad[axis] = (n, n)
        p = np.pad(a, pad)
        out = np.zeros_like(a)
        for i, kv in enumerate(k):
            sl = [slice(None), slice(None)]
            sl[axis] = slice(i, i + a.shape[axis])
            out += kv * p[tuple(sl)]
        a = out
    return a


def draw(paths, t, size, origin, w):
    """The tubes' mask at the screen's scale: `paths` in fractions of the
    width from `origin` (px), tube `t` wide, round ends."""
    big = Image.new("L", (size[0] * SS, size[1] * SS), 0)
    d = ImageDraw.Draw(big)
    tw = t * w * SS
    for pts in paths:
        xy = [((origin[0] + x * w) * SS, (origin[1] + y * w) * SS) for x, y in pts]
        d.line(xy, fill=255, width=max(1, int(round(tw))), joint="curve")
        for x, y in (xy[0], xy[-1]):
            d.ellipse((x - tw / 2, y - tw / 2, x + tw / 2, y + tw / 2), fill=255)
    return np.asarray(big.resize(size, Image.BOX), dtype=np.float32) / 255


def halo(core, w, glow=1.0, far=True):
    """The light round a tube: the mockup's three Gaussians, less FLOOR so
    it ends at nothing."""
    light = K[0] * blur(core, SIGMA[0] * w) + K[1] * blur(core, SIGMA[1] * w)
    if far:
        light = light + K[2] * blur(core, SIGMA[2] * w)
    return np.clip(glow * light - FLOOR, 0, 1)


def dither(light, seed, amount):
    """Noise in the light, so the screen's 32 levels a colour (it has 16
    bits a pixel, and so has the simulator) fall as grain too fine to see
    instead of as bands. Uniform, `amount` of DITHER from peak to peak
    (one level of a strong colour); none where there is no light."""
    noise = (np.random.default_rng(seed).random(light.shape, dtype=np.float32) - 0.5) * DITHER * amount
    return np.where(light > 0, np.clip(light + noise, 0, 1), 0)


def crop(a, origin):
    """An 8-bit layer cut to its lit pixels: (image, the origin within it)."""
    a8 = np.clip(np.rint(a * 255), 0, 255).astype(np.uint8)
    ys, xs = np.nonzero(a8)
    x0, x1, y0, y1 = max(0, xs.min() - 1), min(a8.shape[1], xs.max() + 2), max(0, ys.min() - 1), min(a8.shape[0], ys.max() + 2)
    return Image.fromarray(a8[y0:y1, x0:x1]), (int(origin[0] - x0), int(origin[1] - y0))


def layers(paths, t, w, seed, glow=1.0, far=True, thin=False, amount=TURNED):
    """A tube's layers on a screen w wide: name -> (L image, the pivot's
    place in it, px)."""
    xs = [x for p in paths for x, _ in p]
    ys = [y for p in paths for _, y in p]
    m = int(math.ceil(SIGMA[2 if far else 1] * w * 3.2)) + 4
    ox, oy = int(math.ceil(-min(xs) * w)) + m, int(math.ceil(-min(ys) * w)) + m       # the pivot
    size = (int(math.ceil(ox + max(xs) * w)) + m, int(math.ceil(oy + max(ys) * w)) + m)
    core = draw(paths, t, size, (ox, oy), w)
    out = {"core": crop(core, (ox, oy)), "halo": crop(dither(halo(core, w, glow, far), seed * 1000 + w, amount), (ox, oy))}
    if thin:
        out["thin"] = crop(draw(paths, THIN, size, (ox, oy), w), (ox, oy))
    return out


def loop(hand):
    """A hand's centre line, pointing up from the pivot: a closed path."""
    h = half(hand)
    return [[(-h, -hand["r0"]), (-h, -hand["r1"])] + arc(0, -hand["r1"], h, 180, 360, 24)
            + [(h, -hand["r0"])] + arc(0, -hand["r0"], h, 0, 180, 24)]


def twelve():
    return [[(s * TWELVE["x"], -TWELVE["r0"]), (s * TWELVE["x"], -TWELVE["r1"])] for s in (-1, 1)]


def quarter():
    return [[(0.0, -QUARTER["r0"]), (0.0, -QUARTER["r1"])]]


def cell(w):
    """The lettering's cell on a screen w wide: (width, height, the
    letter's origin in it). Every letter has the same cell, so the watch
    finds one by its number."""
    m = int(math.ceil(TEXT_REACH * w))
    widest = max(g[0] for g in LETTERS.values())
    h = TEXT_H * w
    return int(math.ceil(widest * h)) + 2 * m, int(math.ceil(h * 1.05)) + 2 * m, m


def core_cell(w):
    m = int(math.ceil(TEXT_T * w / 2)) + 2
    widest = max(g[0] for g in LETTERS.values())
    h = TEXT_H * w
    return int(math.ceil(widest * h)) + 2 * m, int(math.ceil(h * 1.05)) + 2 * m, m


def sheet(chars, w, lit, cols, seed):
    """A sheet of letters, one cell each: the halo (its far reach faded
    out inside the cell, so no cell has an edge) or the core."""
    cw, ch, m = cell(w) if lit else core_cell(w)
    rows = (len(chars) + cols - 1) // cols
    out = Image.new("L", (cw * cols, ch * rows), 0)
    h = TEXT_H * w
    ramp = np.clip(np.minimum(np.arange(cw) + 0.5, cw - np.arange(cw) - 0.5) / (0.45 * m), 0, 1)
    rampy = np.clip(np.minimum(np.arange(ch) + 0.5, ch - np.arange(ch) - 0.5) / (0.45 * m), 0, 1)
    window = np.outer(rampy * rampy * (3 - 2 * rampy), ramp * ramp * (3 - 2 * ramp))
    for i, c in enumerate(chars):
        paths = [[(x * h / w, y * h / w) for x, y in p] for p in LETTERS[c][1]]
        a = draw(paths, TEXT_T, (cw, ch), (m, m), w)
        if lit:
            a = dither(halo(a, w, TEXT_GLOW, False) * window, (seed * 100 + i) * 1000 + w, 1.0)
        a8 = np.clip(np.rint(a * 255), 0, 255).astype(np.uint8)
        out.paste(Image.fromarray(a8), ((i % cols) * cw, (i // cols) * ch))
    return out


def parts(w):
    """Everything a screen w wide needs: (images, layout). `images` maps a
    resource name to an L image (the light); `layout` is layout.json."""
    images, layout = {}, {}
    sets = (("Hour", layers(loop(HOUR), T, w, 1, thin=True)), ("Minute", layers(loop(MINUTE), T, w, 2, thin=True)),
            ("Twelve", layers(twelve(), TWELVE["t"], w, 3, thin=True, amount=1.0)),
            ("Quarter", layers(quarter(), QUARTER["t"], w, 4, QUARTER["glow"], far=False)))
    for name, ls in sets:
        for kind, (img, (px, py)) in ls.items():
            images[name + kind.capitalize()] = img
            layout[name + kind.capitalize()] = [px, py]
    for n, (name, chars, cols) in enumerate((("Digits", DIGITS, len(DIGITS)), ("Letters", ALPHA, COLS))):
        images[name + "Halo"] = sheet(chars, w, True, cols, 5 + n)
        images[name + "Core"] = sheet(chars, w, False, cols, 0)
    layout["haloCell"] = list(cell(w))
    layout["coreCell"] = list(core_cell(w))
    return images, layout


# ---------------------------------------------------------------- output

def png(img):
    """White, the light in the alpha channel."""
    rgba = Image.merge("RGBA", (Image.new("L", img.size, 255),) * 3 + (img,))
    b = io.BytesIO()
    rgba.save(b, "PNG", optimize=True)
    return b.getvalue()


def layout_mc():
    chars = DIGITS + ALPHA
    adv = [int(round(LETTERS[c][0] * 1000)) for c in chars]
    f = lambda v: "%.4f" % v
    lines = [
        "// Generated by designs/gen_noir.py; regenerate, don't edit.",
        "import Toybox.Lang;",
        "",
        "// The dial's geometry in fractions of the width, as designs/gen_noir.py",
        "// baked it into the tubes, and the lettering's advances.",
        "module Layout {",
        "    const T = %s;                // the hands' tube" % f(T),
        "    const THIN = %s;             // a tube in standby" % f(THIN),
        "    const R0 = %s;               // both loops start here" % f(HOUR["r0"]),
        "    const HOUR_R1 = %s;" % f(HOUR["r1"]),
        "    const HOUR_HALF = %s;        // the loop's centre line from its axis" % f(half(HOUR)),
        "    const MINUTE_R1 = %s;" % f(MINUTE["r1"]),
        "    const MINUTE_HALF = %s;" % f(half(MINUTE)),
        "    const TEXT_H = %s;           // the lettering's height" % f(TEXT_H),
        "    const TEXT_GAP = %s;         // between letters, in heights" % f(TEXT_GAP),
        "    const SPACE = %s;" % f(SPACE),
        "    const DATE_R = %s;           // the date's centre from the dial's" % f(DATE_R),
        "    const BLOCK = %.1f;             // a hand within this many degrees of a place takes it" % BLOCK,
        "    const TITLE_Y = %s;          // the look's name, from the centre" % f(TITLE_Y),
        "    const SWEEP = %d;               // ms a hand's sweep takes on a wake," % SWEEP,
        "    const SWEEP_FAR = %d;           // and this much more over half a turn" % SWEEP_FAR,
        "    const TICK = %d;                // ms the hands take when the minute turns" % TICK,
        "    const DIGITS = \"%s\";         // the digits' sheet, one row" % DIGITS,
        "    const LETTERS = \"%s\";   // the letters' sheet," % ALPHA,
        "    const COLS = %d;                  // this many to a row" % COLS,
        "    // Each letter's width in thousandths of the height: the digits, then the letters",
        "    const WIDTHS = [",
    ]
    for i in range(0, len(adv), 12):
        lines.append("        " + ", ".join("%d" % v for v in adv[i:i + 12]) + ("," if i + 12 < len(adv) else ""))
    lines += ["    ] as Array<Number>;", "}", ""]
    return "\n".join(lines)


_made = {}


def _cached(w):
    if w not in _made:
        _made[w] = parts(w)
    return _made[w]


def files():
    """Every generated file: path -> bytes."""
    out = {APP / "source" / "Layout.mc": layout_mc().encode()}
    for w in WIDTHS:
        res = APP / ("resources-round-%dx%d" % (w, w))
        images, layout = _cached(w)
        xml = ['<drawables xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="https://developer.garmin.com/downloads/connect-iq/resources.xsd">',
               "    <!-- Generated by designs/gen_noir.py; regenerate, don't edit. White, the light in the alpha channel. -->"]
        for name in sorted(images):
            out[res / "drawables" / (name + ".png")] = png(images[name])
            # PNG keeps all 256 levels of light; the default packing keeps one bit of it, or
            # with a palette can be neither tinted nor turned ("Source must not use a color palette")
            xml.append('    <bitmap id="%s" filename="%s.png" dithering="none" packingFormat="png"/>' % (name, name))
        xml.append("</drawables>\n")
        out[res / "drawables" / "tubes.xml"] = "\n".join(xml).encode()
        out[res / "jsonData" / "layout.json"] = (json.dumps(layout, sort_keys=True) + "\n").encode()
        out[res / "jsonData" / "layout.xml"] = (
            '<resources xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="https://developer.garmin.com/downloads/connect-iq/resources.xsd">\n'
            "    <!-- Generated by designs/gen_noir.py; regenerate, don't edit. Each layer's pivot in its own pixels,\n"
            "         and the lettering's cells: width, height, the letter's origin -->\n"
            '    <jsonData id="Layout" filename="layout.json"/>\n</resources>\n').encode()
    return out


def main():
    check = "--check" in sys.argv
    bad = 0
    total = 0
    out = files()
    for path, data in out.items():
        total += len(data)
        if check:
            if not path.exists() or path.read_bytes() != data:
                print("DIFFERS: %s" % path.relative_to(ROOT))
                bad += 1
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
    for path in APP.glob("resources-round-*/*/*"):          # nothing stale beside what is generated
        if path not in out:
            if check:
                print("STALE: %s" % path.relative_to(ROOT))
                bad += 1
            else:
                path.unlink()
    print("noir: %d widths, %d KB of tubes%s" % (len(WIDTHS), total // 1024, (", %d differ" % bad) if check else ""))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
