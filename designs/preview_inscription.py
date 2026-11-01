#!/usr/bin/env python3
"""Render the Inscription face (design #17) with sample readings: what
InscriptionView draws, from the same layout fractions.

    python3 -I designs/preview_inscription.py out.png [day|night|aod|bedside] [454|416] [style=0-3 accent=0-7|0xRRGGBB data=0-4 slots=a,b,c,d,e hours=14 minutes=38 alarm=0/1 date=WEDNESDAY_30_SEPTEMBER]

Styles: 0 Pridi (the legend in Pridi too), 1 Bionic, 2 Condensed, 3
Rajdhani. Slots name a reading kind each (preview_faces.KINDS): nine
o'clock, three o'clock, then the bottom left to right. date= takes the
weekday, day and month with underscores; its short form is made from it.
Prints the share of the round screen lit (always-on must stay under
10 %). Approximate to a pixel or two: check the real face with
scripts/sim.sh (drawRadialText's radius is taken as the text's middle).
"""
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))   # run with -I
from PIL import Image, ImageDraw  # noqa: E402
from preview_faces import (BEDSIDE, DATA, SS, Face, accent_color, bell, digit_font, font, glyph_mask,  # noqa: E402
                           options, outline_of, paint, reading, rgb, scale, word)

L = dict(
    digits=0.250, aod_digits=0.235,   # each row's digit height
    row_gap=0.035,                    # between the hours' and the minutes' ink
    legend_em=0.038,
    radius=0.425,                     # the legend's middle, from the centre
    value_track=0.008,                # letter spacing in a value
    word_track=0.010,                 # in a word and the date
    tight_track=0.006,                # in a word, when the legend would not fit
    word_gap=0.012,                   # between a value and its word
    word_space=0.013,                 # between the words of a name ("BODY BATT")
    separator_gap=0.024, tight_gap=0.0145,   # either side of the dot between bottom readings, and closed up
    beads=72, bead_radius=0.372, bead_size=0.9, bead=0.30,   # the beaded rim: a dot every 5°
    value=0.85, word=0.60,            # the values' and words' shares of the data colour
    aod_value=0.50, aod_word=0.36, aod_date=0.6,
    bell_y=0.165, bell=0.026,         # the alarm bell, at twelve inside the beads
    night=0.85,                       # the colours after sunset
    date_span=100.0, side_span=32.0, bottom_span=112.0,   # the arcs the legend may fill
)
LONG, SHORT, BARE = range(3)
STYLES = ["PridiRegular", "BionicBold", "RobotoCondensedBold", "BionicMedium"]   # Pridi, Bionic, Condensed, Rajdhani
DEFAULTS = dict(style=0, accent=0, data=0, slots=("temp", "battery", "heart", "steps", "body"), alarm=1)
SAMPLES = {"day": dict(hours="14", minutes="38", night=False),
           "night": dict(hours="21", minutes="05", night=True)}


def item(kind, night, level, value_c, word_c, px, tight=False):
    """A reading as runs (text, colour, tracking, gap before, the gap a
    space inside makes or 0): its value, its unit tight against it, and by
    level its word, closed up if tight."""
    value, unit, _ = reading(kind, night)
    value, unit = value.upper(), unit.upper()
    if not unit and len(value) > 1 and value.endswith("°"):
        value, unit = value[:-1], "°"
    runs = [(value, value_c, px(L["value_track"]), 0, 0)]
    if unit:
        runs.append((unit, value_c, px(L["value_track"]), 0, 0))
    if level < BARE:
        name = word(kind, night, level != LONG)
        if name:
            runs.append((name, word_c, px(L["tight_track"] if tight else L["word_track"]), px(L["word_gap"]),
                         px(L["word_space"])))
    return runs


def width(face, f, ch, run):
    """A character's width in a run; a space set to make the run's own gap
    (InscriptionView.width)."""
    if run[4] and ch == " ":
        return run[4] - 2 * run[2]
    return face.width(f, ch)


def runs_length(face, f, runs):
    total = 0
    for i, run in enumerate(runs):
        text, _, track, gap, _ = run
        total += (gap if i else 0) + sum(width(face, f, ch, run) for ch in text) + track * (len(text) - 1)
    return total


def legend(face, f, runs, angle, bottom=False):
    """Runs round the rim, centred on angle (degrees clockwise from twelve),
    one character at a time as InscriptionView.legend. Returns the length."""
    c = face.img.size[0] / 2
    r = face.px(L["radius"])
    total = runs_length(face, f, runs)
    pos = -total / 2
    for i, run in enumerate(runs):
        text, color, track, gap, _ = run
        pos += gap if i else 0
        for j, ch in enumerate(text):
            cw = width(face, f, ch, run)
            a = math.radians(angle) + (pos + cw / 2) / r * (-1 if bottom else 1)
            pos += cw + (track if j < len(text) - 1 else 0)
            if ch == " ":
                continue
            size = int(f.size * 1.8)
            g = Image.new("L", (size, size), 0)
            ImageDraw.Draw(g).text((size / 2, size / 2), ch, font=f, fill=255, anchor="mm")
            g = g.rotate(-(math.degrees(a) + (180 if bottom else 0)), resample=Image.BICUBIC)
            face.img.paste(Image.new("RGB", (size, size), rgb(color)),
                           (int(c + r * math.sin(a) - size / 2), int(c - r * math.cos(a) - size / 2)), g)
    return total


def ink_centred(face, f, text, cx, mid):
    """The pen that centres text's ink on (cx, mid), from its rendered pixels."""
    m = glyph_mask(face, f, text, 0, face.img.size[1] / 2)
    x0, _, x1, _ = m.getbbox()
    d = face.d.textbbox((0, 0), "0123456789", font=f, anchor="ls")
    return cx - (x0 + x1) / 2, mid - (d[1] + d[3]) / 2


def render(path, mode="day", size=454, st=None, date="SATURDAY · 31 OCTOBER"):
    st = dict(DEFAULTS, **(st or {}))
    sm = dict(SAMPLES["night" if mode in ("night", "bedside") else "day"])
    if "hours" in st:
        sm["hours"] = str(st["hours"])
    if "minutes" in st:
        sm["minutes"] = f"{st['minutes']:02d}"
    night = sm["night"]
    thin = mode in ("aod", "bedside")
    face = Face(size)
    px = face.px
    W = size * SS
    cx = cy = W / 2
    r = px(L["radius"])
    dim = L["night"] if night else 1.0
    data = scale(DATA[st["data"]][1], dim)
    accent = scale(accent_color(st), dim)

    if not thin:    # the beaded rim
        br, bs = px(L["bead_radius"]), L["bead_size"] * SS * size / 454
        for i in range(L["beads"]):
            a = 2 * math.pi * i / L["beads"]
            x, y = cx + br * math.sin(a), cy - br * math.cos(a)
            face.d.ellipse((x - bs, y - bs, x + bs, y + bs), fill=rgb(scale(data, L["bead"])))

    # The time, centred on its ink: solid awake, outlined in standby
    dh = px(L["aod_digits"] if thin else L["digits"])
    f = digit_font(face, STYLES[st["style"]], dh)
    gap = px(L["row_gap"])
    colors = (BEDSIDE, BEDSIDE) if mode == "bedside" else ((scale(data, 0.8), scale(accent, 0.8)) if thin else (data, accent))
    for row, text in enumerate((sm["hours"], sm["minutes"])):
        mid = cy - dh / 2 - gap / 2 if row == 0 else cy + dh / 2 + gap / 2
        x, base = ink_centred(face, f, text, cx, mid)
        if thin:
            paint(face, outline_of(glyph_mask(face, f, text, x, base), SS * 1.5), colors[row])
        else:
            face.text(x, base, f, text, colors[row], "ls")
    if mode == "bedside":
        if st["alarm"]:
            bell(face, cx, px(L["bell_y"]), px(L["bell"]), BEDSIDE)
        return face.done(path)

    # The date across the top (its short form if too long), the bell at twelve
    lf = font("PridiRegular" if st["style"] == 0 else "RobotoCondensedRegular", L["legend_em"], size)
    date_c = scale(accent, L["aod_date"]) if thin else accent
    runs = [(date, date_c, px(L["word_track"]), 0, 0)]
    if runs_length(face, lf, runs) > math.radians(L["date_span"]) * r:
        day, num, month = date.replace(" · ", " ").split()
        runs = [(f"{day[:3]} · {num} {month[:3]}", date_c, px(L["word_track"]), 0, 0)]
    legend(face, lf, runs, 0)
    if st["alarm"]:
        bell(face, cx, px(L["bell_y"]), px(L["bell"]), scale(accent, 0.7))

    # The readings: nine o'clock, three o'clock (from their short words),
    # then the bottom, where the longest item steps down first
    value_c = scale(data, L["aod_value"] if thin else L["value"])
    word_c = scale(data, L["aod_word"] if thin else L["word"])
    slots = st["slots"]
    if not thin:
        side = math.radians(L["side_span"]) * r
        for kind, angle in ((slots[0], 270), (slots[1], 90)):
            runs = item(kind, night, SHORT, value_c, word_c, px)
            if runs_length(face, lf, runs) > side:
                runs = item(kind, night, SHORT, value_c, word_c, px, True)
            if runs_length(face, lf, runs) > side:
                runs = item(kind, night, BARE, value_c, word_c, px, True)
            legend(face, lf, runs, angle)
    # Along the bottom: closed up, then the longest item steps down first
    levels = [LONG] * 3
    tight = [False]

    def items():
        return [item(k, night, levels[i], value_c, word_c, px, tight[0]) for i, k in enumerate(slots[2:])]

    def total(its):
        dot = face.width(lf, "·") + 2 * px(L["tight_gap"] if tight[0] else L["separator_gap"])
        return sum(runs_length(face, lf, x) for x in its) + 2 * dot

    room = math.radians(L["bottom_span"]) * r
    its = items()
    if total(its) > room:
        tight[0] = True
        its = items()
    while total(its) > room:
        open_ = [i for i in range(3) if levels[i] < BARE]
        if not open_:
            break
        levels[max(open_, key=lambda i: runs_length(face, lf, its[i]))] += 1
        its = items()
    runs = []
    gap = px(L["tight_gap"] if tight[0] else L["separator_gap"])
    for i, x in enumerate(its):
        if i:
            runs.append(("·", word_c, 0, gap, 0))
            runs.append((x[0][0], x[0][1], x[0][2], gap, x[0][4]))
            runs += x[1:]
        else:
            runs += x
    legend(face, lf, runs, 180, bottom=True)
    return face.done(path)


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "inscription.png"
    mode = sys.argv[2] if len(sys.argv) > 2 else "day"
    size = int(sys.argv[3]) if len(sys.argv) > 3 else 454
    rest = [a for a in sys.argv[4:] if not a.startswith("date=")]
    dates = [a[5:].split("_") for a in sys.argv[4:] if a.startswith("date=")]
    date = f"{dates[0][0]} · {' '.join(dates[0][1:])}".upper() if dates else "SATURDAY · 31 OCTOBER"
    lit = render(out, mode, size, options(rest, {}), date)
    print(f"{out}: {lit * 100:.1f} % of the screen lit")
