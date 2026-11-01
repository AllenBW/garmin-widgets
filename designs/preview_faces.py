#!/usr/bin/env python3
"""What the faces' preview scripts share (preview_vessel.py,
preview_inscription.py, preview_overlap.py): the watch's fonts, a face
drawn four times over size and scaled down (close to the watch's
anti-aliasing) that reports the share of the round screen lit, the
readings' icons (the same shapes as Lib.Icons), sample readings for each
kind (Lib.Slots), and the drawing moves the faces are made of: ink-true
digit placement, glyph masks, outlines, spaced capitals and text on a
circle. Needs Pillow; run the scripts with a venv's python -I.
"""
import math
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

FONTS = Path.home() / "Library/Application Support/Garmin/ConnectIQ/Fonts"
SS = 4

# Lib.Config's colours
ACCENTS = [("Amber", 0xFFB020), ("Lime", 0x8CE03C), ("Sky", 0x38A8FF), ("Flame", 0xFF5A36),
           ("Mint", 0x2EE6B0), ("Violet", 0xA77BFF), ("Rose", 0xFF5C9E), ("Gold", 0xE8D44A)]
# The sign behind the time for each accent: the same hue, dark, with more
# colour than the accent scaled down would have
DATA = [("Bone", 0xF2ECE2), ("Silver", 0xB4BAC2), ("Sand", 0xE6CFA0), ("Ice", 0xCFE6FF), ("Blush", 0xF8D2D8)]
GREY = 0x8A8A8A
BEDSIDE = 0x8C2A1C               # a dim ember red that keeps night vision

# Each kind: (value, unit) by day and by night, and the bulbs lit (0..1) by
# day and night, None for a kind with no range (no bulbs)
KINDS = {
    "heart":    ((("72", ""), ("58", "")), (0.32, 0.10)),
    "steps":    ((("8412", ""), ("9870", "")), (0.84, 0.99)),
    "battery":  ((("81", "%"), ("64", "%")), (0.81, 0.64)),
    "body":     ((("64", ""), ("23", "")), (0.64, 0.23)),
    "stress":   ((("28", ""), ("12", "")), (0.28, 0.12)),
    "temp":     ((("46°", ""), ("28°", "")), (0.55, 0.30)),
    "calories": ((("1840", ""), ("2310", "")), (None, None)),
    "floors":   ((("12", ""), ("3", "")), (1.0, 0.3)),
    "intensity": ((("95", ""), ("140", "")), (0.63, 0.93)),
    "altitude": ((("5280", "FT"), ("5310", "FT")), (None, None)),
    "pulseox":  ((("96", "%"), ("94", "%")), (0.96, 0.94)),
    "breath":   ((("14", ""), ("12", "")), (None, None)),
    "sun":      ((("19:22", ""), ("7:12", "")), (0.62, 0.35)),
    "notes":    ((("3", ""), ("0", "")), (None, None)),
    "recovery": ((("18", "H"), ("6", "H")), (None, None)),
    "vo2":      ((("52", ""), ("52", "")), (None, None)),
    "sleep":    ((("84", ""), ("84", "")), (0.84, 0.84)),
    "pressure": ((("1013", "HPA"), ("1009", "HPA")), (None, None)),
    "calendar": ((("15:00", ""), ("8:30", "")), (None, None)),
    "app":      ((("112", ""), ("98", "")), (0.45, 0.30)),      # a third-party complication, label "GLU"
}

SAMPLES = {
    "day": dict(hours="14", minutes="38", date="SAT 31", alarms=1, night=False),
    "night": dict(hours="21", minutes="05", date="SAT 31", alarms=0, night=True),
}


def rgb(c):
    return ((c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF)


def scale(c, f):
    r, g, b = rgb(c)
    return (min(255, int(r * f)) << 16) | (min(255, int(g * f)) << 8) | min(255, int(b * f))


def font(name, frac, size):
    """A watch font by its face name (Lib.Ink.NAMES and the rest), with its
    em `frac` of the screen width."""
    return ImageFont.truetype(str(FONTS / FILES[name]), int(size * frac * SS))


FILES = {"RobotoCondensedBold": "RobotoCondensed-Bold.ttf", "RobotoCondensedRegular": "RobotoCondensed-Regular.ttf",
         "RobotoRegular": "Roboto-Regular.ttf", "RobotoMedium": "Roboto-Medium.ttf",
         "BionicBold": "Bionic_Bold.ttf", "BionicMedium": "Bionic_Medium.ttf", "PridiRegular": "Pridi-Regular.ttf"}


class Face:
    def __init__(self, size):
        self.size = size
        self.img = Image.new("RGB", (size * SS, size * SS), (0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    def px(self, frac):
        return frac * self.size * SS

    def text(self, x, y, f, s, color, anchor="mm", **kw):
        self.d.text((x, y), s, font=f, fill=rgb(color), anchor=anchor, **kw)

    def width(self, f, s):
        return self.d.textlength(s, font=f)

    def done(self, path):
        """Save at 1x and 2x; returns the share of the round screen lit."""
        small = self.img.resize((self.size, self.size), Image.LANCZOS)
        mask = Image.new("L", (self.size, self.size), 0)
        ImageDraw.Draw(mask).ellipse((0, 0, self.size - 1, self.size - 1), fill=255)
        px, mk = small.get_flattened_data(), mask.get_flattened_data()
        lit = sum(1 for p, m in zip(px, mk) if m and max(p) > 0)
        disc = sum(1 for m in mk if m)
        out = Image.new("RGB", (self.size, self.size), (24, 24, 24))
        out.paste(small, (0, 0), mask)
        out.save(path)
        out.resize((self.size * 2, self.size * 2), Image.LANCZOS).save(str(path).replace(".png", "@2x.png"))
        return lit / disc


# ------------------------------------------------------------------ icons
# Each is `s` tall, centred on (cx, cy), in one colour; the same shapes as
# Lib.Icons'. Filled where they can be, 3 px lines where they can't, all
# about the same ink.

def lw(f, n=3.0):
    return max(SS, int(n * SS * f.size / 454 + 0.5))


def ell(f, x, y, rx, ry, c):
    f.d.ellipse((x - rx, y - ry, x + rx, y + ry), fill=rgb(c))


def heart(f, cx, cy, s, c):
    s *= 0.9
    r = s * 0.25
    top = cy - s * 0.2
    ell(f, cx - r, top, r, r, c)
    ell(f, cx + r, top, r, r, c)
    f.d.polygon([(cx - 2 * r + r * 0.06, top + r * 0.3), (cx + 2 * r - r * 0.06, top + r * 0.3), (cx, cy + s * 0.48)], fill=rgb(c))


def shoe(f, cx, cy, s, c):
    """A running shoe from the side, toe to the right (steps)."""
    pts = [(-0.50, 0.36), (-0.50, -0.14), (-0.42, -0.24), (-0.30, -0.26), (-0.24, -0.12), (-0.08, -0.22),
           (0.02, -0.36), (0.14, -0.32), (0.20, -0.10), (0.40, 0.00), (0.50, 0.16), (0.50, 0.36)]
    f.d.polygon([(cx + x * s, cy + y * s) for x, y in pts], fill=rgb(c))
    f.d.line([(cx - s * 0.5, cy + s * 0.22), (cx + s * 0.5, cy + s * 0.22)], fill=(0, 0, 0), width=lw(f, 1.5))


def steps(f, cx, cy, s, c):
    shoe(f, cx, cy, s, c)


def battery(f, cx, cy, s, c, level=0.81):
    """A shell, its black inside, then the charge, inset by whole pixels."""
    bw, bh = s * 1.0, s * 0.62
    left, top = cx - bw / 2 - s * 0.05, cy - bh / 2
    w = lw(f, 2)
    f.d.rounded_rectangle((left, top, left + bw, top + bh), radius=s * 0.12, fill=rgb(c))
    f.d.rectangle((left + bw, cy - bh * 0.22, left + bw + s * 0.11, cy + bh * 0.22), fill=rgb(c))
    f.d.rectangle((left + w, top + w, left + bw - w, top + bh - w), fill=(0, 0, 0))
    inset = 2 * w
    f.d.rectangle((left + inset, top + inset, left + inset + (bw - 2 * inset) * level, top + bh - inset), fill=rgb(c))


def bolt(f, cx, cy, s, c):
    pts = [(0.06, -0.5), (0.42, -0.5), (0.16, -0.08), (0.42, -0.08), (-0.20, 0.5), (-0.06, 0.08), (-0.40, 0.08)]
    f.d.polygon([(cx + x * s, cy + y * s) for x, y in pts], fill=rgb(c))


def stress(f, cx, cy, s, c):
    """A ring broken by a jagged line: tension."""
    r = s * 0.42
    f.d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=rgb(c), width=lw(f))
    pts = [(cx - r, cy), (cx - r * 0.45, cy), (cx - r * 0.2, cy - r * 0.55), (cx + r * 0.15, cy + r * 0.55),
           (cx + r * 0.4, cy), (cx + r, cy)]
    f.d.line(pts, fill=rgb(c), width=lw(f), joint="curve")


def thermometer(f, cx, cy, s, c):
    br = s * 0.22
    by = cy + s * 0.5 - br
    stem = s * 0.13
    f.d.rounded_rectangle((cx - stem, cy - s * 0.5, cx + stem, by), radius=stem, fill=rgb(c))
    ell(f, cx, by, br, br, c)


def cloud(f, cx, cy, s, col, grow=0.0):
    for x, y, r in ((-0.24, 0.16, 0.17), (-0.02, 0.06, 0.24), (0.22, 0.17, 0.16)):
        r = r * s + grow
        f.d.ellipse((cx + x * s - r, cy + y * s - r, cx + x * s + r, cy + y * s + r), fill=col)
    f.d.rounded_rectangle((cx - s * 0.42 - grow, cy + s * 0.14 - grow, cx + s * 0.38 + grow, cy + s * 0.33 + grow),
                          radius=s * 0.095 + grow, fill=col)


def weather(f, cx, cy, s, c, night=False):
    """A sun (a moon at night) half behind a cloud."""
    sx, sy, sr = cx + s * 0.16, cy - s * 0.18, s * 0.22
    if night:       # a crescent opening to the upper right, clear of the cloud
        mx, my, mr = cx + s * 0.12, cy - s * 0.16, s * 0.3
        ell(f, mx, my, mr, mr, c)
        f.d.ellipse((mx - mr + mr * 0.6, my - mr - mr * 0.45, mx + mr + mr * 0.6, my + mr - mr * 0.45), fill=(0, 0, 0))
    else:
        for i in range(8):
            a = math.pi * i / 4
            f.d.line([(sx + math.cos(a) * sr * 1.4, sy + math.sin(a) * sr * 1.4),
                      (sx + math.cos(a) * sr * 1.85, sy + math.sin(a) * sr * 1.85)], fill=rgb(c), width=lw(f, 2))
        ell(f, sx, sy, sr, sr, c)
    cloud(f, cx, cy, s, (0, 0, 0), s * 0.07)
    cloud(f, cx, cy, s, rgb(c))


def flame(f, cx, cy, s, c):
    """A flame with a tongue licking up its left side (calories)."""
    pts = [(0.02, -0.50), (0.22, -0.22), (0.34, 0.02), (0.36, 0.22), (0.26, 0.40), (0.0, 0.50), (-0.26, 0.40),
           (-0.36, 0.20), (-0.30, -0.04), (-0.18, -0.20), (-0.12, 0.0), (-0.04, -0.20)]
    f.d.polygon([(cx + x * s, cy + y * s) for x, y in pts], fill=rgb(c))


def stairs(f, cx, cy, s, c):
    s *= 0.9
    x0, y0 = cx - s * 0.48, cy + s * 0.46
    pts = [(x0, y0)]
    for k in range(3):
        pts += [(x0 + k * s * 0.32, y0 - (k + 1) * s * 0.3), (x0 + (k + 1) * s * 0.32, y0 - (k + 1) * s * 0.3)]
    pts += [(x0 + s * 0.96, y0)]
    f.d.polygon(pts, fill=rgb(c))


def chevrons(f, cx, cy, s, c):
    """Two up-chevrons, one over the other (intensity minutes)."""
    for dy in (-0.2, 0.2):
        y = cy + dy * s
        f.d.line([(cx - s * 0.42, y + s * 0.2), (cx, y - s * 0.2), (cx + s * 0.42, y + s * 0.2)], fill=rgb(c), width=lw(f, 3.5), joint="curve")


def bed(f, cx, cy, s, c):
    """A bed from the side, a pillow at the head (sleep score)."""
    f.d.rectangle((cx - s * 0.5, cy - s * 0.3, cx - s * 0.36, cy + s * 0.4), fill=rgb(c))       # the headboard
    f.d.rectangle((cx - s * 0.5, cy + s * 0.04, cx + s * 0.5, cy + s * 0.24), fill=rgb(c))      # the mattress
    f.d.rectangle((cx + s * 0.38, cy + s * 0.04, cx + s * 0.5, cy + s * 0.4), fill=rgb(c))      # the foot
    f.d.rounded_rectangle((cx - s * 0.3, cy - s * 0.14, cx - s * 0.02, cy + s * 0.02), radius=s * 0.06, fill=rgb(c))  # the pillow


def stopwatch(f, cx, cy, s, c):
    r = s * 0.38
    y = cy + s * 0.1
    f.d.ellipse((cx - r, y - r, cx + r, y + r), outline=rgb(c), width=lw(f))
    f.d.rectangle((cx - s * 0.11, cy - s * 0.5, cx + s * 0.11, cy - s * 0.38), fill=rgb(c))
    f.d.pieslice((cx - r * 0.62, y - r * 0.62, cx + r * 0.62, y + r * 0.62), 270, 30, fill=rgb(c))


def mountain(f, cx, cy, s, c):
    foot = cy + s * 0.4
    f.d.polygon([(cx - s * 0.1, cy - s * 0.45), (cx + s * 0.32, foot), (cx - s * 0.54, foot)], fill=rgb(c))
    f.d.polygon([(cx + s * 0.28, cy - s * 0.12), (cx + s * 0.54, foot), (cx, foot)], fill=rgb(c))


def drop(f, cx, cy, s, c, ring=True):
    r = s * 0.3
    by = cy + s * 0.5 - r
    pts = [(cx, cy - s * 0.5)] + [(cx + r * math.cos(math.pi * (-0.2 + 1.4 * i / 20)), by + r * math.sin(math.pi * (-0.2 + 1.4 * i / 20)))
                                  for i in range(21)]
    f.d.polygon(pts, fill=rgb(c))
    if ring:    # an O in the drop: oxygen, not water
        rr = r * 0.48
        f.d.ellipse((cx - rr, by - rr, cx + rr, by + rr), outline=(0, 0, 0), width=lw(f, 2))


def lungs(f, cx, cy, s, c):
    f.d.line([(cx, cy - s * 0.5), (cx, cy - s * 0.1)], fill=rgb(c), width=lw(f))
    for side in (-1, 1):
        x = cx + side * s * 0.25
        f.d.ellipse((x - s * 0.2, cy - s * 0.3, x + s * 0.2, cy + s * 0.48), fill=rgb(c))
    f.d.rectangle((cx - s * 0.04, cy - s * 0.3, cx + s * 0.04, cy + s * 0.48), fill=(0, 0, 0))


def sun(f, cx, cy, s, c, rise=False):
    hy = cy + s * 0.36
    r = s * 0.3
    f.d.pieslice((cx - r, hy - r, cx + r, hy + r), 180, 360, fill=rgb(c))
    f.d.line([(cx - s * 0.52, hy), (cx + s * 0.52, hy)], fill=rgb(c), width=lw(f, 2.5))
    k = s * 0.26
    near = hy - r - s * 0.12
    far = near - s * 0.3
    pts = [(cx - k, near), (cx, far), (cx + k, near)] if rise else [(cx - k, far), (cx, near), (cx + k, far)]
    f.d.line(pts, fill=rgb(c), width=lw(f), joint="curve")


def bubble(f, cx, cy, s, c):
    s *= 0.9
    f.d.rounded_rectangle((cx - s * 0.5, cy - s * 0.42, cx + s * 0.5, cy + s * 0.2), radius=s * 0.16, fill=rgb(c))
    f.d.polygon([(cx - s * 0.26, cy + s * 0.16), (cx - s * 0.02, cy + s * 0.16), (cx - s * 0.3, cy + s * 0.46)], fill=rgb(c))


def hourglass(f, cx, cy, s, c):
    a, b = s * 0.32, s * 0.46
    f.d.polygon([(cx - a, cy - b), (cx + a, cy - b), (cx + s * 0.05, cy), (cx + a, cy + b), (cx - a, cy + b), (cx - s * 0.05, cy)],
                fill=rgb(c))


def trend(f, cx, cy, s, c, way=1):
    """The barometer's arrow (Lib.Icons.trend): up and forward rising, down and forward falling."""
    k = 1.0 if way == 0 else 0.7071
    dx, dy = k, -way * 0.7071
    px_, py_ = -dy, dx
    tip, back, head, wide = s * 0.46, s * 0.46, s * 0.42, s * 0.30
    nx, ny = cx + dx * (tip - head), cy + dy * (tip - head)
    f.d.line([(cx - dx * back, cy - dy * back), (nx, ny)], fill=rgb(c), width=lw(f, 3.5))
    f.d.polygon([(cx + dx * tip, cy + dy * tip), (nx + px_ * wide, ny + py_ * wide), (nx - px_ * wide, ny - py_ * wide)],
                fill=rgb(c))


def crescent(f, cx, cy, s, c):
    r = s * 0.46
    ell(f, cx, cy, r, r, c)
    o = r * 0.55
    f.d.ellipse((cx - r + o, cy - r - o * 0.45, cx + r + o, cy + r - o * 0.45), fill=(0, 0, 0))


def calendar(f, cx, cy, s, c):
    f.d.rounded_rectangle((cx - s * 0.44, cy - s * 0.36, cx + s * 0.44, cy + s * 0.46), radius=s * 0.08, outline=rgb(c), width=lw(f, 2.5))
    f.d.rectangle((cx - s * 0.44, cy - s * 0.36, cx + s * 0.44, cy - s * 0.1), fill=rgb(c))
    for x in (-0.22, 0.22):
        f.d.line([(cx + x * s, cy - s * 0.5), (cx + x * s, cy - s * 0.28)], fill=rgb(c), width=lw(f, 2.5))


def bell(f, cx, cy, s, c):
    """A filled bell `s` tall."""
    f.d.chord((cx - s * 0.34, cy - s * 0.46, cx + s * 0.34, cy + s * 0.2), 180, 360, fill=rgb(c))
    f.d.polygon([(cx - s * 0.34, cy - s * 0.13), (cx + s * 0.34, cy - s * 0.13), (cx + s * 0.46, cy + s * 0.26),
                 (cx - s * 0.46, cy + s * 0.26)], fill=rgb(c))
    ell(f, cx, cy + s * 0.37, s * 0.1, s * 0.1, c)


def phone_off(f, cx, cy, s, c):
    """A phone with a slash: the phone isn't connected."""
    f.d.rounded_rectangle((cx - s * 0.24, cy - s * 0.46, cx + s * 0.24, cy + s * 0.46), radius=s * 0.08, outline=rgb(c), width=lw(f, 2.5))
    f.d.line([(cx - s * 0.42, cy + s * 0.42), (cx + s * 0.42, cy - s * 0.42)], fill=(0, 0, 0), width=lw(f, 6))
    f.d.line([(cx - s * 0.42, cy + s * 0.42), (cx + s * 0.42, cy - s * 0.42)], fill=rgb(c), width=lw(f, 3))


ICONS = dict(heart=heart, steps=steps, battery=battery, body=bolt, stress=stress, calories=flame,
             floors=stairs, intensity=chevrons, altitude=mountain, pulseox=drop, breath=lungs, notes=bubble,
             recovery=hourglass, pressure=trend, sleep=bed, calendar=calendar)
LABELS = dict(vo2="VO2", app="GLU")     # kinds shown by a short label in place of an icon


def draw_icon(face, kind, cx, cy, s, c, night, small=False):
    if kind in LABELS:
        face.text(cx, cy, font("RobotoCondensedBold", 0.032 if small else 0.042, face.size), LABELS[kind], c)
    elif kind == "sun":
        sun(face, cx, cy, s, c, rise=night)
    elif kind == "temp":
        weather(face, cx, cy + face.px(0.006), s, c, night)
    elif kind == "pressure":
        trend(face, cx, cy, s, c, 0 if night else 1)       # rising by day, steady at night
    else:
        ICONS[kind](face, cx, cy, s, c)


def icon_width(face, kind, s, small=False):
    if kind in LABELS:
        return face.width(font("RobotoCondensedBold", 0.032 if small else 0.042, face.size), LABELS[kind])
    return s


def draw_value(face, x, y, f, fu, value, unit, color, unit_color, align):
    """A value with its unit small on the same baseline, right- or left-
    aligned on x, its digits' ink centred on y. Returns its width."""
    vb = face.d.textbbox((0, 0), "0", font=f, anchor="ls")
    base = y + (vb[3] - vb[1]) / 2
    vw = face.width(f, value)
    pad = -face.px(0.005) if unit == "%" else face.px(0.004)     # % carries its own margin
    uw = face.width(fu, unit) + pad if unit else 0
    left = x - vw - uw if align == "r" else x
    face.text(left, base, f, value, color, "ls")
    if unit:
        face.text(left + vw + pad, base, fu, unit, unit_color, "ls")
    return vw + uw



# Each kind's word when set as text (Lib.Slots.word)
WORDS = dict(heart="BPM", steps="STEPS", battery="BATTERY", body="BODY BATT", stress="STRESS", temp="TEMP",
             calories="CAL", floors="FLOORS", intensity="ACTIVE MIN", altitude="", pulseox="SPO2", breath="BRPM",
             sun="SUNSET", notes="ALERTS", recovery="RECOVERY", vo2="VO2", sleep="SLEEP", pressure="", calendar="NEXT",
             app="GLU")
SHORT = dict(WORDS, battery="BATT", body="BODY", intensity="MIN", recovery="REST")


def word(kind, night, short=False):
    """Lib.Slots.word for a kind's sample (the sun: sunset by day, sunrise at night)."""
    if kind == "sun":
        return "SUNRISE" if night else "SUNSET"
    return (SHORT if short else WORDS)[kind]


def reading(kind, night):
    """(value, unit, fill 0..1 or None) for a kind's sample."""
    (v_day, v_night), (f_day, f_night) = KINDS[kind]
    v, u = v_night if night else v_day
    return v, u, (f_night if night else f_day)


# ------------------------------------------------------------------ moves

def digit_font(face, name, h):
    """The font whose digits' ink is h tall (supersampled px), as Lib.Ink.em."""
    probe = ImageFont.truetype(str(FONTS / FILES[name]), 1000)
    b = face.d.textbbox((0, 0), "0123456789", font=probe, anchor="ls")
    return ImageFont.truetype(str(FONTS / FILES[name]), int(1000 * h / (b[3] - b[1])))


_INK = {}


def ink_box(f, s):
    """The ink box of s drawn with its pen at (0, 0) on the baseline, from
    the rendered pixels (textbbox gives the advance, not the ink, so
    aligning by it puts a right-aligned "38" its right bearing short)."""
    key = (f.path, f.size, s)
    if key not in _INK:
        pad = f.size
        img = Image.new("L", (pad * (len(s) + 2), pad * 3), 0)
        ImageDraw.Draw(img).text((pad, 2 * pad), s, font=f, fill=255, anchor="ls")
        x0, y0, x1, y1 = img.point(lambda v: 255 if v > 127 else 0).getbbox()
        _INK[key] = (x0 - pad, y0 - 2 * pad, x1 - pad, y1 - 2 * pad)
    return _INK[key]


def place(face, f, s, x_ink, y_mid, align="r"):
    """The pen (x, baseline) that puts s's ink against x_ink (its right
    edge, left edge or centre) with its digits centred on y_mid, and the
    ink box, as Lib.Ink places it on the watch."""
    b = ink_box(f, s)
    d = ink_box(f, "0123456789")
    x = x_ink - b[2] if align == "r" else (x_ink - b[0] if align == "l" else x_ink - (b[0] + b[2]) / 2)
    base = y_mid - (d[1] + d[3]) / 2
    return x, base, (x + b[0], base + d[1], x + b[2], base + d[3])


def glyph_mask(face, f, s, x, base):
    m = Image.new("L", face.img.size, 0)
    ImageDraw.Draw(m).text((x, base), s, font=f, fill=255, anchor="ls")
    return m


def paint(face, mask, color):
    face.img.paste(Image.new("RGB", face.img.size, rgb(color)), (0, 0), mask)


def outline_of(mask, px):
    """The inner `px` of a glyph mask: its outline drawn inside the shape."""
    k = int(px) | 1
    return ImageChops.subtract(mask, mask.filter(ImageFilter.MinFilter(k)))


def band(mask, top, bottom):
    """The part of a mask between two heights."""
    b = Image.new("L", mask.size, 0)
    ImageDraw.Draw(b).rectangle((0, top, mask.size[0], bottom), fill=255)
    return ImageChops.multiply(mask, b)


def spaced(face, x, y, f, s, color, track, anchor="m"):
    """Capitals with letter spacing on one line, y their middle; anchor
    l, m or r. Returns the width."""
    widths = [face.width(f, ch) for ch in s]
    total = sum(widths) + track * (len(s) - 1)
    x0 = x if anchor == "l" else (x - total / 2 if anchor == "m" else x - total)
    for ch, w in zip(s, widths):
        face.text(x0, y, f, ch, color, "lm")
        x0 += w + track
    return total


def radial(face, s, f, color, angle, r, track, bottom=False):
    """Text on a circle like a coin's legend (Dc.drawRadialText), centred
    on `angle` (degrees clockwise from 12 o'clock), its middle on radius r;
    along the bottom it reads left to right, tops toward the centre.
    Returns its span in degrees."""
    c = face.img.size[0] / 2
    widths = [face.width(f, ch) for ch in s]
    total = sum(widths) + track * (len(s) - 1)
    pos = -total / r / 2
    for ch, w in zip(s, widths):
        a = math.radians(angle) + (pos + w / 2 / r) * (-1 if bottom else 1)
        pos += (w + track) / r
        if ch == " ":
            continue
        size = int(f.size * 1.8)
        g = Image.new("L", (size, size), 0)
        ImageDraw.Draw(g).text((size / 2, size / 2), ch, font=f, fill=255, anchor="mm")
        g = g.rotate(-(math.degrees(a) + (180 if bottom else 0)), resample=Image.BICUBIC)
        x = c + r * math.sin(a) - size / 2
        y = c - r * math.cos(a) - size / 2
        face.img.paste(Image.new("RGB", (size, size), rgb(color)), (int(x), int(y)), g)
    return math.degrees(total / r)


def options(argv, defaults):
    """key=value switches over the defaults; comma lists become tuples,
    hex colours (0x...) and numbers become ints."""
    chosen = dict(defaults)
    for a in argv:
        k, v = a.split("=")
        if k == "slots":
            chosen[k] = tuple(v.split(","))
        elif v.startswith("0x"):
            chosen[k] = int(v, 16)
        else:
            chosen[k] = int(v)
    return chosen


def accent_color(st):
    """The accent: an index into ACCENTS or a 0x colour, lifted to read on
    black as Lib.Config.lift does."""
    a = st["accent"]
    c = ACCENTS[a][1] if a < len(ACCENTS) else a
    r, g, b = rgb(c)
    lum = lambda r, g, b: 0.2126 * (r / 255) ** 2 + 0.7152 * (g / 255) ** 2 + 0.0722 * (b / 255) ** 2  # noqa: E731
    if lum(r, g, b) >= 0.30:
        return c
    top = max(r, g, b)
    if top:
        r, g, b = r * 255 // top, g * 255 // top, b * 255 // top
    for _ in range(12):
        if lum(r, g, b) >= 0.30:
            break
        r, g, b = r + (255 - r) // 4, g + (255 - g) // 4, b + (255 - b) // 4
    return (r << 16) | (g << 8) | b


QUIET = 0.75    # icons and quiet text: the data colour at this (Lib.Config.QUIET)


def sheet(out, items, cols=None):
    """A contact sheet: (path, label) pairs in rows."""
    ims = [(Image.open(p), label) for p, label in items]
    w = ims[0][0].width
    cols = cols or len(ims)
    rows = (len(ims) + cols - 1) // cols
    pad, lab = 12, 40
    s = Image.new("RGB", (cols * w + (cols + 1) * pad, rows * (w + lab) + (rows + 1) * pad), (24, 24, 24))
    d = ImageDraw.Draw(s)
    f = ImageFont.truetype(str(FONTS / "Roboto-Regular.ttf"), 22)
    for k, (im, label) in enumerate(ims):
        x = pad + (k % cols) * (w + pad)
        y = pad + (k // cols) * (w + lab + pad)
        s.paste(im, (x, y))
        d.text((x + w / 2, y + w + lab / 2), label, font=f, fill=(210, 210, 210), anchor="mm")
    s.save(out)
