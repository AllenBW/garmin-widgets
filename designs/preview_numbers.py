#!/usr/bin/env python3
"""What the previews of the faces made of numbers share (preview_blocks.py,
preview_wall.py): the families' colours per look (Lib.Numbers), sample
readings, and rows of numbers sized to reach the bezel, drawn four times
over size and scaled down. Widths come from zeros by advance, as on the
watch. Needs Pillow; run the scripts with a venv's python -I.
"""
import math
import os
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

FONTS = Path.home() / "Library/Application Support/Garmin/ConnectIQ/Fonts"
SS = 4
W = int(os.environ.get("FACE_W", 454))
S = W * SS
BB, BM, RB, RR = "Bionic_Bold.ttf", "Bionic_Medium.ttf", "RobotoCondensed-Bold.ttf", "RobotoCondensed-Regular.ttf"
DEG = 0.30      # the width a degree sign adds, per digit height

LOOKS = {
    "yours": dict(data=0xF2ECE2, sun=0xFFB020, wx=0x4DB2FF, body=0xFF5C9E, s=.86, t=.70),
    "orange": dict(data=0xFFFFFF, sun=0xFF6A13, wx=0xFFD21A, body=0xFF3D6E, s=1, t=1, big=True),
    "blue": dict(data=0xFFFFFF, sun=0x2EA8FF, wx=0x2EF0E0, body=0xB48CFF, s=1, t=1, big=True),
    "green": dict(data=0xFFFFFF, sun=0x5CFF2E, wx=0xD4FF1A, body=0x2EF0B0, s=1, t=1, big=True),
    "low": dict(data=0xF0D2A8, sun=0xFF9A3C, wx=0xD9C08F, body=0xE8785A, s=.85, t=.70),
    "gold": dict(data=0xE6CFA0, sun=0xFFB020, wx=0x2EE6B0, body=0xFF5A36, s=.86, t=.70),
    "ember": dict(data=0xE6CFA0, sun=0xFF5A36, wx=0xE8D44A, body=0xFF5C9E, s=.86, t=.70),
    "orchard": dict(data=0xF2ECE2, sun=0x8CE03C, wx=0x2EE6B0, body=0xE8D44A, s=.86, t=.70),
    "dusk": dict(data=0xF8D2D8, sun=0xA77BFF, wx=0x38A8FF, body=0xFF5C9E, s=.86, t=.70),
}
SAMPLES = {
    "day": dict(time="14:38", hh="14", mm="38", sun="19:22", count="4:44", temp="46°", hr="72", hi="52", lo="38",
                date="10/31", bat="82", steps="6214", alt="1240", wind="12"),
    "night": dict(time="21:05", hh="21", mm="05", sun="07:12", count="10:07", temp="28°", hr="58", hi="41", lo="24",
                  date="10/31", bat="47", steps="11382", alt="1240", wind="6"),
    "widest": dict(time="11:11", hh="11", mm="11", sun="17:01", count="11:11", temp="-12°", hr="148", hi="-4", lo="-19",
                   date="11/11", bat="100", steps="21114", alt="11240", wind="31"),
}
_fonts = {}


def font(name, px):
    px = max(4, int(px))
    if (name, px) not in _fonts:
        _fonts[(name, px)] = ImageFont.truetype(str(FONTS / name), px)
    return _fonts[(name, px)]


def rgb(c, a=1.0):
    return tuple(int(((c >> s) & 255) * a) for s in (16, 8, 0))


def metrics(text, name):
    """(advance width, em) per unit of digit height"""
    f = font(name, 1000)
    deg = text.endswith("°")
    t = text[:-1] if deg else text
    x0, _, x1, _ = f.getbbox(t)
    _, dy0, _, dy1 = f.getbbox("0")
    return (x1 - x0) / (dy1 - dy0) + (DEG if deg else 0), 1000 / (dy1 - dy0)


def template(t):
    return "".join("0" if ch.isdigit() else ch for ch in t)


def chord(y, margin):
    d = abs(y - 0.5)
    return 0.0 if d >= 0.5 - margin else 2 * math.sqrt((0.5 - margin) ** 2 - d ** 2)


def span(y, margin):
    c = chord(y, margin)
    return 0.5 - c / 2, 0.5 + c / 2


def it(s, f, c, a=1.0):
    return dict(t=s, f=f, c=c, a=a)


def row_width(items, h, gap):
    return sum(metrics(template(i["t"]), i["f"])[0] * h for i in items) + gap * (len(items) - 1)


def solve(items, avail, gap):
    lo, hi = 0.005, 0.8
    for _ in range(40):
        h = (lo + hi) / 2
        if row_width(items, h, gap) <= avail(h):
            lo = h
        else:
            hi = h
    return lo


class Canvas:
    def __init__(self):
        self.im = Image.new("RGB", (S, S), (0, 0, 0))
        self.mask_all = Image.new("L", (S, S), 0)

    def text(self, t, name, h, x, y, color, a=1.0, mode="fill", align="l", width=None):
        """the digits h tall (fraction of W), top at y, advance box from x"""
        hpx = h * S
        _, em = metrics("0", name)
        f = font(name, hpx * em)
        deg = t.endswith("°")
        t = t[:-1] if deg else t
        if deg and width is not None:
            width -= DEG * h
        bx0, _, bx1, _ = f.getbbox(t)
        _, dy0, _, _ = f.getbbox("0")
        ox = x * S - bx0
        if align == "r" and width is not None:
            ox = (x + width) * S - bx1
        if align == "c" and width is not None:
            ox = (x + width / 2) * S - (bx0 + bx1) / 2
        oy = y * S - dy0
        m = Image.new("L", (S, S), 0)
        dm = ImageDraw.Draw(m)
        dm.text((ox, oy), t, font=f, fill=255)
        if deg:  # a small ring, top aligned with the digits
            cx = ox + bx1 + (DEG * 0.62) * hpx
            r = 0.115 * hpx
            w = max(2, 0.052 * hpx)
            dm.ellipse((cx - r, y * S, cx + r, y * S + 2 * r), outline=255, width=int(w))
        if mode == "line":
            m = ImageChops.subtract(m.filter(ImageFilter.MaxFilter((2 * SS - 1) | 1)), m)
        self.im.paste(Image.new("RGB", (S, S), rgb(color, a)), (0, 0), m)
        self.mask_all = ImageChops.lighter(self.mask_all, m)

    def done(self):
        out = self.im.resize((W, W), Image.LANCZOS)
        c = Image.new("L", (W * 4, W * 4), 0)
        ImageDraw.Draw(c).ellipse((0, 0, W * 4 - 1, W * 4 - 1), fill=255)
        c = c.resize((W, W), Image.LANCZOS)
        black = Image.new("RGB", (W, W), (0, 0, 0))
        black.paste(out, (0, 0), c)
        hist = black.convert("L").histogram()
        return black, sum(hist[13:]) / (math.pi * (W / 2) ** 2)


def place(cv, items, h, x0, x1, y, mode):
    tot = row_width(items, h, 0)
    slack = max(0, (x1 - x0) - tot)
    g = slack / (len(items) - 1) if len(items) > 1 else 0
    x = x0
    for n, i in enumerate(items):
        w = metrics(template(i["t"]), i["f"])[0] * h
        al = "c" if len(items) == 1 else "l" if n == 0 else "r" if n == len(items) - 1 else "c"
        cv.text(i["t"], i["f"], h, x, y, i["c"], i.get("a", 1.0), mode=mode, align=al, width=w)
        x += w + g


def stack(cv, rows, y, sign, M, G, RG, mode):
    for r in rows:
        b = y + sign * G
        hh = solve(r, lambda q, b=b: chord(b + sign * q, M), RG)
        if hh < 0.012:
            break
        tp = b - hh if sign < 0 else b
        a, c = span(b + sign * hh, M)
        place(cv, r, hh, a, c, tp, mode)
        y = b + sign * hh
    return y


def family(lk):
    return lk["data"], lk["sun"], lk["wx"], lk["body"], lk["s"], lk["t"]


def args(argv):
    """out.png [day|night|widest] [standby] [look=yours]"""
    sample, standby, look = "day", False, "yours"
    for a in argv[2:]:
        if a in SAMPLES:
            sample = a
        elif a == "standby":
            standby = True
        elif a.startswith("look="):
            look = a[5:]
    return argv[1], SAMPLES[sample], LOOKS[look], standby
