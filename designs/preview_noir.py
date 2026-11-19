#!/usr/bin/env python3
"""Preview of the Noir face (design #59): an analog dial in neon. The hands
are loops of tube, the twelve a pair of strokes, the quarters one each,
the date bent from thin tube where the hands leave room.

It composes the very layers the watch draws (designs/gen_noir.py bakes
them: glow, haze, core, thin), the way the watch does: each tinted with
its tube's colour, turned about the centre with a bilinear filter, laid
over what is there. So what this shows is what `drawBitmap2` gives.

    uv run -q --with pillow --with numpy python -I designs/preview_noir.py [sheet ...] [switches]

Sheets (written to designs/noir/): pair (awake and standby, the default),
times (twelve times), looks (the seven sets and the four other looks),
tubes (all sixteen tubes), sizes (the five screen widths), letters (the
lettering and every look's name), cross (the minute hand lying over the hour hand, enlarged),
motion (the transition: a GIF of each scene at the face's frame rate and a
sheet of frames), frame (one frame: scene=wake-hours t=300 to=FILE).

Switches: time=10:37 date=15 w=454 look=yours|red|blue|green|low|daily
day=0..6 hours=ROSE minutes=TURQUOISE detail=AMBER title=1 standby=1
out=FILE (one face to FILE). --check prints the standby's lit share at
every width, the worst of the twelve times, and exits 1 at 8 % or more.
"""
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))                                   # run with -I
import gen_noir as g  # noqa: E402
from colors import NEON_LOOKS, NEON_SETS, TUBES, core, rgb, standby  # noqa: E402
from preview_sign import DEATH, LONGEST, strike_dying, strike_lit  # noqa: E402  (Lib.Strike's tables)

OUT = HERE / "noir"
FONTS = Path.home() / "Library/Application Support/Garmin/ConnectIQ/Fonts"
TIMES = [(10, 37), (12, 0), (1, 5), (2, 50), (3, 15), (4, 22), (6, 0), (6, 30), (7, 37), (9, 15), (9, 47), (11, 58)]
LOOKS = {"red": "BRIGHT", "blue": "BRIGHT_BLUE", "green": "BRIGHT_GREEN", "low": "LOW"}
TITLES = {"yours": "YOUR LOOK", "red": "HI-VIS RED", "blue": "HI-VIS BLUE", "green": "HI-VIS GREEN", "low": "LOW LIGHT"}
DEPTH16 = True             # show the watch's 16 bits a pixel (depth=24 for the light as baked)
LEVELS = np.array([31, 63, 31], dtype=np.float32)
_parts = {}


def parts(w):
    if w not in _parts:
        _parts[w] = g.parts(w)
    return _parts[w]


def tubes(look="yours", day=0, yours=("ROSE", "TURQUOISE", "AMBER")):
    """The look's three tubes, as Lib.Neon.tubes: hours, minutes, details."""
    if look == "daily":
        return list(NEON_SETS.values())[day % len(NEON_SETS)]
    return NEON_LOOKS[LOOKS[look]] if look in LOOKS else tuple(yours)


def title(look="yours", day=0):
    return list(NEON_SETS)[day % len(NEON_SETS)] if look == "daily" else TITLES[look]


def angles(hour, minute):
    """The hands' angles, degrees clockwise from twelve: hour, minute."""
    return (hour % 12 + minute / 60.0) * 30.0, minute * 6.0


def apart(a, b):
    d = abs(a - b) % 360.0
    return 360.0 - d if d > 180.0 else d


def date_place(hour_deg, minute_deg):
    """Where the date goes: 0 at three o'clock, 1 at nine, 2 at six: the
    first that neither hand is near. Two hands can't take all three."""
    for place, at in enumerate((90.0, 270.0, 180.0)):
        if apart(hour_deg, at) > g.BLOCK and apart(minute_deg, at) > g.BLOCK:
            return place
    return 2


def title_below(minute_deg):
    """The look's name sits below the centre unless the minute hand does."""
    return apart(minute_deg, 180.0) > 90.0


class Face:
    """One screen, w wide, drawn as NoirView draws it."""

    def __init__(self, w):
        self.w = w
        self.c = w / 2.0
        self.images, self.layout = parts(w)
        self.a = np.zeros((w, w, 3), dtype=np.float32)

    def over(self, alpha, colour):
        """Lay a tinted layer over what is there, into 16 bits a pixel as
        the watch's bitmap has (5 of red, 6 of green, 5 of blue)."""
        self.a = self.a * (1 - alpha[..., None]) + alpha[..., None] * np.array(colour, dtype=np.float32)
        if DEPTH16:
            self.a = np.rint(self.a * LEVELS / 255) * 255 / LEVELS

    def turn(self, name, deg, colour, scale=1.0, shift=(0, 0)):
        """A layer turned about the centre: drawBitmap2 with a transform."""
        img = self.images[name]
        px, py = self.layout[name]
        t = math.radians(deg)
        cos, sin = math.cos(t), math.sin(t)
        cx, cy = self.c + shift[0], self.c + shift[1]
        data = (cos / scale, sin / scale, px - (cos * cx + sin * cy) / scale,
                -sin / scale, cos / scale, py - (-sin * cx + cos * cy) / scale)
        full = img.transform((self.w, self.w), Image.AFFINE, data, resample=Image.BILINEAR)
        self.over(np.asarray(full, dtype=np.float32) / 255, colour)

    def text(self, s, x, y, colour, kind):
        """A line of lettering centred on (x, y), fractions of the width:
        each letter's cell from its sheet, at whole pixels."""
        cw, ch, m = self.layout["haloCell" if kind == "Halo" else "coreCell"]
        h = g.TEXT_H * self.w
        left = x * self.w - g.text_width(s) * h / 2
        top = int(math.floor(y * self.w - h / 2 + 0.5))
        for ch_ in s:
            if ch_ == " ":
                left += (g.SPACE + g.TEXT_GAP) * h
                continue
            name, chars, cols = ("Digits", g.DIGITS, len(g.DIGITS)) if ch_ in g.DIGITS else ("Letters", g.ALPHA, g.COLS)
            i = chars.index(ch_)
            cellimg = self.images[name + kind].crop(((i % cols) * cw, (i // cols) * ch, (i % cols + 1) * cw, (i // cols + 1) * ch))
            full = Image.new("L", (self.w, self.w), 0)
            full.paste(cellimg, (int(math.floor(left + 0.5)) - m, top - m))
            self.over(np.asarray(full, dtype=np.float32) / 255, colour)
            left += (g.LETTERS[ch_][0] + g.TEXT_GAP) * h

    def image(self):
        return Image.fromarray(np.clip(np.rint(self.a), 0, 255).astype(np.uint8))


def render(w=454, hour=10, minute=37, date="15", colours=("ROSE", "TURQUOISE", "AMBER"), name=None, asleep=False, shift=None,
           hands=None, dates=None):
    """The face. `name` is the look's name, standing in for the date. In a
    transition `hands` are the hands' angles of the moment and `dates` the
    dates lit: (text, place, core percent, halo percent) each."""
    f = Face(w)
    hc, mc, dc = (rgb("TUBE_" + t) for t in colours)
    hd, md = hands if hands else angles(hour, minute)
    if asleep:
        if shift is None:
            shift = aod_offset(minute, max(1, int(w * 0.005 + 0.5)))
        f.turn("TwelveThin", 0, standby(dc), shift=shift)
        f.turn("HourThin", hd, standby(hc), shift=shift)
        f.turn("MinuteThin", md, standby(mc), shift=shift)
        return f.image()
    if name:
        lines = [(name, 0.5, 0.5 + (g.TITLE_Y if title_below(md) else -g.TITLE_Y), 100, 100)]
    else:
        if dates is None:
            dates = [(date, date_place(hd, md), 100, 100)]
        lines = [(text, 0.5 + (g.DATE_R, -g.DATE_R, 0.0)[place], 0.5 + (0.0, 0.0, g.DATE_R)[place], c, h)
                 for text, place, c, h in dates]
    for deg in (90, 180, 270):
        f.turn("QuarterHalo", deg, dc)
    f.turn("TwelveHalo", 0, dc)
    for text, x, y, _, h in lines:
        if h > 0:
            f.text(text, x, y, dimmed(dc, h), "Halo")
    f.turn("HourHalo", hd, hc)
    f.turn("MinuteHalo", md, mc)
    for deg in (90, 180, 270):
        f.turn("QuarterCore", deg, core(dc))
    f.turn("TwelveCore", 0, core(dc))
    for text, x, y, c, _ in lines:
        if c > 0:
            f.text(text, x, y, dimmed(core(dc), c), "Core")
    f.turn("HourCore", hd, core(hc))
    f.turn("MinuteCore", md, core(mc))
    return f.image()


def aod_offset(minute, step):
    """Lib.Aod.offset."""
    return ((minute % 5) - 2) * step, (((2 * minute + minute // 5 + 1) % 5) - 2) * step


# ---------------------------------------------------------------- the transition
# The hands sweep and the date is struck: the same sums as Dial.mc, NoirView
# and Lib.Motion.ease, with Lib.Strike's tables from the Sign preview.

PUSH, BACK = 70, 0.025     # Lib.Motion: the push off the stop, and how far back it goes
FRAME = 50                 # ms between the face's frames
DATE_SEED = 2
SCENES = (
    # name, last seen (hour, minute, day), now, a wake or the minute turning while awake
    ("wake-8-minutes", (10, 29, 15), (10, 37, 15), True),
    ("wake-hours", (6, 15, 14), (10, 37, 15), True),
    ("minute", (10, 36, 15), (10, 37, 15), False),
    ("date-moves", (4, 10, 15), (4, 11, 15), False),
)


def dimmed(colour, percent):
    """Lib.Neon.wash(colour, 0, percent)."""
    return tuple(v * percent // 100 for v in colour)


def ease(t, dur):
    """Lib.Motion.ease with no bounce: a little back, then slow out, slow in."""
    if t <= 0:
        return 0.0
    if t < PUSH:
        return -BACK * math.sin(math.pi * t / PUSH)
    x = (t - PUSH) / dur
    if x >= 1.0:
        return 1.0
    return 4 * x * x * x if x < 0.5 else 1 - (2 - 2 * x) ** 3 / 2


def turn(a, b):
    """The shorter way round from a to b: -180 to 180, clockwise positive."""
    d = b - a
    while d > 180.0:
        d -= 360.0
    while d <= -180.0:
        d += 360.0
    return d


def sweep_ms(d):
    return g.SWEEP + int(g.SWEEP_FAR * abs(d) / 180.0)


def swept(a, b, t, dur):
    d = turn(a, b)
    if d == 0.0 or t >= PUSH + dur:
        return b
    return a + d * ease(t, dur)


def transition(seen, now, wake):
    """What a change sets moving: the hands' sweeps (from, to, ms) and the
    date's lives (text, place, dying or struck, from when), and its length."""
    a0, a1 = angles(seen[0], seen[1]), angles(now[0], now[1])
    hands = [(a0[i], a1[i], sweep_ms(turn(a0[i], a1[i])) if wake else g.TICK) for i in (0, 1)]
    old = (str(seen[2]), date_place(*a0))
    new = (str(now[2]), date_place(*a1))
    length = max((PUSH + dur for a, b, dur in hands if turn(a, b) != 0.0), default=0)
    if new[1] != old[1] or (not wake and new[0] != old[0]):
        dates = [(old[0], old[1], True, 0), (new[0], new[1], False, DEATH)]
        length = max(length, DEATH + LONGEST)
    elif new[0] != old[0]:
        dates = [(new[0], new[1], False, 0)]
        length = max(length, LONGEST)
    else:
        dates = [(new[0], new[1], None, 0)]
    return hands, dates, length


def moment(w, seen, now, wake, t, colours=("ROSE", "TURQUOISE", "AMBER")):
    """The face t ms into a transition, as NoirView draws the frame."""
    hands, dates, _ = transition(seen, now, wake)
    lit = []
    for text, place, dying, at in dates:
        if dying is None:
            lit.append((text, place, 100, 100))
        elif dying:
            c, h = strike_dying(t - at)
            lit.append((text, place, c, h))
        else:
            c, h = strike_lit(t - at, DATE_SEED) if t >= at else (0, 0)
            lit.append((text, place, c, h))
    return render(w=w, colours=colours, hands=[swept(a, b, t, dur) for a, b, dur in hands], dates=lit)


def write_motion(w=454):
    """A GIF of each scene at the face's frame rate, and a sheet of frames."""
    rows = []
    for name, seen, now, wake in SCENES:
        _, _, length = transition(seen, now, wake)
        before = moment(w, seen, seen, wake, 0)
        frames = [(before, 900)] + [(moment(w, seen, now, wake, t), FRAME) for t in range(0, length + FRAME, FRAME)]
        frames[-1] = (frames[-1][0], 1600)
        gif = [watch(f).resize((w * 3 // 4, w * 3 // 4), Image.LANCZOS).quantize(255, dither=Image.Dither.FLOYDSTEINBERG) for f, _ in frames]
        gif[0].save(OUT / ("motion-%s.gif" % name), save_all=True, append_images=gif[1:], duration=[d for _, d in frames], loop=0)
        picks = [0, 100, 150, 200, 250, 300, 350, 420, 500, 560, 650, 800, 1000, length]
        rows += [("%s  %d ms" % (name, t), watch(moment(w, seen, now, wake, min(t, length))).resize((w // 2, w // 2), Image.LANCZOS)) for t in picks]
        print("%s: %d ms, %d frames, %s" % (name, length, len(frames), OUT / ("motion-%s.gif" % name)))
    out = grid(rows, 14, 6)
    out.save(OUT / "motion.png")
    print(OUT / "motion.png")


# ---------------------------------------------------------------- sheets

def disc(n):
    m = Image.new("L", (n, n), 0)
    ImageDraw.Draw(m).ellipse((0, 0, n - 1, n - 1), fill=255)
    return m


def watch(img):
    n = img.size[0]
    out = Image.new("RGB", (n, n), (26, 26, 28))
    out.paste(img, (0, 0), disc(n))
    return out


def lit_share(img):
    n = img.size[0]
    on = np.asarray(img.convert("L")) > 8
    m = np.asarray(disc(n)) > 0
    return (on & m).sum() / m.sum()


def label(text, w, h=30, size=18):
    im = Image.new("RGB", (w, h), (12, 12, 12))
    try:
        font = ImageFont.truetype(str(FONTS / "RobotoCondensed-Regular.ttf"), size)
    except OSError:
        font = ImageFont.load_default()
    ImageDraw.Draw(im).text((8, h // 2), text, font=font, fill=(200, 200, 196), anchor="lm")
    return im


def grid(tiles, cols, gap=10):
    """Tiles of (label, image) in rows."""
    tw = max(t[1].size[0] for t in tiles)
    th = max(t[1].size[1] for t in tiles) + 30
    rows = (len(tiles) + cols - 1) // cols
    out = Image.new("RGB", (cols * (tw + gap) - gap, rows * (th + gap) - gap), (12, 12, 12))
    for i, (text, img) in enumerate(tiles):
        x, y = (i % cols) * (tw + gap), (i // cols) * (th + gap)
        out.paste(label(text, tw), (x, y))
        out.paste(img, (x, y + 30))
    return out


def pair(**kw):
    a, s = render(**kw), render(asleep=True, **kw)
    out = Image.new("RGB", (2 * a.size[0] + 12, a.size[1]), (12, 12, 12))
    out.paste(watch(a), (0, 0))
    out.paste(watch(s), (a.size[0] + 12, 0))
    return out, lit_share(s)


def main():
    args = [a for a in sys.argv[1:] if "=" not in a and not a.startswith("--")]
    opt = dict(a.split("=", 1) for a in sys.argv[1:] if "=" in a)
    w = int(opt.get("w", 454))
    global DEPTH16
    DEPTH16 = opt.get("depth", "16") == "16"
    hour, minute = (int(v) for v in opt.get("time", "10:37").split(":"))
    look, day = opt.get("look", "yours"), int(opt.get("day", 0))
    yours = (opt.get("hours", "ROSE"), opt.get("minutes", "TURQUOISE"), opt.get("detail", "AMBER"))
    colours = tubes(look, day, yours)
    base = dict(w=w, hour=hour, minute=minute, date=opt.get("date", "15"), colours=colours,
                name=title(look, day) if opt.get("title") else None)
    OUT.mkdir(exist_ok=True)

    if "--check" in sys.argv:
        worst_all = 0.0
        for width in g.WIDTHS:
            worst = max(lit_share(render(w=width, hour=h, minute=m, asleep=True, colours=("SNOW", "SNOW", "SNOW"))) for h, m in TIMES)
            worst_all = max(worst_all, worst)
            print("%d px: standby %.2f %% lit at worst" % (width, worst * 100))
        sys.exit(1 if worst_all >= 0.08 else 0)
    if "out" in opt:
        watch(render(asleep=bool(opt.get("standby")), **base)).save(opt["out"])
        return
    for sheet in args or ["pair"]:
        if sheet == "pair":
            img, share = pair(**base)
            out = Image.new("RGB", (img.size[0], img.size[1] + 30), (12, 12, 12))
            out.paste(label("Noir  ·  awake  |  standby, %.1f %% lit" % (share * 100), img.size[0]), (0, 0))
            out.paste(img, (0, 30))
        elif sheet == "times":
            out = grid([("%d:%02d" % (h, m), watch(render(**{**base, "hour": h, "minute": m}))) for h, m in TIMES], 4)
        elif sheet == "looks":
            tiles = []
            for i, name in enumerate(NEON_SETS):
                img, share = pair(**{**base, "colours": tubes("daily", i), "w": 360})
                tiles.append(("%s: %s  ·  standby %.1f %%" % (name, ", ".join(TUBES[t][3] for t in tubes("daily", i)), share * 100), img))
            for key in LOOKS:
                img, share = pair(**{**base, "colours": tubes(key), "w": 360})
                tiles.append(("%s: %s  ·  standby %.1f %%" % (TITLES[key], ", ".join(TUBES[t][3] for t in tubes(key)), share * 100), img))
            out = grid(tiles, 2)
        elif sheet == "tubes":
            tiles = []
            for t in TUBES:
                img, _ = pair(**{**base, "colours": (t, t, t), "w": 360})
                tiles.append((TUBES[t][3], img))
            out = grid(tiles, 2)
        elif sheet == "sizes":
            out = grid([("%d px" % width, watch(render(**{**base, "w": width}))) for width in g.WIDTHS], 5)
        elif sheet == "letters":
            tiles = []
            for i, s in enumerate(["0123456789", "ABCDEFGHI", "JKLMNOPQR", "STUVWXYZ-"] + list(TITLES.values()) + list(NEON_SETS)):
                f = Face(w)
                f.text(s, 0.5, 0.5, rgb("TUBE_AMBER"), "Halo")
                f.text(s, 0.5, 0.5, core(rgb("TUBE_AMBER")), "Core")
                band = f.image().crop((0, w // 2 - int(0.11 * w), w, w // 2 + int(0.11 * w)))
                tiles.append((s, band.resize((band.size[0] * 2, band.size[1] * 2), Image.LANCZOS)))
            out = grid(tiles, 2)
        elif sheet == "cross":
            tiles = []
            for h, m in ((12, 0), (1, 5), (2, 9), (3, 22), (6, 30), (9, 45), (10, 58), (4, 17)):
                for asleep in (False, True):
                    img = render(**{**base, "hour": h, "minute": m, "asleep": asleep, "shift": (0, 0)})
                    q = w // 4
                    tiles.append(("%d:%02d%s" % (h, m, " standby" if asleep else ""), img.crop((q, q, w - q, w - q)).resize((w, w), Image.LANCZOS)))
            out = grid(tiles, 4)
        elif sheet == "motion":
            write_motion(w)
            continue
        elif sheet == "frame":
            scene = next(sc for sc in SCENES if sc[0] == opt.get("scene", "wake-hours"))
            out = watch(moment(w, scene[1], scene[2], scene[3], int(opt.get("t", 0)), colours))
            out.save(opt.get("to", str(OUT / "frame.png")))
            continue
        elif sheet == "titles":
            tiles = []
            for (h, m), key in zip(((10, 37), (6, 30), (3, 15), (12, 0), (9, 47), (4, 22)), ("yours", "red", "blue", "green", "low", "daily")):
                tiles.append(("%d:%02d" % (h, m), watch(render(**{**base, "hour": h, "minute": m, "colours": tubes(key, 6), "name": title(key, 6)}))))
            out = grid(tiles, 3)
        else:
            raise SystemExit("no sheet named %s" % sheet)
        out.save(OUT / ("%s.png" % sheet))
        print(OUT / ("%s.png" % sheet))


if __name__ == "__main__":
    main()
