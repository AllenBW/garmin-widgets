#!/usr/bin/env python3
"""Render the Edge face (design #58) as EdgeView draws it: the same masks
(designs/gen_edge.py bakes them into the watch's bitmaps), set at the
same whole pixels, coloured and laid over each other the same way.

Enormous numerals that are not drawn: only their edges catch the light,
the hours' tube on the edges facing the upper left and the minutes' on
those facing the lower right (designs/edge_runs.py makes the runs). A lit
tube is a halo in its colour and a core washed toward white; standby is
the thin tubes alone. Every colour is a tube from the dictionary
(designs/colors.py), by the look.

    python3 -I designs/preview_edge.py                    # the whole set, into designs/edge/
    python3 -I designs/preview_edge.py out.png [key=value ...]

    w=454            the screen (466, 454, 416, 390, 360)
    time=10:37       date="TUE 15"
    standby=1        the thin tubes alone
    title=1          the look's name in place of the date, as after a hold
    plain=1          as a watch that cannot tint a bitmap draws it (the
                     Forerunner 165 and 70): the halo in three font layers
    strike=MS        one frame of the number transition, MS after the face
                     changed from from=HH:MM (09:26) to the time; turn=1 for
                     the minute turning while awake (the old numeral dies)
    look=yours|red|blue|green|low|daily     day=0..6 (the daily look's set)
    hours=ROSE minutes=TURQUOISE detail=AMBER   (your tubes; any of colors.TUBES)

Prints the share of the round screen lit. Pillow only.
"""
import sys
from functools import lru_cache
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))                                   # run with -I
import edge_runs as er                                          # noqa: E402
import preview_sign as ps                                       # noqa: E402  Lib.Strike's tables
from colors import NEON_LOOKS, NEON_SETS, TUBES, core, rgb, standby  # noqa: E402

OUT = HERE / "edge"
WIDTHS = [466, 454, 416, 390, 360]   # fenix 9 Pro 51 mm; fenix 8 47/51 mm; fenix 8 43 mm; Venu 4 41 mm; Forerunner 265S
SS = 8                               # the tubes are drawn this many times over size

# The layout, in fractions of the screen width (EdgeView has the same)
CX = 0.44                    # the numerals' centre: left of the middle, the date to their right
ROW_GAP = 0.022              # between the hours and the minutes
DATE_X = 0.80                # the date's centre
DATE_H = 0.042               # its letters' height
DATE_TUBE = 0.0048           # and their tube
LINE_GAP = 0.030             # between a two-line title's lines
SHIFT = 0.006                # standby's step (Lib.Aod.offset)

# The halo, as the mockup's neon(): Gaussians of these radii at these
# strengths, added; the numerals glow at 0.9 of it and the date at 0.7
HALO = ((0.009, 1.0), (0.030, 0.78), (0.075, 0.34))
GLOW, DATE_GLOW = 0.9, 0.7
DITHER = 14                  # the halo's grain, in 255ths of its strength
PAD = 0.105                  # the halo kept round a numeral (it fades to nothing over the outer third)
DATE_PAD = 0.050

LOOKS = {"red": "BRIGHT", "blue": "BRIGHT_BLUE", "green": "BRIGHT_GREEN", "low": "LOW"}
TITLES = {"yours": "YOUR LOOK", "red": "HI-VIS RED", "blue": "HI-VIS BLUE", "green": "HI-VIS GREEN", "low": "LOW LIGHT"}
DEFAULTS = dict(w=454, time="10:37", date="TUE 15", standby=0, title=0, plain=0, strike=-1, turn=0, look="yours", day=0,
                hours="ROSE", minutes="TURQUOISE", detail="AMBER")


# ---------------------------------------------------------------- masks

def tube(paths, size, width):
    """A mask `size` (w, h) px of round-ended tubes `width` px wide along
    `paths` (points in px), anti-aliased."""
    big = Image.new("L", (size[0] * SS, size[1] * SS), 0)
    d = ImageDraw.Draw(big)
    r = width * SS / 2
    for pts in paths:
        pts = [(x * SS, y * SS) for x, y in pts]
        for (x0, y0), (x1, y1) in zip(pts, pts[1:] + pts[-1:]):
            n = max(1, int(((x1 - x0) ** 2 + (y1 - y0) ** 2) ** 0.5 / (r / 3)))
            for k in range(n):
                x, y = x0 + (x1 - x0) * k / n, y0 + (y1 - y0) * k / n
                d.ellipse((x - r, y - r, x + r, y + r), fill=255)
    return big.resize(size, Image.BOX)


def strength(mask, w, k, pad, fade):
    """A tube mask's halo, as floats of 255 a pixel: the Gaussians added,
    fading to nothing over the outer `fade` of `pad` px so its cell has no
    edge; and each pixel's dither, 0 to 1 (interleaved gradient noise)."""
    blurs = [mask.filter(ImageFilter.GaussianBlur(r * w)).tobytes() for r, _ in HALO]
    ks = [h * k for _, h in HALO]
    wd, ht = mask.size
    fade = max(1, int(pad * fade))
    ramp = [min(1.0, (i + 0.5) / fade) for i in range(max(wd, ht))]
    ramp = [t * t * (3 - 2 * t) for t in ramp]
    out, noise = [], []
    i = 0
    for y in range(ht):
        fy = ramp[min(y, ht - 1 - y)]
        for x in range(wd):
            out.append((blurs[0][i] * ks[0] + blurs[1][i] * ks[1] + blurs[2][i] * ks[2]) * fy * ramp[min(x, wd - 1 - x)])
            noise.append((52.9829189 * ((0.06711056 * x + 0.00583715 * y) % 1.0)) % 1.0)
            i += 1
    return out, noise


def halo(mask, w, k, pad, fade=1 / 3):
    """The halo as a mask of 256 levels, for a bitmap the watch tints. The
    watch shows 16-bit colour, which would step a dim halo in rings, so the
    strength is dithered by DITHER (never by more than the strength itself,
    so the faint end keeps its mean and fades to nothing): the rings break
    into a grain too fine to see."""
    values, noise = strength(mask, w, k, pad, fade)
    out = bytearray(len(values))
    for i, v in enumerate(values):
        v += (noise[i] - 0.5) * min(DITHER, 2 * v)
        out[i] = 255 if v > 255 else (0 if v < 0 else int(v + 0.5))
    return Image.frombytes("L", mask.size, bytes(out))


# Where a watch cannot tint a bitmap (no 8-bit alpha in its bitmaps: the
# Forerunner 165 and 70) the halo is three bitmap fonts laid over each
# other. A font's mask has four levels (0, 1/3, 2/3, 1), so the first is
# drawn in the tube's colour at LAYERS[0], the second at LAYERS[1], the
# third in the colour itself: the faint end, where steps show most, gets
# the finest steps (a third of LAYERS[0]), and the dither covers the rest.
LAYERS = (0.14, 0.36, 1.0)


@lru_cache(maxsize=None)
def _combos():
    """What three layers can make, sorted: (strength, (level, level, level))."""
    made = {}
    for c in range(4):
        for a in range(4):
            for b in range(4):
                v = b / 3 * LAYERS[2] + (1 - b / 3) * (a / 3 * LAYERS[1] + (1 - a / 3) * c / 3 * LAYERS[0])
                made.setdefault(round(v, 6), (c, a, b))
    return sorted(made.items())


def layered(mask, w, k, pad, fade=1 / 3):
    """The halo as three masks of four levels, one a layer."""
    values, noise = strength(mask, w, k, pad, fade)
    combos = _combos()
    table = []                                    # for each strength of 255: the combos below and above it
    j = 0
    for v in range(256):
        while j + 1 < len(combos) - 1 and combos[j + 1][0] <= v / 255:
            j += 1
        table.append((combos[j], combos[j + 1]))
    outs = [bytearray(len(values)) for _ in LAYERS]
    for i, v in enumerate(values):
        v = min(255.0, v)
        (lo, lc), (hi, hc) = table[int(v)]
        pick = hc if (v / 255 - lo) > noise[i] * (hi - lo) else lc
        for n in range(3):
            outs[n][i] = pick[n] * 85
    return [Image.frombytes("L", mask.size, bytes(o)) for o in outs]


def four(mask):
    """A mask as a bitmap font holds it: four levels."""
    return mask.point(lambda v: (v + 42) // 85 * 85)


def metrics(w):
    """The face's whole pixels on a `w` px screen: what Layout.mc holds."""
    em = er.EM * w
    adv, _, _ = er.metrics()
    h = round(er.height() * em)
    gap = round(ROW_GAP * w)
    y0 = (w - gap) // 2 - h
    lh = round(DATE_H * w)
    return dict(em=em, h=h, adv={c: round(a * em) for c, a in adv.items()}, y=(y0, y0 + h + gap), cx=round(CX * w),
                pad=round(PAD * w), core_pad=2, date_x=round(DATE_X * w), letter=lh, letter_pad=round(DATE_PAD * w),
                letter_adv={c: max(1, round(a * lh)) for c, (a, _) in er.LETTERS.items()},
                letter_gap=round(er.LETTER_GAP * lh),
                letter_cell=max(max(1, round(a * lh)) for a, _ in er.LETTERS.values()), line_gap=round(LINE_GAP * w), shift=int(SHIFT * w))


@lru_cache(maxsize=None)
def digit_mask(c, light, w, kind):
    """One digit's tubes of one light (edge_runs.UL or LR) on a `w` px
    screen: "core" (the lit tube), "glow" (its halo) or "thin" (standby);
    for a watch that cannot tint, "layer0" to "layer2" (the halo's three
    font layers) and "core4" (the core in a font's four levels). The cell
    is the digit's box with a pad all round: metrics()'s `pad` for a halo,
    `core_pad` for the others."""
    m = metrics(w)
    soft = kind == "glow" or kind.startswith("layer")
    pad = m["pad"] if soft else m["core_pad"]
    size = (m["adv"][c] + 2 * pad, m["h"] + 2 * pad)
    paths = [[(pad + x * m["em"], pad + y * m["em"]) for x, y in p] for lt, p in er.digit(c)[1] if lt == light]
    mask = tube(paths, size, (er.THIN if kind == "thin" else er.TUBE) * w)
    if kind == "glow":
        return halo(mask, w, GLOW, pad)
    if soft:
        return _digit_layers(c, light, w)[int(kind[-1])]
    return four(mask) if kind in ("thin", "core4") else mask


@lru_cache(maxsize=None)
def _digit_layers(c, light, w):
    m = metrics(w)
    return layered(_padded(digit_mask(c, light, w, "core"), m["pad"] - m["core_pad"]), w, GLOW, m["pad"])


def _padded(mask, by):
    """A mask with `by` px of nothing added all round."""
    out = Image.new("L", (mask.width + 2 * by, mask.height + 2 * by), 0)
    out.paste(mask, (by, by))
    return out


@lru_cache(maxsize=None)
def letter_mask(c, w, kind):
    """One letter of the date's lettering: "core" or "glow", or "layer0" to
    "layer2" and "core4" as digit_mask's; its cell is the letter's box with
    metrics()'s `letter_pad` all round."""
    m = metrics(w)
    pad, lh = m["letter_pad"], m["letter"]
    if kind.startswith("layer"):
        return _letter_layers(c, w)[int(kind[-1])]
    size = (m["letter_adv"][c] + 2 * pad, lh + 2 * pad)
    # the tube's centre line runs inside the letter's box, half a tube in
    t = DATE_TUBE * w
    a = er.LETTERS[c][0]
    sx = (m["letter_adv"][c] - t) / a if a else 0
    paths = [[(pad + t / 2 + x * sx, pad + t / 2 + y * (lh - t)) for x, y in p] for p in er.LETTERS[c][1]]
    mask = tube(paths, size, t)
    if kind == "glow":
        return halo(mask, w, DATE_GLOW, pad, 0.6)
    return four(mask) if kind == "core4" else mask


@lru_cache(maxsize=None)
def _letter_layers(c, w):
    return layered(letter_mask(c, w, "core"), w, DATE_GLOW, metrics(w)["letter_pad"], 0.6)


# ---------------------------------------------------------------- the face

def tubes(st):
    """The look's three tubes, as (r, g, b): hours, minutes, details
    (Lib.Neon.colors)."""
    look = st["look"]
    if look == "daily":
        names = list(NEON_SETS.values())[st["day"] % len(NEON_SETS)]
    elif look in LOOKS:
        names = NEON_LOOKS[LOOKS[look]]
    else:
        names = (st["hours"], st["minutes"], st["detail"])
    return [rgb("TUBE_" + n) for n in names]


def title(st):
    return list(NEON_SETS)[st["day"] % len(NEON_SETS)] if st["look"] == "daily" else TITLES[st["look"]]


def lines(s):
    """A title's lines: two where it has a space (HI-VIS / GREEN)."""
    return s.split(" ") if " " in s else [s]


def aod_offset(minute, step):
    """Lib.Aod.offset."""
    return ((minute % 5) - 2) * step, (((2 * minute + minute // 5 + 1) % 5) - 2) * step


def dimmed(colour, percent):
    """Lib.Neon.wash(colour, 0, percent)."""
    return tuple(v * percent // 100 for v in colour)


def row_places(m, s, y):
    """Each numeral of a row and its box's corner: (digit, x, y)."""
    out, x = [], m["cx"] - sum(m["adv"][c] for c in s) // 2
    for c in s:
        out.append((c, x, y))
        x += m["adv"][c]
    return out


def letter_spots(m, w, text):
    """Each letter of the date's lines and its box's corner: (letter, x, y)."""
    lh = m["letter"]
    block = len(text) * lh + (len(text) - 1) * m["line_gap"]
    spots = []
    for k, s in enumerate(text):
        x = m["date_x"] - (sum(m["letter_adv"][c] for c in s) + m["letter_gap"] * (len(s) - 1)) // 2
        for c in s:
            if c != " ":
                spots.append((c, x, (w - block) // 2 + k * (lh + m["line_gap"])))
            x += m["letter_adv"][c] + m["letter_gap"]
    return spots


def lay_digit(img, w, c, x, y, kind, colours):
    """One numeral's two lights from its masks of one kind."""
    m = metrics(w)
    pad = m["core_pad"] if kind in ("core", "core4", "thin") else m["pad"]
    for light in (er.UL, er.LR):
        img.paste(colours[light], (x - pad, y - pad), digit_mask(c, light, w, kind))


def lay_letters(img, w, spots, kind, colour):
    pad = metrics(w)["letter_pad"]
    for c, x, y in spots:
        img.paste(colour, (x - pad, y - pad), letter_mask(c, w, kind))


def passes(plain):
    """The masks the lit face is laid from, in order, with what dims each:
    (kind, halo or core, percent of the tube's colour)."""
    if plain:
        return [(f"layer{n}", "halo", round(level * 100)) for n, level in enumerate(LAYERS)] + [("core4", "core", 100)]
    return [("glow", "halo", 100), ("core", "core", 100)]


def face(st, hide=()):
    """The face at 1x, as EdgeView draws it; `hide` leaves out numerals
    ((row, place)) and "date", which a strike draws itself."""
    w = st["w"]
    m = metrics(w)
    img = Image.new("RGB", (w, w), (0, 0, 0))
    hours, minutes = st["time"].split(":")
    cols = tubes(st)
    thin = bool(st["standby"])
    dx, dy = aod_offset(int(minutes), m["shift"]) if thin else (0, 0)
    cells = [(c, x + dx, y + dy) for row, s in enumerate((hours, minutes))
             for i, (c, x, y) in enumerate(row_places(m, s, m["y"][row])) if (row, i) not in hide]
    if thin:
        for c, x, y in cells:
            lay_digit(img, w, c, x, y, "thin", [standby(k) for k in cols])
        return img
    text = lines(title(st)) if st["title"] else [st["date"]]
    spots = letter_spots(m, w, text) if st["title"] or "date" not in hide else []
    # every halo first, then the cores over them
    for kind, part, percent in passes(st["plain"]):
        tint = (lambda c: dimmed(c, percent)) if part == "halo" else core
        for c, x, y in cells:
            lay_digit(img, w, c, x, y, kind, [tint(k) for k in cols])
        lay_letters(img, w, spots, kind, tint(cols[2]))
    return img


# ---------------------------------------------------------------- the strike
# How a numeral changes (Lib.Strike, whose tables and whole-number
# arithmetic preview_sign has copied exactly): on a wake the numerals that
# changed are struck as a neon tube is, a stutter or two and a glow that
# spreads; when the minute turns while the face is awake the old numeral
# dies first. A numeral's two lights share one seed (its place), so it
# comes on as one; the date's seed is 4.

def changed(old, new):
    """The places of `new` whose numeral differs from `old`'s: all of them
    when the count of numerals changed (EdgeView.changed)."""
    return list(range(len(new))) if len(old) != len(new) else [i for i in range(len(new)) if old[i] != new[i]]


def strike_frame(st, old, new, t, death):
    """The face `t` ms after it changed from `old` to `new`, each (hours,
    minutes, date): what EdgeView draws on that frame."""
    w = st["w"]
    m = metrics(w)
    cols = tubes(st)
    born = t - ps.DEATH if death else t
    hide, acts = set(), []                         # acts: (digit or None, x, y, text, (core %, halo %))
    for r in (0, 1):
        was, now = row_places(m, old[r], m["y"][r]), row_places(m, new[r], m["y"][r])
        for k, i in enumerate(changed(old[r], new[r])):
            hide.add((r, i))
            if death:
                acts += [(c, x, y, None, ps.strike_dying(t)) for j, (c, x, y) in enumerate(was)
                         if (j == i if len(was) == len(now) else k == 0)]
            c, x, y = now[i]
            acts.append((c, x, y, None, ps.strike_lit(born, r * 2 + i)))
    if old[2] != new[2]:
        hide.add("date")
        if death:
            acts.append((None, 0, 0, old[2], ps.strike_dying(t)))
        acts.append((None, 0, 0, new[2], ps.strike_lit(born, 4)))
    img = face(dict(st, time=f"{new[0]}:{new[1]}", date=new[2], standby=0, title=0), hide)
    for kind, part, percent in passes(st["plain"]):
        for c, x, y, text, (cp, hp) in acts:
            level = percent * hp // 100 if part == "halo" else cp
            if level <= 0:
                continue
            tint = (lambda k: dimmed(k, level)) if part == "halo" else (lambda k: dimmed(core(k), level))
            if c is None:
                lay_letters(img, w, letter_spots(m, w, [text]), kind, tint(cols[2]))
            else:
                lay_digit(img, w, c, x, y, kind, [tint(k) for k in cols])
    return img


def strike_length(old, new, death):
    """The ms until every changed tube has settled."""
    seeds = [r * 2 + i for r in (0, 1) for i in changed(old[r], new[r])] + ([4] if old[2] != new[2] else [])
    longest = max(ps.strike_wait(k) + ps.PATTERNS[k % len(ps.PATTERNS)][-3] for k in seeds) if seeds else 0
    return longest + (ps.DEATH if death else 0)


SCENES = (
    # name, what was showing, what shows now, whether the face was awake (the old tubes die)
    ("wake", ("10", "29", "TUE 15"), ("10", "37", "TUE 15"), False),
    ("wake-hour", ("09", "26", "TUE 15"), ("10", "37", "TUE 15"), False),
    ("turn", ("10", "37", "TUE 15"), ("10", "38", "TUE 15"), True),
)


def write_strikes(out, w=454):
    """A GIF of each scene at the face's frame rate, and a sheet of their
    frames; and the Forerunner 165's way (font layers) for one scene."""
    st = dict(DEFAULTS, w=w)
    rows = []
    for name, old, new, death in SCENES:
        length = strike_length(old, new, death)
        before = face(dict(st, time=f"{old[0]}:{old[1]}", date=old[2], standby=0 if death else 1))
        frames = [(watch(before), 700)]
        frames += [(watch(strike_frame(st, old, new, t, death)), ps.FRAME) for t in range(0, length + ps.FRAME, ps.FRAME)]
        frames[-1] = (frames[-1][0], 1500)
        gif = [f.resize((w * 3 // 4, w * 3 // 4), Image.LANCZOS).quantize(255, dither=Image.Dither.FLOYDSTEINBERG) for f, _ in frames]
        gif[0].save(out / f"strike-{name}.gif", save_all=True, append_images=gif[1:], duration=[d for _, d in frames], loop=0)
        picks = [0, 50, 100, 150, 200, 250, 300, 350, 400, 500, 600, 700, 800, 900] if not death else \
                [0, 50, 100, 150, 200, 250, 300, 350, 400, 500, 600, 700, 900, 1100]
        rows += [label_tile(watch(strike_frame(st, old, new, t, death)), f"{name}  {t} ms", 227) for t in picks]
        print(f"strike-{name}.gif: {len(frames)} frames, {length} ms")
    plain = dict(DEFAULTS, w=390, plain=1)
    name, old, new, death = SCENES[1]
    rows += [label_tile(watch(strike_frame(plain, old, new, t, death)), f"165: {name}  {t} ms", 227)
             for t in (0, 50, 100, 150, 200, 250, 300, 350, 400, 500, 600, 700, 800, 900)]
    frames = [(watch(face(dict(plain, time="09:26", standby=1))), 700)]
    frames += [(watch(strike_frame(plain, old, new, t, death)), ps.FRAME) for t in range(0, strike_length(old, new, death) + ps.FRAME, ps.FRAME)]
    frames[-1] = (frames[-1][0], 1500)
    gif = [f.quantize(255, dither=Image.Dither.FLOYDSTEINBERG) for f, _ in frames]
    gif[0].save(out / "strike-wake-hour-plain.gif", save_all=True, append_images=gif[1:], duration=[d for _, d in frames], loop=0)
    grid(rows, 14, out / "strike.png")


def label_tile(img, text, size):
    img = img.resize((size, size), Image.LANCZOS)
    out = Image.new("RGB", (size, size + 34), (12, 12, 12))
    out.paste(label(text, size), (0, 0))
    out.paste(img, (0, 34))
    return out


# ---------------------------------------------------------------- output

def disc(n):
    m = Image.new("L", (n, n), 0)
    ImageDraw.Draw(m).ellipse((0, 0, n - 1, n - 1), fill=255)
    return m


def lit_share(img):
    """The share of the round screen with any light at all."""
    m = disc(img.width)
    on = Image.merge("RGB", img.split()).convert("L").point(lambda v: 255 if v > 0 else 0)
    lit = sum(1 for a, b in zip(on.tobytes(), m.tobytes()) if a and b)
    return lit / m.histogram()[255]


def watch(img):
    """The square render as the round screen on grey."""
    out = Image.new("RGB", img.size, (24, 24, 24))
    out.paste(img, (0, 0), disc(img.width))
    return out


def label(text, width, height=34):
    im = Image.new("RGB", (width, height), (12, 12, 12))
    f = ImageFont.truetype(str(Path.home() / "Library/Application Support/Garmin/ConnectIQ/Fonts/Roboto-Regular.ttf"), 18)
    ImageDraw.Draw(im).text((10, height // 2), text, font=f, fill=(200, 200, 200), anchor="lm")
    return im


def tile(st, text=None, size=None):
    """A labelled round render."""
    img = watch(face(st))
    if size and size != img.width:
        img = img.resize((size, size), Image.LANCZOS)
    if text is None:
        return img
    out = Image.new("RGB", (img.width, img.height + 34), (12, 12, 12))
    out.paste(label(text, img.width), (0, 0))
    out.paste(img, (0, 34))
    return out


def grid(tiles, cols, path):
    tw, th = max(t.width for t in tiles), max(t.height for t in tiles)
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (tw + 10) + 10, rows * (th + 10) + 10), (12, 12, 12))
    for k, t in enumerate(tiles):
        sheet.paste(t, (10 + (k % cols) * (tw + 10), 10 + (k // cols) * (th + 10)))
    sheet.save(path)


def digits_sheet(path, w=454, scale=2):
    """Every digit on its own, awake over standby, enlarged: does each read?"""
    m = metrics(w)
    cols = [rgb("TUBE_ROSE"), rgb("TUBE_TURQUOISE")]
    pad = m["pad"] // 2
    cw, ch = max(m["adv"].values()) + 2 * pad, m["h"] + 2 * pad
    sheet = Image.new("RGB", (10 * cw, 2 * ch), (0, 0, 0))
    for k, c in enumerate("0123456789"):
        x = k * cw + (cw - m["adv"][c]) // 2
        for row, kinds in enumerate((("glow", "core"), ("thin",))):
            y = row * ch + pad
            for kind in kinds:
                p = m["pad"] if kind == "glow" else m["core_pad"]
                for light in (er.UL, er.LR):
                    colour = {"glow": cols[light], "core": core(cols[light]), "thin": standby(cols[light])}[kind]
                    cell = Image.new("RGB", sheet.size, colour)
                    mask = Image.new("L", sheet.size, 0)
                    mask.paste(digit_mask(c, light, w, kind), (x - p, y - p))
                    sheet.paste(cell, (0, 0), mask)
    sheet.resize((sheet.width * scale, sheet.height * scale), Image.LANCZOS).save(path)


def options(argv):
    st = dict(DEFAULTS)
    st["from"] = "09:26"
    for a in argv:
        k, v = a.split("=", 1)
        st[k] = int(v) if isinstance(DEFAULTS.get(k), int) else (v.upper() if k in ("hours", "minutes", "detail", "date") else v)
    for k in ("hours", "minutes", "detail"):
        assert st[k] in TUBES, f"{st[k]} is not a tube"
    return st


def whole_set():
    OUT.mkdir(exist_ok=True)
    # each size, awake and in standby
    for w in WIDTHS:
        st = dict(DEFAULTS, w=w)
        a, s = face(st), face(dict(st, standby=1))
        watch(a).save(OUT / f"edge-{w}.png")
        watch(s).save(OUT / f"edge-{w}-standby.png")
        worst = max(lit_share(face(dict(st, standby=1, time=t))) for t in ("00:00", "08:08", "20:08", "23:59", "10:37"))
        print(f"{w}: standby {lit_share(s):.1%} lit at 10:37, {worst:.1%} at the worst of five times")
    watch(face(dict(DEFAULTS, w=390, plain=1))).save(OUT / "edge-390-plain.png")   # as the Forerunner 165 draws it
    pair = [tile(DEFAULTS, "Edge  ·  awake"), tile(dict(DEFAULTS, standby=1), "standby")]
    grid(pair, 2, OUT / "edge.png")
    digits_sheet(OUT / "digits.png")
    # a spread of times: the widest and the narrowest pairs, 12-hour single hours
    times = ["10:37", "00:00", "11:11", "20:08", "23:59", "9:41", "1:11", "12:34", "17:46", "4:05", "08:52", "21:30"]
    grid([tile(dict(DEFAULTS, time=t), t, 300) for t in times], 4, OUT / "times.png")
    grid([tile(dict(DEFAULTS, time=t, standby=1), t + " standby", 300) for t in times], 4, OUT / "times-standby.png")
    # every look: the seven sets and the four others, awake and standby
    looks = [dict(DEFAULTS, look="daily", day=d) for d in range(len(NEON_SETS))] + [dict(DEFAULTS, look=k) for k in LOOKS]
    tiles = []
    for st in looks:
        tiles.append(tile(st, title(st), 300))
        tiles.append(tile(dict(st, standby=1), title(st) + " standby", 300))
    grid(tiles, 6, OUT / "looks.png")
    grid([tile(dict(st, title=1), title(st), 300) for st in looks + [dict(DEFAULTS)]], 6, OUT / "titles.png")
    # all sixteen tubes, as the hours' and the minutes' (the next on the chart), awake and standby
    names = list(TUBES)
    tiles = []
    for i, n in enumerate(names):
        st = dict(DEFAULTS, hours=n, minutes=names[(i + 5) % len(names)], detail=names[(i + 10) % len(names)])
        tiles.append(tile(st, f"{n} / {st['minutes']} / {st['detail']}", 300))
        tiles.append(tile(dict(st, standby=1), "standby", 300))
    grid(tiles, 8, OUT / "tubes.png")
    write_strikes(OUT)


if __name__ == "__main__":
    if len(sys.argv) > 1:
        st = options(sys.argv[2:])
        if st["strike"] >= 0:
            old = tuple(st["from"].split(":")) + (st["date"],)
            img = strike_frame(st, old, tuple(st["time"].split(":")) + (st["date"],), st["strike"], bool(st["turn"]))
        else:
            img = face(st)
        watch(img).save(sys.argv[1])
        print(f"{lit_share(img):.1%} lit")
    else:
        whole_set()
