#!/usr/bin/env python3
"""Render the Sign face (design #57): what SignView draws, from the same
sprites and the same whole-pixel layout. The time is a neon sign, numerals
bent from one tube each, the hours over the minutes, left of centre on open
black; the date to the right in thin tube.

    python3 -I designs/preview_sign.py out.png [standby] [360|390|416|454|466]
        [time=10:37] [format=24|12] [date="TUE 15"] [title=1] [watch=1]
        [look=yours|red|blue|green|low|daily] [day=0..6]
        [hours=ROSE minutes=TURQUOISE detail=AMBER]
        [from=09:36 strike=150 [turn=1]]
    python3 -I designs/preview_sign.py --sheets designs/sign
    python3 -I designs/preview_sign.py --strike designs/sign

`look` and the three tubes are the settings (Lib.Look, Lib.Neon); `day`
picks the daily look's set. `title=1` shows the look's name where the date
is, as after a hold. `watch=1` cuts the colours to the watch's 16 bits, to
judge the halo's dither. `--sheets` writes the review sheets: the numerals
and letters, every hour in both clocks, every set and look, the titles and
the five screen sizes with the standby's lit share (under 10 %).
`strike=MS` with `from=HH:MM` draws one frame of the number transition, MS
ms after the face woke having last shown `from` (`turn=1`: after the
minute turned while awake, the old tube dying first). `--strike` writes
the three scenes as GIFs at the face's frame rate and a sheet of frames.

Everything lit is a tube: one width, round ends, bends not corners. A lit
tube is a pale core and a halo in the tube's colour; the watch cannot blur,
so the halo is baked for each numeral and letter as a grey mask the watch
tints (designs/gen_sign.py writes the masks from the functions here). The
mask is three blurs of the tube summed (HALO, the approved sketch's), with
a fine noise the size of one step of the watch's 16-bit colour, so the
glow fades with no visible steps. Pillow only: the generator runs in the
tools' venv.
"""
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))                                   # run with -I
from colors import NEON_LOOKS, NEON_SETS, TUBES as CHART, core, rgb, standby  # noqa: E402

WIDTHS = (360, 390, 416, 454, 466)
SS = 4                                 # the strokes are drawn at four times the size and reduced

# ---------------------------------------------------------------- the layout
# Fractions of the screen width (digits and letters: of their own height)
X = 0.435                              # the time's centre line, left of the screen's
Y_HOURS, Y_MINUTES = 0.155, 0.540      # the rows' tops
DIGIT = 0.305                          # the numerals' height
GAP = 0.20                             # between numerals, of their height
TUBE = 0.0125                          # the numerals' tube
THIN = 0.0058                          # and in standby
DATE_X, DATE_Y = 0.800, 0.500          # the date's centre
SMALL = 0.044                          # the date's letters (the mockup's 0.036 is under the watch's smallest text)
SMALL_TUBE = 0.0052
SMALL_GAP = 0.28                       # between letters, of their height
SPACE = 0.30                           # a space's width, of the height
LINE = 0.60                            # between a title's two lines, of the height
HALO = ((0.009, 1.0), (0.030, 0.78), (0.075, 0.34))   # the mockup's blurs: radius, strength
SMALL_GLOW = 0.7                       # the date's halo is quieter, as in the mockup
PAD = 0.110                            # room for the halo round a numeral
SMALL_PAD = 0.055                      # and round a letter
DITHER = 10                            # the noise in the halo, in mask levels: one 5-bit step at a strong tint
AOD_STEP = 0.006                       # the standby shift (Lib.Aod.offset)
DAYS = ("SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT")


# ---------------------------------------------------------------- the lettering
# Single-stroke numerals and capitals as a sign maker bends them, in a box
# one unit tall, y down. A path is one tube; a point (x, y, r) is a bend of
# radius r (a tube has no corners). A new path only where a real tube would
# double back or branch.

def arc(cx, cy, r, a0, a1):
    """Points on a circle; degrees on the screen (0 right, 90 down)."""
    n = max(2, int(abs(a1 - a0) / 5))
    return [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)),
             cy + r * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]


def bent(path):
    """The path with each (x, y, r) corner replaced by its bend."""
    out = []
    for i, p in enumerate(path):
        if len(p) == 2 or i in (0, len(path) - 1):
            out.append((p[0], p[1]))
            continue
        ax, ay = path[i - 1][:2]
        bx, by, r = p
        cx, cy = path[i + 1][:2]
        ua, ub = math.hypot(ax - bx, ay - by), math.hypot(cx - bx, cy - by)
        u = ((ax - bx) / ua, (ay - by) / ua)
        v = ((cx - bx) / ub, (cy - by) / ub)
        half = math.acos(max(-1.0, min(1.0, u[0] * v[0] + u[1] * v[1]))) / 2
        t = min(r / math.tan(half), ua / 2, ub / 2)             # from the corner to where the bend starts
        r = t * math.tan(half)
        bis = (u[0] + v[0], u[1] + v[1])
        bl = math.hypot(*bis)
        ox, oy = bx + bis[0] / bl * r / math.sin(half), by + bis[1] / bl * r / math.sin(half)
        a0 = math.atan2(by + u[1] * t - oy, bx + u[0] * t - ox)
        a1 = math.atan2(by + v[1] * t - oy, bx + v[0] * t - ox)
        while a1 - a0 > math.pi:
            a1 -= 2 * math.pi
        while a1 - a0 < -math.pi:
            a1 += 2 * math.pi
        n = max(3, int(abs(a1 - a0) / math.radians(12)))
        out += [(ox + r * math.cos(a0 + (a1 - a0) * k / n), oy + r * math.sin(a0 + (a1 - a0) * k / n)) for k in range(n + 1)]
    return out


def _six():
    # one tube: down the left in a long sweep, then round the bowl and closed on itself
    return [arc(0.779, 0.72, 0.769, 245.5, 180) + arc(0.28, 0.72, 0.27, 180, -180)[1:]]


def _turned(paths, w):
    return [[(w - x, 1.0 - y) for x, y in p] for p in paths]


def _two():
    # the bowl, then straight down its tangent to the foot
    c, r, foot = (0.27, 0.27), 0.27, (0.0, 1.0)
    d = math.hypot(foot[0] - c[0], foot[1] - c[1])
    t = math.degrees(math.atan2(foot[1] - c[1], foot[0] - c[0]) - math.acos(r / d))
    return [arc(c[0], c[1], r, 192, 360 + t) + [(foot[0], foot[1], 0.045), (0.54, 1.0)]]


R = 0.07   # a letter's bend
GLYPHS = {
    "0": [arc(0.28, 0.28, 0.28, 180, 360) + arc(0.28, 0.72, 0.28, 0, 180) + [(0.0, 0.28)]],
    "1": [[(0.0, 0.25), (0.26, -0.045, 0.04), (0.26, 1.0)]],
    "2": _two(),
    "3": [arc(0.25, 0.24, 0.24, -165, 90) + arc(0.25, 0.74, 0.26, -90, 165)],
    "4": [[(0.42, 0.0), (0.0, 0.69, 0.04), (0.58, 0.69)], [(0.42, 0.0), (0.42, 1.0)]],
    "5": [[(0.48, 0.0), (0.06, 0.0, 0.05), (0.06, 0.486)] + arc(0.24, 0.70, 0.28, -130, 150)],
    "6": _six(),
    "7": [[(0.0, 0.0), (0.54, 0.0, 0.06), (0.20, 1.0)]],
    "8": [arc(0.265, 0.235, 0.235, 90, 450) + arc(0.265, 0.735, 0.265, -90, 270)[1:]],
    "9": _turned(_six(), 0.55),
    "A": [[(0.0, 1.0), (0.25, 0.0, 0.03), (0.50, 1.0)], [(0.10, 0.64), (0.40, 0.64)]],
    "B": [[(0.0, 0.0), (0.0, 1.0)], [(0.0, 0.0), (0.21, 0.0)] + arc(0.21, 0.25, 0.25, -90, 90) + [(0.0, 0.5)],
          [(0.0, 0.5), (0.23, 0.5)] + arc(0.23, 0.75, 0.25, -90, 90) + [(0.0, 1.0)]],
    "C": [arc(0.26, 0.26, 0.26, -35, -180) + arc(0.26, 0.74, 0.26, 180, 35)],
    "D": [[(0.0, 0.0), (0.0, 1.0)], [(0.0, 0.0), (0.20, 0.0)] + arc(0.20, 0.28, 0.28, -90, 0) + arc(0.20, 0.72, 0.28, 0, 90) + [(0.0, 1.0)]],
    "E": [[(0.42, 0.0), (0.0, 0.0, R), (0.0, 1.0, R), (0.42, 1.0)], [(0.0, 0.5), (0.36, 0.5)]],
    "F": [[(0.42, 0.0), (0.0, 0.0, R), (0.0, 1.0)], [(0.0, 0.5), (0.36, 0.5)]],
    "G": [arc(0.26, 0.26, 0.26, -35, -180) + arc(0.26, 0.74, 0.26, 180, 0) + [(0.52, 0.56, R), (0.28, 0.56)]],
    "H": [[(0.0, 0.0), (0.0, 1.0)], [(0.48, 0.0), (0.48, 1.0)], [(0.0, 0.5), (0.48, 0.5)]],
    "I": [[(0.0, 0.0), (0.0, 1.0)]],
    "J": [[(0.38, 0.0), (0.38, 0.78)] + arc(0.19, 0.78, 0.19, 0, 180)],
    "K": [[(0.0, 0.0), (0.0, 1.0)], [(0.44, 0.0), (0.0, 0.60)], [(0.15, 0.40), (0.46, 1.0)]],
    "L": [[(0.0, 0.0), (0.0, 1.0, R), (0.42, 1.0)]],
    "M": [[(0.0, 1.0), (0.0, 0.0, 0.03), (0.29, 0.62, 0.03), (0.58, 0.0, 0.03), (0.58, 1.0)]],
    "N": [[(0.0, 1.0), (0.0, 0.0, 0.03), (0.48, 1.0, 0.03), (0.48, 0.0)]],
    "O": [arc(0.26, 0.26, 0.26, 180, 360) + arc(0.26, 0.74, 0.26, 0, 180) + [(0.0, 0.26)]],
    "P": [[(0.0, 1.0), (0.0, 0.0)], [(0.0, 0.0), (0.21, 0.0)] + arc(0.21, 0.27, 0.27, -90, 90) + [(0.0, 0.54)]],
    "Q": [arc(0.26, 0.26, 0.26, 180, 360) + arc(0.26, 0.74, 0.26, 0, 180) + [(0.0, 0.26)], [(0.32, 0.76), (0.54, 1.02)]],
    "R": [[(0.0, 1.0), (0.0, 0.0)], [(0.0, 0.0), (0.21, 0.0)] + arc(0.21, 0.27, 0.27, -90, 90) + [(0.0, 0.54)],
          [(0.20, 0.54), (0.48, 1.0)]],
    "S": [arc(0.24, 0.25, 0.24, -30, -270) + arc(0.24, 0.745, 0.255, -90, 155)],
    "T": [[(0.0, 0.0), (0.46, 0.0)], [(0.23, 0.0), (0.23, 1.0)]],
    "U": [[(0.0, 0.0), (0.0, 0.76)] + arc(0.23, 0.76, 0.23, 180, 0) + [(0.46, 0.0)]],
    "V": [[(0.0, 0.0), (0.24, 1.0, 0.03), (0.48, 0.0)]],
    "W": [[(0.0, 0.0), (0.155, 1.0, 0.03), (0.31, 0.30, 0.03), (0.465, 1.0, 0.03), (0.62, 0.0)]],
    "X": [[(0.0, 0.0), (0.46, 1.0)], [(0.46, 0.0), (0.0, 1.0)]],
    "Y": [[(0.0, 0.0), (0.23, 0.52, 0.03), (0.46, 0.0)], [(0.23, 0.52), (0.23, 1.0)]],
    "Z": [[(0.0, 0.0), (0.46, 0.0, 0.03), (0.0, 1.0, 0.03), (0.46, 1.0)]],
    "-": [[(0.0, 0.5), (0.30, 0.5)]],
}
# Room beside a numeral, of its height, where its shape leaves a hole: the
# one's flag hangs over open space on its left, the seven's bar on its right
BEARINGS = {"1": (-0.05, 0.03), "7": (0.0, -0.04), "4": (-0.02, 0.0)}
SMALL_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"
NAMES = {"-": "Hyphen"}                # a resource's name for a glyph


def glyph(ch):
    """(paths, width): the glyph's tubes with its ink starting at x = 0."""
    paths = [bent(p) for p in GLYPHS[ch]]
    x0 = min(x for p in paths for x, _ in p)
    x1 = max(x for p in paths for x, _ in p)
    return [[(x - x0, y) for x, y in p] for p in paths], x1 - x0


# ---------------------------------------------------------------- the sprites

def ign(x, y):
    """Interleaved gradient noise: even, with no pattern the eye picks up."""
    f = 0.06711056 * x + 0.00583715 * y
    f = 52.9829189 * (f - math.floor(f))
    return f - math.floor(f)


def dithered(v, x, y):
    """A halo level with its noise: the watch's 16-bit colour then steps
    between neighbours instead of in rings, and the mean stays `v`."""
    u = ign(x, y)
    if v < DITHER / 2:
        return DITHER if u < v / DITHER else 0
    return min(255, int(v + (u - 0.5) * DITHER + 0.5))


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


class Sprites:
    """One screen width's masks: the numerals' halos, cores and standby
    tubes, the letters' halos and cores, and the whole-pixel sizes the view
    places them by (designs/gen_sign.py writes both)."""

    def __init__(self, w):
        self.w = w
        self.h = int(DIGIT * w + 0.5)                  # the numerals' height
        self.gap = int(GAP * self.h + 0.5)
        self.pad = int(PAD * w + 0.5)
        self.tube = TUBE * w
        self.m = int(math.ceil(self.tube / 2)) + 2     # a core's margin round the glyph's box
        self.thin = max(2.0, THIN * w)
        self.tm = int(math.ceil(self.thin / 2)) + 1
        self.sh = int(SMALL * w + 0.5)                 # the letters' height
        self.sgap = int(SMALL_GAP * self.sh + 0.5)
        self.space = int(SPACE * self.sh + 0.5)
        self.line = int(LINE * self.sh + 0.5)
        self.spad = int(SMALL_PAD * w + 0.5)
        self.stube = max(2.0, SMALL_TUBE * w)          # never under two pixels: a thinner line greys out
        self.sm = int(math.ceil(self.stube / 2)) + 2
        self._cache = {}

    def adv(self, ch, small=False):
        """A glyph's box width in pixels."""
        return int(glyph(ch)[1] * (self.sh if small else self.h) + 0.5)

    def bearings(self, ch):
        lb, rb = BEARINGS.get(ch, (0.0, 0.0))
        return int(math.floor(lb * self.h + 0.5)), int(math.floor(rb * self.h + 0.5))

    def strokes(self, ch, height, tube, margin):
        """The glyph's tubes as a mask at SS, its box `margin` in from the corner."""
        paths, width = glyph(ch)
        aw = int(width * height + 0.5)
        size = ((aw + 2 * margin) * SS, (height + 2 * margin) * SS)
        im = Image.new("L", size, 0)
        d = ImageDraw.Draw(im)
        t = max(2, int(tube * SS + 0.5))
        for p in paths:
            pts = [((margin + x * height) * SS, (margin + y * height) * SS) for x, y in p]
            d.line(pts, fill=255, width=t, joint="curve")
            for x, y in pts:                            # round ends, and round joins at every point
                d.ellipse((x - t / 2, y - t / 2, x + t / 2, y + t / 2), fill=255)
        return im

    def lit(self, ch, small=False):
        """(halo, core): two grey masks. The halo's cell is the glyph's box
        with `pad` round it, the core's with its margin."""
        key = (ch, small)
        if key in self._cache:
            return self._cache[key]
        height, tube, pad, m, glow = ((self.sh, self.stube, self.spad, self.sm, SMALL_GLOW) if small
                                      else (self.h, self.tube, self.pad, self.m, 1.0))
        big = self.strokes(ch, height, tube, pad)
        cw, chh = big.size[0] // SS, big.size[1] // SS
        core_mask = big.reduce(SS).crop((pad - m, pad - m, cw - pad + m, chh - pad + m))
        blurs = [(big.filter(ImageFilter.GaussianBlur(r * self.w * SS)).reduce(SS).tobytes(), k) for r, k in HALO]
        edge = 0.4 * pad                                 # the halo eases to nothing at its cell's edge
        out = bytearray(cw * chh)
        for y in range(chh):
            wy = smooth(min(y, chh - 1 - y) / edge)
            for x in range(cw):
                i = y * cw + x
                v = sum(b[i] * k for b, k in blurs) * glow
                if v <= 0.0:
                    continue
                v = min(255.0, v) * wy * smooth(min(x, cw - 1 - x) / edge)
                out[i] = dithered(v, x, y)
        halo = Image.frombytes("L", (cw, chh), bytes(out))
        self._cache[key] = (halo, core_mask)
        return self._cache[key]

    def standby(self, ch):
        """The standby tube: thin, no halo, in the font's four levels (the
        watch keeps two bits of a font's grey)."""
        key = (ch, "thin")
        if key not in self._cache:
            im = self.strokes(ch, self.h, self.thin, self.tm).reduce(SS)
            self._cache[key] = im
        return self._cache[key]


_SPRITES = {}


def sprites(w):
    if w not in _SPRITES:
        _SPRITES[w] = Sprites(w)
    return _SPRITES[w]


def two_bit(mask):
    """A font's grey as the watch keeps it."""
    return mask.point(lambda v: int(v / 85 + 0.5) * 85)


# ---------------------------------------------------------------- the face

def aod_offset(minute, step):
    """Lib.Aod.offset"""
    return ((minute % 5) - 2) * step, (((2 * minute + minute // 5 + 1) % 5) - 2) * step


def hours_text(hour, is24):
    if is24:
        return "%02d" % hour
    return str(hour % 12 or 12)


def title_lines(title):
    """A look's name in one line or two, split at its first space."""
    return title.split(" ", 1)


def places(w):
    """The whole-pixel places for a screen `w` wide: the time's centre line,
    its rows' tops, the date's centre, the standby shift's step."""
    return [int(v * w + 0.5) for v in (X, Y_HOURS, Y_MINUTES, DATE_X, DATE_Y)] + [int(AOD_STEP * w)]


def row_boxes(s, text, y):
    """Where each numeral's box goes: [(ch, x, y)], the row's ink centred on X."""
    x = 0
    xs = []
    for i, ch in enumerate(text):
        lb, rb = s.bearings(ch)
        if i > 0:
            x += s.gap + lb
        xs.append(x)
        x += s.adv(ch) + (rb if i < len(text) - 1 else 0)
    x0 = places(s.w)[0] - x // 2
    return [(ch, x0 + v, y) for ch, v in zip(text, xs)]


def line_boxes(s, text, y):
    """A line of letters centred on the date's centre: [(ch, x, y)]."""
    x = 0
    xs = []
    for i, ch in enumerate(text):
        if i > 0:
            x += s.sgap
        xs.append(x)
        x += s.space if ch == " " else s.adv(ch, True)
    x0 = places(s.w)[3] - x // 2
    return [(ch, x0 + v, y) for ch, v in zip(text, xs) if ch != " "]


def small_boxes(s, lines):
    cy = places(s.w)[4]
    if len(lines) == 1:
        return line_boxes(s, lines[0], cy - s.sh // 2)
    top = cy - (2 * s.sh + s.line) // 2
    return line_boxes(s, lines[0], top) + line_boxes(s, lines[1], top + s.sh + s.line)


def paste(img, mask, x, y, color):
    img.paste(Image.new("RGB", mask.size, color), (x, y), mask)


def face(w, hh, mm, lines, cols, asleep=False, minute=37, watch=False, hide=()):
    """The screen: `cols` are the hours', the minutes' and the details' tubes.
    `hide` leaves tubes out for a strike to draw: (row, index) for a numeral,
    "date" for the date."""
    s = sprites(w)
    img = Image.new("RGB", (w, w), (0, 0, 0))
    rows = ((hh, places(w)[1], cols[0]), (mm, places(w)[2], cols[1]))
    if asleep:
        dx, dy = aod_offset(minute, places(w)[5])
        for text, y, col in rows:
            for ch, x, yy in row_boxes(s, text, y):
                paste(img, two_bit(s.standby(ch)), x - s.tm + dx, yy - s.tm + dy, standby(col))
        return img
    for r, (text, y0, col) in enumerate(rows):          # a numeral at a time: its halo, then its core
        for i, (ch, x, y) in enumerate(row_boxes(s, text, y0)):
            if (r, i) in hide:
                continue
            halo, core_mask = s.lit(ch)
            paste(img, halo, x - s.pad, y - s.pad, col)
            paste(img, core_mask, x - s.m, y - s.m, core(col))
    small = [] if "date" in hide else [(s.lit(ch, True), x, y) for ch, x, y in small_boxes(s, lines)]
    for (halo, _), x, y in small:                       # the letters sit close: every halo, then every core
        paste(img, halo, x - s.spad, y - s.spad, cols[2])
    for (_, core_mask), x, y in small:
        paste(img, core_mask, x - s.sm, y - s.sm, core(cols[2]))
    return sixteen_bit(img) if watch else img


def sixteen_bit(img):
    """The colours cut to the watch's 16 bits."""
    r, g, b = img.split()
    return Image.merge("RGB", (r.point(lambda v: v & 0xF8), g.point(lambda v: v & 0xFC), b.point(lambda v: v & 0xF8)))


# ---------------------------------------------------------------- the strike
# How a numeral changes: the tube that changed is struck as a neon tube is,
# a stutter or two and a glow that spreads; when the minute turns while the
# face is awake the old tube dies first. Lib.Strike's tables and its
# whole-number arithmetic, copied exactly (the face's tests check values
# printed from here: --strike-values).

EMBER = (12, 5)
STRIKE_WAIT = 35
DEATH = 280
LONGEST = 965
FRAME = 50                             # ms between the face's frames
PATTERNS = (
    (0, 55, 18, 90, 55, 18, 105, 12, 5, 190, 12, 5, 205, 70, 28, 290, 70, 28, 305, 12, 5, 360, 12, 5,
     375, 50, 20, 500, 78, 42, 680, 93, 75, 860, 100, 100),
    (0, 45, 14, 70, 45, 14, 85, 12, 5, 200, 12, 5, 215, 75, 30, 330, 75, 30, 345, 12, 5, 390, 12, 5,
     405, 55, 22, 520, 80, 45, 690, 94, 78, 850, 100, 100),
    (0, 60, 20, 110, 60, 20, 125, 12, 5, 230, 12, 5, 245, 45, 16, 330, 70, 30, 380, 50, 22, 430, 72, 34,
     560, 85, 55, 720, 95, 82, 840, 100, 100),
)
DYING = (0, 100, 100, 50, 85, 60, 70, 20, 8, 120, 20, 8, 140, 60, 30, 190, 45, 18, 280, 0, 0)


def _div(a, b):
    """Whole-number division as Monkey C does it: toward zero."""
    return abs(a) // b if a >= 0 else -(abs(a) // b)


def _along(table, t, last):
    if t >= table[-3]:
        return last, last
    i = 3
    while table[i] <= t:
        i += 3
    t0, span = table[i - 3], table[i] - table[i - 3]
    return (table[i - 2] + _div((table[i + 1] - table[i - 2]) * (t - t0), span),
            table[i - 1] + _div((table[i + 2] - table[i - 1]) * (t - t0), span))


def strike_wait(seed):
    return ((seed * 37) % 4) * STRIKE_WAIT


def strike_lit(t, seed):
    """(core, halo) in percent, t ms after the strike: Lib.Strike.lit"""
    t -= strike_wait(seed)
    return (0, 0) if t < 0 else _along(PATTERNS[seed % len(PATTERNS)], t, 100)


def strike_dying(t):
    """Lib.Strike.dying"""
    return (100, 100) if t < 0 else _along(DYING, t, 0)


def strike_settled(t, seed):
    return t - strike_wait(seed) >= PATTERNS[seed % len(PATTERNS)][-3]


def dimmed(color, percent):
    """Lib.Neon.wash(color, 0, percent)"""
    return tuple(v * percent // 100 for v in color)


def changed(old, new):
    """The places of `new` whose numeral differs from `old`'s: all of them
    when the count of numerals changed (SignText.changed)."""
    if len(old) != len(new):
        return list(range(len(new)))
    return [i for i in range(len(new)) if old[i] != new[i]]


def strike_frame(w, old, new, t, death, cols, watch=False):
    """The face `t` ms after it changed from `old` to `new`, each (hours,
    minutes, date). On a wake the changed tubes are struck at once; with
    `death` (the minute turning while awake) the old ones die first."""
    s = sprites(w)
    ys = (places(w)[1], places(w)[2])
    acts = []                                           # (halo, core, x, y, pad, margin, colour, (core %, halo %))
    hide = set()
    born = t - DEATH if death else t
    for r in (0, 1):
        was, now = row_boxes(s, old[r], ys[r]), row_boxes(s, new[r], ys[r])
        for i in changed(old[r], new[r]):
            hide.add((r, i))
            seed = r * 2 + i
            if death and not strike_dying(t) == (0, 0):
                for ch, x, y in (was if len(was) != len(now) else [was[i]]):
                    acts.append(s.lit(ch) + (x, y, s.pad, s.m, cols[r], strike_dying(t)))
            ch, x, y = now[i]
            acts.append(s.lit(ch) + (x, y, s.pad, s.m, cols[r], strike_lit(born, seed)))
    if old[2] != new[2]:
        hide.add("date")
        if death:
            acts += [s.lit(ch, True) + (x, y, s.spad, s.sm, cols[2], strike_dying(t)) for ch, x, y in small_boxes(s, [old[2]])]
        acts += [s.lit(ch, True) + (x, y, s.spad, s.sm, cols[2], strike_lit(born, 4)) for ch, x, y in small_boxes(s, [new[2]])]
    img = face(w, new[0], new[1], [new[2]], cols, hide=hide)
    for halo, _, x, y, pad, _, col, (_, hp) in acts:    # every halo, then every core
        if hp > 0:
            paste(img, halo, x - pad, y - pad, dimmed(col, hp))
    for _, core_mask, x, y, _, m, col, (cp, _) in acts:
        if cp > 0:
            paste(img, core_mask, x - m, y - m, dimmed(core(col), cp))
    return sixteen_bit(img) if watch else img


def strike_length(old, new, death):
    """The ms until every changed tube has settled."""
    seeds = [r * 2 + i for r in (0, 1) for i in changed(old[r], new[r])] + ([4] if old[2] != new[2] else [])
    longest = max(strike_wait(k) + PATTERNS[k % len(PATTERNS)][-3] for k in seeds) if seeds else 0
    return longest + (DEATH if death else 0)


SCENES = (
    # name, what was showing, what shows now, whether the face was awake (the old tubes die)
    ("wake", ("10", "29", "TUE 15"), ("10", "37", "TUE 15"), False),
    ("wake-hour", ("09", "26", "TUE 15"), ("10", "37", "TUE 15"), False),
    ("turn", ("10", "37", "TUE 15"), ("10", "38", "TUE 15"), True),
)


def write_strikes(out, w=454):
    """A GIF of each scene at the face's frame rate, and a sheet of their frames."""
    cols = tubes()[0]
    rows = []
    for name, old, new, death in SCENES:
        length = strike_length(old, new, death)
        before = face(w, old[0], old[1], [old[2]], cols, asleep=not death, minute=int(old[1]))
        frames = [(on_watch(before), 700)]
        frames += [(on_watch(strike_frame(w, old, new, t, death, cols)), FRAME) for t in range(0, length + FRAME, FRAME)]
        frames[-1] = (frames[-1][0], 1500)
        gif = [f.resize((w * 3 // 4, w * 3 // 4), Image.LANCZOS).quantize(255, dither=Image.Dither.FLOYDSTEINBERG) for f, _ in frames]
        gif[0].save(out / f"strike-{name}.gif", save_all=True, append_images=gif[1:], duration=[d for _, d in frames], loop=0)
        picks = [0, 50, 100, 150, 200, 250, 300, 350, 400, 500, 600, 700, 800, 900] if not death else \
                [0, 50, 100, 150, 200, 250, 300, 350, 400, 500, 600, 700, 900, 1100]
        rows += [tile(strike_frame(w, old, new, t, death, cols), f"{name}  {t} ms", 0.5) for t in picks]
        print(f"wrote {out / f'strike-{name}.gif'}: {len(frames)} frames, {length} ms")
    grid(rows, 14).save(out / "preview-strike.png")
    print(f"wrote {out / 'preview-strike.png'}")


def strike_values():
    """Lib.Strike's values for the face's tests."""
    for seed in range(5):
        print(f"seed {seed} wait {strike_wait(seed)}:", " ".join("%d:%d/%d" % ((t,) + strike_lit(t, seed)) for t in (0, 40, 100, 150, 250, 333, 420, 600, 777, 900, 965)))
    print("dying:", " ".join("%d:%d/%d" % ((t,) + strike_dying(t)) for t in (0, 25, 60, 100, 130, 160, 240, 279, 280)))


def disc(w):
    m = Image.new("L", (w * 4, w * 4), 0)
    ImageDraw.Draw(m).ellipse((0, 0, w * 4 - 1, w * 4 - 1), fill=255)
    return m.resize((w, w), Image.LANCZOS)


def lit_share(img):
    """The share of the round screen lit."""
    w = img.size[0]
    m = disc(w).point(lambda v: 255 if v > 127 else 0)
    on = img.convert("L").point(lambda v: 255 if v > 8 else 0)
    both = Image.composite(on, Image.new("L", on.size, 0), m)
    return both.histogram()[255] / m.histogram()[255]


def on_watch(img):
    """The screen in its round bezel, on the sheets' grey."""
    out = Image.new("RGB", img.size, (26, 26, 28))
    out.paste(img, (0, 0), disc(img.size[0]))
    return out


# ---------------------------------------------------------------- the looks

LOOKS = {"yours": None, "red": "BRIGHT", "blue": "BRIGHT_BLUE", "green": "BRIGHT_GREEN", "low": "LOW", "daily": "DAILY"}
TITLES = {"yours": "YOUR LOOK", "red": "HI-VIS RED", "blue": "HI-VIS BLUE", "green": "HI-VIS GREEN", "low": "LOW LIGHT"}


def tubes(look="yours", day=0, yours=("ROSE", "TURQUOISE", "AMBER")):
    """(the three colours, the look's title): Lib.Neon.colors and title."""
    if look == "daily":
        name = list(NEON_SETS)[day % len(NEON_SETS)]
        names = NEON_SETS[name]
    else:
        name = TITLES[look]
        names = NEON_LOOKS[LOOKS[look]] if LOOKS[look] else yours
    return [rgb("TUBE_" + n) for n in names], name


# ---------------------------------------------------------------- the sheets

def label(text, width, height=30, size=17):
    im = Image.new("RGB", (width, height), (16, 16, 16))
    try:
        f = ImageFont.load_default(size)
    except TypeError:
        f = ImageFont.load_default()
    ImageDraw.Draw(im).text((8, height // 2), text, font=f, fill=(210, 210, 210), anchor="lm")
    return im


def tile(img, text, scale=1.0):
    img = on_watch(img)
    if scale != 1.0:
        img = img.resize((int(img.size[0] * scale), int(img.size[1] * scale)), Image.LANCZOS)
    out = Image.new("RGB", (img.size[0], img.size[1] + 30), (16, 16, 16))
    out.paste(label(text, img.size[0]), (0, 0))
    out.paste(img, (0, 30))
    return out


def grid(tiles, columns, gap=8):
    tw, th = max(t.size[0] for t in tiles), max(t.size[1] for t in tiles)
    rows = (len(tiles) + columns - 1) // columns
    out = Image.new("RGB", (columns * (tw + gap) - gap, rows * (th + gap) - gap), (16, 16, 16))
    for i, t in enumerate(tiles):
        out.paste(t, ((i % columns) * (tw + gap), (i // columns) * (th + gap)))
    return out


def sheet_numerals(out, w=454):
    """Every numeral at the face's size, lit and in standby, and the letters
    at theirs and three times enlarged."""
    s = sprites(w)
    rose, teal, amber = tubes()[0]
    width = 2 * s.pad + sum(s.adv(c) for c in "0123456789") + 9 * s.gap
    rows = []
    for half in ("01234", "56789"):
        im = Image.new("RGB", (width // 2 + s.pad * 2, s.h + 2 * s.pad), (0, 0, 0))
        st = Image.new("RGB", im.size, (0, 0, 0))
        x = s.pad
        places = []
        for ch in half:
            places.append((ch, x))
            x += s.adv(ch) + s.gap + 14
        col = rose if half == "01234" else teal
        for ch, x in places:
            paste(im, s.lit(ch)[0], x - s.pad, 0, col)
        for ch, x in places:
            paste(im, s.lit(ch)[1], x - s.m, s.pad - s.m, core(col))
            paste(st, two_bit(s.standby(ch)), x - s.tm, s.pad - s.tm, standby(col))
        rows += [im, st]
    text = ["ABCDEFGHIJKLM", "NOPQRSTUVWXYZ", "0123456789-", "TUE 15  WED 28", "HI-VIS GREEN", "LAST CALL  DOWNTOWN"]
    small = Image.new("RGB", (rows[0].size[0], len(text) * (s.sh + 2 * s.spad - 16) + 16), (0, 0, 0))
    for i, t in enumerate(text):
        x, y = s.spad, i * (s.sh + 2 * s.spad - 16) + s.spad
        jobs = []
        for ch in t:
            if ch != " ":
                jobs.append((ch, x))
            x += (s.space if ch == " " else s.adv(ch, True)) + s.sgap
        for ch, xx in jobs:
            paste(small, s.lit(ch, True)[0], xx - s.spad, y - s.spad, amber)
        for ch, xx in jobs:
            paste(small, s.lit(ch, True)[1], xx - s.sm, y - s.sm, core(amber))
    big = small.resize((small.size[0] * 3, small.size[1] * 3), Image.NEAREST).crop((0, 0, small.size[0], small.size[1] * 3))
    parts = rows + [small, big]
    sheet = Image.new("RGB", (rows[0].size[0], sum(p.size[1] for p in parts) + 8 * len(parts)), (16, 16, 16))
    y = 0
    for p in parts:
        sheet.paste(p, (0, y))
        y += p.size[1] + 8
    sheet.save(out)


def sheet_hours(out, w=454):
    """Every hour in both clocks with a spread of minutes: the pair must
    stay balanced when the hour is 1 or 20."""
    minutes = (0, 11, 24, 37, 48, 59, 5, 10, 17, 21, 32, 40, 56, 9, 14, 28, 35, 43, 51, 6, 12, 23, 47, 58)
    cols = tubes()[0]
    tiles = []
    for hour in range(24):
        hh, mm = hours_text(hour, True), "%02d" % minutes[hour]
        tiles.append(tile(face(w, hh, mm, ["TUE 15"], cols), f"24 h  {hh}:{mm}", 0.5))
    for hour in range(1, 13):
        hh, mm = hours_text(hour, False), "%02d" % minutes[(hour * 5) % 24]
        tiles.append(tile(face(w, hh, mm, ["SAT %d" % (hour * 2 + 3)], cols), f"12 h  {hh}:{mm}", 0.5))
    grid(tiles, 9).save(out)


def sheet_looks(out, w=454):
    """Every set and every other look, lit and in standby, and three of the
    owner's own choices with the dark tubes."""
    tiles = []
    kinds = [("daily", d, None) for d in range(len(NEON_SETS))] + [(k, 0, None) for k in ("red", "blue", "green", "low")]
    kinds += [("yours", 0, y) for y in (("RUBY", "COBALT", "LEMON"), ("PURPLE", "RUBY", "COBALT"), ("COBALT", "PURPLE", "RUBY"))]
    for asleep in (False, True):
        for look, day, yours in kinds:
            cols, name = tubes(look, day, yours or ("ROSE", "TURQUOISE", "AMBER"))
            if yours:
                name = " ".join(n.title() for n in yours)
            im = face(w, "10", "37", ["TUE 15"], cols, asleep)
            tiles.append(tile(im, name + (f"  standby {lit_share(im):.1%}" if asleep else ""), 0.5))
    grid(tiles, 7).save(out)


def sheet_titles(out, w=454):
    """The look's name where the date is, as after a hold."""
    tiles = []
    for look, day in [(k, 0) for k in ("yours", "red", "blue", "green", "low")] + [("daily", d) for d in range(len(NEON_SETS))]:
        cols, name = tubes(look, day)
        tiles.append(tile(face(w, "20", "00", title_lines(name), cols), name, 0.5))
    grid(tiles, 6).save(out)


def sheet_sizes(out):
    """The five screen sizes at their own size, lit and in standby with the
    worst minute's lit share."""
    cols = tubes()[0]
    tiles = []
    for asleep in (False, True):
        for w in WIDTHS:
            im = face(w, "10", "37", ["TUE 15"], cols, asleep)
            note = f"{w} px"
            if asleep:
                worst = max(lit_share(face(w, hh, "08", [], cols, True)) for hh in ("08", "20", "00"))
                note += f"  standby {lit_share(im):.1%} (most, 08:08 {worst:.1%})"
            tiles.append(tile(im, note))
    grid(tiles, 5).save(out)


def sheet_face(out, w=454):
    """Lit and standby side by side, as the mockup."""
    cols = tubes()[0]
    a, b = face(w, "10", "37", ["TUE 15"], cols), face(w, "10", "37", ["TUE 15"], cols, True)
    grid([tile(a, "Sign  ·  awake"), tile(b, f"standby, {lit_share(b):.1%} lit")], 2, 12).save(out)


def main(argv):
    if argv and argv[0] == "--sheets":
        out = Path(argv[1])
        out.mkdir(parents=True, exist_ok=True)
        pick = set(argv[2:])
        for name, fn in (("face", sheet_face), ("numerals", sheet_numerals), ("hours", sheet_hours),
                         ("looks", sheet_looks), ("titles", sheet_titles), ("sizes", sheet_sizes)):
            if not pick or name in pick:
                fn(out / f"preview-{name}.png")
                print(f"wrote {out / f'preview-{name}.png'}")
        return
    if argv and argv[0] == "--strike":
        out = Path(argv[1])
        out.mkdir(parents=True, exist_ok=True)
        write_strikes(out)
        return
    if argv and argv[0] == "--strike-values":
        strike_values()
        return
    out = argv[0]
    opts = dict(a.split("=", 1) for a in argv[1:] if "=" in a)
    flags = [a for a in argv[1:] if "=" not in a]
    w = next((int(a) for a in flags if a.isdigit()), 454)
    hour, minute = (int(v) for v in opts.get("time", "10:37").split(":"))
    yours = (opts.get("hours", "ROSE"), opts.get("minutes", "TURQUOISE"), opts.get("detail", "AMBER"))
    cols, name = tubes(opts.get("look", "yours"), int(opts.get("day", 0)), yours)
    lines = title_lines(name) if opts.get("title") == "1" else [opts.get("date", "TUE 15")]
    is24 = opts.get("format", "24") == "24"
    if "strike" in opts:                                # a frame of a strike: from=09:36 strike=150 [turn=1]
        h0, m0 = (int(v) for v in opts.get("from", "09:36").split(":"))
        im = strike_frame(w, (hours_text(h0, is24), "%02d" % m0, opts.get("was", lines[0])), (hours_text(hour, is24), "%02d" % minute, lines[0]),
                          int(opts["strike"]), opts.get("turn") == "1", cols, opts.get("watch") == "1")
    else:
        im = face(w, hours_text(hour, is24), "%02d" % minute, lines, cols, "standby" in flags, minute, opts.get("watch") == "1")
    on_watch(im).save(out)
    print(f"{out}: {w} px, {lit_share(im):.1%} of the screen lit")


if __name__ == "__main__":
    main(sys.argv[1:])
