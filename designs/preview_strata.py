#!/usr/bin/env python3
"""Render the Strata face (design #12) to a PNG with sample readings, so
a layout can be judged without the simulator, whose readings are mostly
empty (no heart-rate history, no distance, no alarms).

It draws what StrataView draws, from the same generated field
(gen_strata.generate) and the same layout fractions, with the watch's own
vector fonts (the TTFs the Connect IQ SDK downloads). Lines are drawn
four times over size and scaled down, close to the watch's anti-aliasing.

    python3 designs/preview_strata.py out.png [day|night|aod] [454|416] [strata=0-4 accent=0-4 time=0-2 ...]

Needs Pillow. Approximate: the watch's text metrics differ by a pixel or
two, so check the real face with scripts/sim.sh before trusting a pixel.
"""
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen_strata as G  # noqa: E402

FONTS = Path.home() / "Library/Application Support/Garmin/ConnectIQ/Fonts"
SS = 4

# The layout, as fractions of the screen: the same numbers as StrataView
# and gen_strata.ISLANDS
L = dict(
    sun_y=0.150,
    date_y=0.252,
    time_y=0.473,
    time_size=0.31,         # the time's em, of the width
    cue_y=0.657,            # the row of cues over the readings
    row_y=0.738,
    row_x=(0.186, 0.391, 0.596, 0.801),
    moon_y=0.862,
    moon_r=0.074,
    sun_time_size=0.064,
    date_size=0.086,
    row_size=0.060,
    unit_size=0.036,
    cue_size=0.036,
    moon_size=0.034,
)

C = dict(
    white=0xF2ECE2,         # warm white, like paper
    cream=0xE6DCCB,
    gray=0x8A8478,
    dim=0x5A564E,
    sunrise=0xE9B04F,
    sunset=0xE8854A,
    heart=0xC4584A,         # rosehip
    feet=0xB8AD9A,
    stone_day=0x4E3E26,
    stone_night=0x353B49,
    moon_lit=0x4E4A42,
    moon_rim=0x9C937F,
    aod_moon=0x4A463F,
)

SAMPLES = {
    "day": dict(time="14:38", rise=False, sun="19:22", date="FRI OCT 30", celsius=7.8,
                hr="72", miles="3.4", unit="mi", pebbles=13, alarms=1, phase=0.62, day=True),
    "night": dict(time="21:05", rise=True, sun="07:12", date="FRI OCT 30", celsius=-2.2,
                  hr="58", miles="0.4", unit="mi", pebbles=1, alarms=0, phase=0.12, day=False),
}


# The settings' colours, as Palette.mc has them
STRATA_DAY = [0x5C4A2E, 0x7A402E, 0x44582E, 0x405268, 0x76705A]      # Soil, Clay, Moss, Slate, Sand
STRATA_NIGHT = [0x3E4556, 0x573B34, 0x2C4A44, 0x2A466A, 0x4E4A40]
MOONLIGHT = 0x9FB4C8
ACCENTS = [None, None, 0xE0B050, 0x6FA8A0, 0xC8703E]                  # temperature, tone on tone, Ochre, Lichen, Ember
TIMES = [0xF2ECE2, None, 0xD9B98C]                                    # Bone, the accent, Sandstone
DEFAULTS = dict(strata=0, accent=0, time=0, outline=False, daynight=True, stones=True, slots=(0, 1, 2, 3))
# The reading kinds (Readings.Kind) and a sample of each, as the sample build has them
KINDS = ["temperature", "rain", "heart", "distance", "body battery", "elevation", "humidity", "wind", "battery", "steps"]
KIND_SAMPLES = [("46", "°F"), ("20", "%"), ("72", "bpm"), ("3.4", "mi"), ("64", ""), ("5280", "ft"),
                ("68", "%"), ("8", "mph"), ("81", "%"), ("8412", "")]
RAIN, DEW, LEAF, STONE, WIND = 0x8FB8C8, 0x7FA8B8, 0x9CC07A, 0xB8AD9A, 0xA8B4BC


def blend(c0, c1, t):
    a, b = rgb(c0), rgb(c1)
    r, g, bl = (int(a[j] + (b[j] - a[j]) * t + 0.5) for j in range(3))
    return (r << 16) | (g << 8) | bl


def colours(s, settings):
    """earth, the accent layers, the time and the thermometer, as StrataView
    picks them for these settings."""
    night = not s["day"] and settings["daynight"]
    earth = (STRATA_NIGHT if night else STRATA_DAY)[settings["strata"]]
    temp = temperature_color(s["celsius"])
    choice = settings["accent"]
    full = blend(earth, C["cream"], 0.55) if choice == 1 else (temp if choice == 0 else ACCENTS[choice])
    if choice == 1:
        layer = blend(earth, C["cream"], 0.25)
    elif choice == 0:
        layer = blend(earth, MOONLIGHT, 0.5) if night else scale(full, 0.65)
    else:
        layer = scale(full, 0.7 if night else 0.8)
    time = full if settings["time"] == 1 else TIMES[settings["time"]]
    return earth, layer, time, temp, night


def rgb(c):
    return ((c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF)


def temperature_color(celsius):
    stops_f = [25.0, 45.0, 60.0, 72.0, 85.0, 100.0]
    stops_c = [0x8FB8C8, 0x6FA8A0, 0x8FAE6A, 0xD2A24C, 0xC8703E, 0xB84A3A]
    f = celsius * 9 / 5 + 32
    if f <= stops_f[0]:
        return stops_c[0]
    if f >= stops_f[-1]:
        return stops_c[-1]
    i = 0
    while f > stops_f[i + 1]:
        i += 1
    t = (f - stops_f[i]) / (stops_f[i + 1] - stops_f[i])
    a, b = rgb(stops_c[i]), rgb(stops_c[i + 1])
    r, g, bl = (int(a[j] + (b[j] - a[j]) * t + 0.5) for j in range(3))
    return (r << 16) | (g << 8) | bl


def font(name, frac, size):
    """The face at `frac` of the width per em (the watch's StrataView asks
    for 1.17 times that, since it sizes vector fonts by their height)."""
    files = {"RobotoCondensedBold": "RobotoCondensed-Bold.ttf",
             "RobotoCondensedRegular": "RobotoCondensed-Regular.ttf",
             "BionicBold": "Bionic_Bold.ttf", "PridiRegular": "Pridi-Regular.ttf",
             "RobotoMedium": "Roboto-Medium.ttf", "RobotoRegular": "Roboto-Regular.ttf"}
    return ImageFont.truetype(str(FONTS / files[name]), int(size * frac) * SS)


class Face:
    def __init__(self, size):
        self.size = size
        self.k = size / G.SIZE * SS             # generated px -> canvas px
        self.img = Image.new("RGB", (size * SS, size * SS), (0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    def px(self, frac):
        return frac * self.size * SS

    def line(self, pts, color, width=1):
        self.d.line([(x * self.k, y * self.k) for x, y in pts], fill=rgb(color), width=int(width * SS), joint="curve")

    def text(self, x, y, f, s, color, anchor="mm"):
        self.d.text((x, y), s, font=f, fill=rgb(color), anchor=anchor)

    def width(self, f, s):
        return self.d.textlength(s, font=f)

    def done(self, path):
        small = self.img.resize((self.size, self.size), Image.LANCZOS)
        mask = Image.new("L", (self.size, self.size), 0)
        ImageDraw.Draw(mask).ellipse((0, 0, self.size - 1, self.size - 1), fill=255)
        out = Image.new("RGB", (self.size, self.size), (24, 24, 24))
        out.paste(small, (0, 0), mask)
        out.save(path)
        big = out.resize((self.size * 2, self.size * 2), Image.LANCZOS)
        big.save(str(path).replace(".png", "@2x.png"))


def draw_field(face, lines, earth, accent, only_accent=False):
    for k, first, ys in lines:
        is_accent = k % 4 == 3
        if only_accent and not is_accent:
            continue
        pts = [((first + i) * G.STEP, y) for i, y in enumerate(ys)]
        face.line(pts, accent if is_accent else earth)


def scale(c, f):
    r, g, b = rgb(c)
    return (int(r * f) << 16) | (int(g * f) << 8) | int(b * f)


def arrow(face, cx, cy, s, rise, color):
    """The sun on the horizon and an open chevron over it, pointing up for
    sunrise and down for sunset; `s` is the horizon's length."""
    d, w = face.d, int(2 * SS)
    hy = cy + s * 0.36                      # the horizon
    r = s * 0.33
    d.pieslice((cx - r, hy - r, cx + r, hy + r), 180, 360, fill=rgb(color))
    d.line([(cx - s / 2, hy), (cx + s / 2, hy)], fill=rgb(color), width=w)
    c = s * 0.24                            # the chevron's half width
    near = hy - r - s * 0.2                 # its foot, clear of the sun
    far = near - s * 0.22
    if rise:
        pts = [(cx - c, near), (cx, far), (cx + c, near)]
    else:
        pts = [(cx - c, far), (cx, near), (cx + c, far)]
    d.line(pts, fill=rgb(color), width=w, joint="curve")


def draw_cue(face, kind, x, y, s, accent, feet):
    if kind == 0:
        thermometer(face, x, y, s, accent)
    elif kind == 1:
        cloud(face, x, y, s, RAIN)
    elif kind == 6:
        drop(face, x, y, s, DEW, True)
    elif kind == 2:
        heart(face, x, y, s * 0.85, C["heart"])
    elif kind == 3:
        trail(face, x, y, s, feet)
    elif kind == 9:
        footprints(face, x, y, s, feet)
    elif kind == 4:
        bolt(face, x, y, s, LEAF)
    elif kind == 5:
        mountain(face, x, y, s, feet)
    elif kind == 7:
        wind(face, x, y, s, WIND)
    elif kind == 8:
        battery(face, x, y, s, STONE, 81)


def drop(face, cx, cy, s, color, filled):
    r = s * 0.27
    by = cy + s * 0.5 - r
    pts = [(cx, cy - s * 0.5)] + [(cx + r * math.cos(math.pi * (-0.2 + 1.4 * i / 16)), by + r * math.sin(math.pi * (-0.2 + 1.4 * i / 16)))
                                  for i in range(17)]
    if filled:
        face.d.polygon(pts, fill=rgb(color))
    else:
        face.d.line(pts + [pts[0]], fill=rgb(color), width=2 * SS, joint="curve")


def cloud(face, cx, cy, s, color):
    d = face.d
    for x, y, r in ((-0.2, -0.08, 0.2), (0.06, -0.2, 0.26), (0.3, -0.06, 0.18)):
        d.ellipse((cx + (x - r) * s, cy + (y - r) * s, cx + (x + r) * s, cy + (y + r) * s), fill=rgb(color))
    d.rounded_rectangle((cx - s * 0.4, cy - s * 0.08, cx + s * 0.48, cy + s * 0.12), radius=s * 0.1, fill=rgb(color))
    for x in (-0.12, 0.16):
        d.line([(cx + x * s, cy + s * 0.26), (cx + (x - 0.06) * s, cy + s * 0.46)], fill=rgb(color), width=2 * SS)


def trail(face, cx, cy, s, color):
    d = face.d
    for x, y in ((-0.42, 0.36), (-0.16, 0.4), (0.02, 0.16)):
        d.ellipse((cx + (x - 0.1) * s, cy + (y - 0.1) * s, cx + (x + 0.1) * s, cy + (y + 0.1) * s), fill=rgb(color))
    px, py, pr = cx + s * 0.22, cy - s * 0.2, s * 0.2
    d.ellipse((px - pr, py - pr, px + pr, py + pr), fill=rgb(color))
    d.polygon([(px - pr * 0.85, py + pr * 0.5), (px + pr * 0.85, py + pr * 0.5), (px, py + pr * 2.1)], fill=rgb(color))
    d.ellipse((px - pr * 0.4, py - pr * 0.4, px + pr * 0.4, py + pr * 0.4), fill=(0, 0, 0))


def bolt(face, cx, cy, s, color):
    face.d.polygon([(cx + s * 0.22, cy - s * 0.5), (cx - s * 0.4, cy + s * 0.08), (cx - s * 0.03, cy + s * 0.08),
                    (cx - s * 0.22, cy + s * 0.5), (cx + s * 0.4, cy - s * 0.1), (cx + s * 0.03, cy - s * 0.1)], fill=rgb(color))


def mountain(face, cx, cy, s, color):
    foot = cy + s * 0.4
    face.d.polygon([(cx - s * 0.12, cy - s * 0.45), (cx + s * 0.32, foot), (cx - s * 0.56, foot)], fill=rgb(color))
    face.d.polygon([(cx + s * 0.28, cy - s * 0.12), (cx + s * 0.56, foot), (cx, foot)], fill=rgb(color))


def wind(face, cx, cy, s, color):
    for i, length in enumerate((0.85, 0.6, 0.75)):
        y = cy + (i - 1) * s * 0.3
        left = cx - s * 0.5
        right = left + s * length
        face.d.line([(left, y), (right, y)], fill=rgb(color), width=2 * SS)
        r = s * 0.13
        if i == 0:      # curls up and back (Pillow's angles run clockwise)
            face.d.arc((right - r, y - 2 * r, right + r, y), 180, 90, fill=rgb(color), width=2 * SS)
        elif i == 2:    # curls down and back
            face.d.arc((right - r, y, right + r, y + 2 * r), 270, 180, fill=rgb(color), width=2 * SS)


def battery(face, cx, cy, s, color, level):
    bw, bh = s * 0.5, s * 0.86
    left, top = cx - bw / 2, cy - s / 2 + s * 0.14
    face.d.rounded_rectangle((left, top, left + bw, top + bh), radius=2 * SS, outline=rgb(color), width=2 * SS)
    face.d.rectangle((cx - bw / 4, cy - s / 2, cx + bw / 4, cy - s / 2 + s * 0.12), fill=rgb(color))
    inner = (bh - 6 * SS) * level / 100
    face.d.rectangle((left + 3 * SS, top + bh - 3 * SS - inner, left + bw - 3 * SS, top + bh - 3 * SS), fill=rgb(color))


def heart(face, cx, cy, s, color):
    d = face.d
    r = s * 0.27
    top = cy - s * 0.30
    d.ellipse((cx - 2 * r, top - r, cx, top + r), fill=rgb(color))
    d.ellipse((cx, top - r, cx + 2 * r, top + r), fill=rgb(color))
    d.polygon([(cx - 2 * r + r * 0.08, top + r * 0.35), (cx + 2 * r - r * 0.08, top + r * 0.35), (cx, cy + s * 0.42)],
              fill=rgb(color))


def thermometer(face, cx, cy, s, color):
    """A filled thermometer `s` tall: a stem and a bulb."""
    d = face.d
    br = s * 0.22
    by = cy + s * 0.5 - br
    stem = s * 0.14
    d.rounded_rectangle((cx - stem, cy - s * 0.5, cx + stem, by), radius=stem, fill=rgb(color))
    d.ellipse((cx - br, by - br, cx + br, by + br), fill=rgb(color))


def footprints(face, cx, cy, s, color):
    """Two prints `s` tall, one ahead of the other: a sole and a heel."""
    d = face.d
    for dx, dy in ((-0.28, 0.08), (0.28, -0.08)):
        x, y = cx + dx * s, cy + dy * s
        d.ellipse((x - s * 0.18, y - s * 0.45, x + s * 0.18, y + s * 0.11), fill=rgb(color))
        d.ellipse((x - s * 0.13, y + s * 0.185, x + s * 0.13, y + s * 0.415), fill=rgb(color))


def bell(face, cx, cy, s, color):
    d, w = face.d, int(1.6 * SS)
    d.arc((cx - s * 0.32, cy - s * 0.46, cx + s * 0.32, cy + s * 0.18), 180, 360, fill=rgb(color), width=w)
    d.line([(cx - s * 0.32, cy - s * 0.14), (cx - s * 0.36, cy + s * 0.22)], fill=rgb(color), width=w)
    d.line([(cx + s * 0.32, cy - s * 0.14), (cx + s * 0.36, cy + s * 0.22)], fill=rgb(color), width=w)
    d.line([(cx - s * 0.46, cy + s * 0.24), (cx + s * 0.46, cy + s * 0.24)], fill=rgb(color), width=w)
    d.ellipse((cx - s * 0.08, cy + s * 0.3, cx + s * 0.08, cy + s * 0.46), fill=rgb(color))


def moon(face, cx, cy, r, phase, lit, rim):
    d = face.d
    c = math.cos(2 * math.pi * phase)
    if c < 0.98:
        side = 1 if phase < 0.5 else -1
        pts = []
        for i in range(49):
            a = -math.pi / 2 + math.pi * i / 48
            pts.append((cx + side * r * math.cos(a), cy + r * math.sin(a)))
        for i in range(49):
            dy = r - 2 * r * i / 48
            half = math.sqrt(max(r * r - dy * dy, 0))
            pts.append((cx + side * c * half, cy + dy))
        d.polygon(pts, fill=rgb(lit))
    d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=rgb(rim), width=int(1.5 * SS))


def phase_name(phase):
    names = ["NEW MOON", "WAXING CRESCENT", "FIRST QUARTER", "WAXING GIBBOUS",
             "FULL MOON", "WANING GIBBOUS", "LAST QUARTER", "WANING CRESCENT"]
    return names[int((phase + 0.0625) * 8) % 8]


def time_text(face, cx, cy, f, text, fill, keyline, outline_only=False):
    """The time, centred on (cx, cy) by its digits' height, cut out of the
    layers by a black keyline (on the watch: the text drawn black at eight
    offsets, then in colour)."""
    if outline_only:
        face.d.text((cx, cy), text, font=f, fill=(0, 0, 0), anchor="mm", stroke_width=int(1.5 * SS), stroke_fill=rgb(fill))
        return
    face.d.text((cx, cy), text, font=f, fill=rgb(fill), anchor="mm", stroke_width=int(keyline * SS), stroke_fill=(0, 0, 0))


def render(path, mode="day", size=454, settings=None):
    settings = dict(DEFAULTS, **(settings or {}))
    s = SAMPLES["night" if mode == "night" else "day"]
    lines, pebbles = G.generate(7)
    face = Face(size)
    w = size * SS
    cx = w / 2
    earth, field_accent, time_color, accent, night = colours(s, settings)
    f_time = font("RobotoCondensedBold", L["time_size"], size)
    f_sun = font("RobotoCondensedBold", L["sun_time_size"], size)

    def sun_line(color_rise, color_set, text_color, alarms):
        """The time centred on the axis, the sun's arrow hung to its left
        and a bell to its right while an alarm is set."""
        y = face.px(L["sun_y"])
        a = face.px(0.052)
        gap = face.px(0.020)
        b = face.px(0.030)
        tw = face.width(f_sun, s["sun"])
        face.text(cx, y, f_sun, s["sun"], text_color)
        arrow(face, cx - tw / 2 - gap - a / 2, y, a, s["rise"], color_rise if s["rise"] else color_set)
        if alarms:
            bell(face, cx + tw / 2 + gap + b / 2, y, b, C["moon_rim"])

    if mode == "aod":
        aod = [l for l in G.generate(7, G.AOD_ISLANDS)[0] if l[0] % 8 == 7]
        draw_field(face, aod, 0, scale(field_accent, 0.6), only_accent=True)
        time_text(face, cx, face.px(L["time_y"]), f_time, s["time"], 0x9A9488, 0, outline_only=True)
        sun_line(0x6A6458, 0x6A6458, 0x6A6458, 0)
        face.text(cx, face.px(L["date_y"]), font("RobotoCondensedRegular", 0.070, size), s["date"], C["gray"])
        r = face.px(L["moon_r"])
        my = face.px(L["moon_y"])
        if math.cos(2 * math.pi * s["phase"]) < 0.98:     # the lit limb only
            start = 270 if s["phase"] < 0.5 else 90
            face.d.arc((cx - r, my - r, cx + r, my + r), start, start + 180, fill=rgb(0x6A6458), width=int(1.5 * SS))
            c, side = math.cos(2 * math.pi * s["phase"]), (1 if s["phase"] < 0.5 else -1)
            pts = [(cx + side * c * math.sqrt(max(r * r - dy * dy, 0)), my + dy)
                   for dy in (-r + 2 * r * i / 24 for i in range(25))]
            face.d.line(pts, fill=rgb(0x5A564E), width=SS)
        face.done(path)
        return

    draw_field(face, lines, earth, field_accent)
    stone = C["stone_night"] if night else C["stone_day"]
    for px_, py_, rx, ry in pebbles[:s["pebbles"] if s["pebbles"] >= 4 and settings["stones"] else 0]:
        k = face.k
        face.d.ellipse(((px_ - rx) * k, (py_ - ry * 0.8) * k, (px_ + rx) * k, (py_ + ry * 0.8) * k), fill=rgb(stone))

    # The time, clean, cut out of the layers
    if settings["outline"]:
        # A wider keyline clears the layers round the outline; inside it stays black
        line = 3 if size >= 440 else 2   # heavier than the date on the big screens
        face.d.text((cx, face.px(L["time_y"])), s["time"], font=f_time, fill=(0, 0, 0), anchor="mm",
                    stroke_width=(3 + line) * SS, stroke_fill=(0, 0, 0))
        face.d.text((cx, face.px(L["time_y"])), s["time"], font=f_time, fill=(0, 0, 0), anchor="mm",
                    stroke_width=line * SS, stroke_fill=rgb(time_color))
    else:
        time_text(face, cx, face.px(L["time_y"]), f_time, s["time"], time_color, 3)

    # The next sun event: its arrow and its time, centred together
    sun_line(C["sunrise"], C["sunset"], C["cream"], s["alarms"])

    # The date, larger
    face.text(cx, face.px(L["date_y"]), font("RobotoCondensedRegular", L["date_size"], size), s["date"], C["cream"])

    # The four readings the settings chose: a coloured cue over each number
    cue_y, row_y = face.px(L["cue_y"]), face.px(L["row_y"])
    cue = face.px(L["cue_size"])
    f_val = font("RobotoCondensedBold", L["row_size"], size)
    f_unit = font("RobotoCondensedRegular", L["unit_size"], size)
    feet = 0x8A94A6 if night else C["feet"]
    for x, kind in zip((face.px(v) for v in L["row_x"]), settings["slots"]):
        value, unit = KIND_SAMPLES[kind]
        if kind == 0:
            value = str(round(s["celsius"] * 9 / 5 + 32))
        elif kind == 2:
            value = s["hr"]
        elif kind == 3:
            value, unit = s["miles"], s["unit"]
        draw_cue(face, kind, x, cue_y, cue, accent, feet)
        # The number centred under its cue, the unit hung off its right
        vw = face.width(f_val, value)
        face.text(x - vw / 2, row_y, f_val, value, C["cream"], "ls")
        if unit:
            face.text(x + vw / 2 + face.px(0.008), row_y, f_unit, unit, C["gray"], "ls")

    # The moon, its phase in it
    my, mr = face.px(L["moon_y"]), face.px(L["moon_r"])
    moon(face, cx, my, mr, s["phase"], C["moon_lit"], C["moon_rim"])
    f = font("RobotoCondensedRegular", L["moon_size"], size)
    words = phase_name(s["phase"]).title().split(" ")
    gap = face.px(0.021)
    for n, word in enumerate(words):
        face.text(cx, my + (n - (len(words) - 1) / 2) * 2 * gap, f, word, C["white"])
    face.done(path)


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "strata.png"
    # Settings as key=value after the size: strata=0-4 accent=0-4 time=0-2 outline=0/1 daynight=0/1 stones=0/1
    # slots=0123 (a reading kind 0-9 for each of the four slots)
    chosen = {k: (tuple(int(c) for c in v) if k == "slots" else int(v)) for k, v in (a.split("=") for a in sys.argv[4:])}
    render(out, sys.argv[2] if len(sys.argv) > 2 else "day", int(sys.argv[3]) if len(sys.argv) > 3 else 454, chosen)
    print(out)
