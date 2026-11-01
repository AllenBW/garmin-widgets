#!/usr/bin/env python3
"""Render the Vessel face (design #16) with sample readings: what
VesselView draws, from the same layout fractions.

    python3 -I designs/preview_vessel.py out.png [day|night|aod|bedside] [454|416] [style=0-2 accent=0-7|0xRRGGBB data=0-4 slots=a,b,c hours=14 minutes=38 alarm=0/1]

Slots name a reading kind each (preview_faces.KINDS): the hours' glass,
the minutes' glass, the foot. Prints the share of the round screen lit
(always-on must stay under 10 %). Approximate to a pixel or two: check the
real face with scripts/sim.sh.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))   # run with -I
from preview_faces import (BEDSIDE, DATA, QUIET, SS, Face, LABELS, accent_color, band, bell, digit_font, draw_icon,
                           font, glyph_mask, options, outline_of, paint, place, reading, rgb, scale, spaced, word)

L = dict(
    digits=0.285, aod_digits=0.270,   # each row's digit height
    row_gap=0.040,                    # between the hours' and the minutes' ink
    ink_right=0.639,                  # the time's ink right edge
    mid=0.485,                        # the stack's centre, a touch over the screen's
    axis=0.430,                       # the date's and the foot's centre: the glasses' axis
    mark_gap=0.026, mark_w=0.018, mark_h=0.022,   # the waterline mark: a triangle pointing at the glass
    value_x=0.036,                    # from the mark's tip to the reading
    value_em=0.062, aod_value_em=0.054,
    icon=0.032,
    full=0.96,                        # a glass this full is full
    date_y=0.112, date_em=0.040, track=0.007,
    foot_y=0.870,
    bell_gap=0.042,                   # from the date's end to the alarm bell's centre
    night=0.85,                       # the colours after sunset
)
STYLES = ["BionicBold", "RobotoCondensedBold", "BionicMedium"]   # Bionic, Condensed, Rajdhani
DEFAULTS = dict(style=0, accent=0, data=0, slots=("body", "steps", "sun"), alarm=1)
SAMPLES = {"day": dict(hours="14", minutes="38", date="SATURDAY 31", night=False),
           "night": dict(hours="21", minutes="05", date="SATURDAY 31", night=True)}


def render(path, mode="day", size=454, st=None):
    st = dict(DEFAULTS, **(st or {}))
    sm = dict(SAMPLES["night" if mode in ("night", "bedside") else "day"])
    for k in ("hours", "minutes"):
        if k in st:
            sm[k] = str(st[k]) if k == "hours" else f"{st[k]:02d}"
    night = sm["night"]
    thin = mode in ("aod", "bedside")
    face = Face(size)
    dim = L["night"] if night else 1.0
    data = scale(DATA[st["data"]][1], dim)
    accent = scale(accent_color(st), dim)
    if mode == "bedside":
        data = accent = BEDSIDE
    dh = face.px(L["aod_digits"] if thin else L["digits"])
    f = digit_font(face, STYLES[st["style"]], dh)
    gap = face.px(L["row_gap"])
    cy = face.px(L["mid"])
    quiet = scale(data, QUIET)
    right = face.px(L["ink_right"])
    line = (3 if size >= 440 and st["style"] != 2 else 2) * SS
    for row, (text, color) in enumerate(((sm["hours"], data), (sm["minutes"], accent))):
        mid = cy - dh / 2 - gap / 2 if row == 0 else cy + dh / 2 + gap / 2
        x, base, box = place(face, f, text, right, mid)
        m = glyph_mask(face, f, text, x, base)
        if mode == "bedside":
            paint(face, outline_of(m, SS * 1.5), BEDSIDE)
            continue
        kind = st["slots"][row]
        value, unit, frac = reading(kind, night)
        gauge = frac is not None            # a reading with no range fills its glass, unmarked
        level = box[3] - (box[3] - box[1]) * (1.0 if frac is None or frac >= L["full"] else frac)
        if thin:
            paint(face, outline_of(m, SS * 1.5), scale(color, 0.8))
            paint(face, band(m, level - SS, level + 2 * SS), scale(color, 0.8))     # the waterline
        else:
            paint(face, outline_of(m, line), color)
            paint(face, band(m, level, face.img.size[1]), color)
        # the reading on its waterline, kept inside its glass's band; with no range, at its middle
        room = face.px(0.024)
        at = min(max(level if gauge else mid, box[1] + room), box[3] - room)
        c = scale(color, 0.55) if thin else color
        tx = right + face.px(L["mark_gap"])
        if gauge:
            mw, mh = face.px(L["mark_w"]), face.px(L["mark_h"])
            face.d.polygon([(tx, at), (tx + mw, at - mh / 2), (tx + mw, at + mh / 2)], fill=rgb(scale(c, 0.7)))
        vf = font("RobotoCondensedBold", L["aod_value_em"] if thin else L["value_em"], size)
        uf = font("RobotoCondensedBold", L["value_em"] * 0.62, size)
        b = face.d.textbbox((0, 0), "0", font=vf, anchor="ls")
        vx = tx + face.px(L["value_x"])
        vbase = at - (b[1] + b[3]) / 2
        face.text(vx, vbase, vf, value, c, "ls")
        end = vx + face.width(vf, value)
        if unit:
            face.text(end + SS, vbase, uf, unit, c, "ls")
            end += face.width(uf, unit) + SS
        s = face.px(L["icon"]) * (0.85 if thin else 1.0)
        ic = scale(quiet, 0.7) if thin else quiet
        if kind in LABELS:
            face.text(end + face.px(0.012), at, uf, LABELS[kind], ic, "lm")
        else:
            draw_icon(face, kind, end + face.px(0.012) + s / 2, at, s, ic, night, True)
    ax = face.px(L["axis"])
    if mode == "bedside":
        if st["alarm"]:
            bell(face, ax, face.px(L["date_y"]), face.px(0.036), BEDSIDE)
        return face.done(path)
    # the date and the foot in the data colour, quiet: the accent is the minutes'
    df = font("RobotoCondensedRegular", L["date_em"], size)
    date_c = scale(data, 0.45 if thin else 0.62)
    w = spaced(face, ax, face.px(L["date_y"]), df, sm["date"], date_c, face.px(L["track"]))
    if st["alarm"]:
        bell(face, ax + w / 2 + face.px(L["bell_gap"]), face.px(L["date_y"]), face.px(0.030), date_c)
    if not thin:
        kind = st["slots"][2]
        value, unit, _ = reading(kind, night)
        text = value + unit
        wd = LABELS.get(kind) or word(kind, night)
        if kind in ("sun", "app", "vo2"):
            text = (wd + " " + text) if wd else text
        elif wd:
            text = text + " " + wd
        spaced(face, ax, face.px(L["foot_y"]), df, text, quiet, face.px(L["track"]))
    return face.done(path)


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "vessel.png"
    mode = sys.argv[2] if len(sys.argv) > 2 else "day"
    size = int(sys.argv[3]) if len(sys.argv) > 3 else 454
    lit = render(out, mode, size, options(sys.argv[4:], {}))
    print(f"{out}: {lit * 100:.1f} % of the screen lit")
