#!/usr/bin/env python3
"""Render the Overlap face (design #18) with sample readings: what
OverlapView draws, from the same layout fractions.

    python3 -I designs/preview_overlap.py out.png [day|night|aod|bedside] [454|416] [style=0-2 accent=0-7|0xRRGGBB data=0-4 slots=a,b hours=14 minutes=38 alarm=0/1]

Slots name a reading kind each (preview_faces.KINDS): the first and the
second reading. The hours always show two digits (hours=9 draws "09").
`preview_overlap.py --check` checks every hour in every typeface at both
sizes, at every window edge the minutes give, for a sliver or loose piece at the knock-out's edges (RAISE) or a
fleck cut off by the bezel.
Prints the share of the round screen lit (always-on must stay under
10 %). Approximate to a pixel or two: check the real face with
scripts/sim.sh.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))   # run with -I
from preview_faces import (BEDSIDE, DATA, QUIET, SS, Face, LABELS, accent_color, bell, digit_font, draw_icon,  # noqa: E402
                           font, glyph_mask, options, outline_of, paint, place, reading, rgb, scale, spaced)

L = dict(
    hours_digits=0.70, hours_x=0.47, hours_y=0.40,          # the hours' digit height and ink centre
    minutes_digits=0.26, minutes_right=0.857, minutes_y=0.700,
    gap=0.016,                        # the hours knocked out this far above and left of the minutes' ink
    window=0.458,                     # the knock-out's left edge at most, so no hour leaves a sliver at it
    stub=0.030,                       # a piece of hour narrower than this is a sliver (--check)
    loose=0.050,                      # and a piece cut loose from its digit thinner than this, a fleck
    hours_data=0.30, hours_accent=0.12,                     # the hours: data × 0.30 + accent × 0.12
    aod_hours=0.45, aod_minutes=0.85,
    left=0.215,                       # the date's and the readings' left edge
    date_y=0.790, date_em=0.046, track=0.008,
    bell_x=0.185, bell=0.030,         # the alarm bell, left of the date
    reading_y=0.855, reading_em=0.040, small_em=0.036, reading_dim=0.70,
    reading_right=0.455,              # the readings never run past this,
    reading_clear=0.020,              # nor closer than this to the minutes' ink
    icon=0.030, icon_gap=0.012, reading_gap=0.032,
    night=0.85,                       # the colours after sunset (not the hours)
)
STYLES = ["BionicBold", "RobotoCondensedBold", "BionicMedium"]   # Bionic, Condensed, Rajdhani
# How much higher the knock-out's top sits (thousandths of the width) for
# the hours' second digit, 0 to 9, per typeface: a 3's or 5's lower stroke
# would otherwise be cut into a loose dash, and a 0 into an arch that reads
# "n". From `--check`; OverlapView.RAISE.
RAISE = [[20, 0, 0, 37, 0, 30, 0, 0, 0, 0], [20, 0, 0, 4, 0, 6, 0, 0, 0, 0], [20, 0, 0, 25, 0, 18, 0, 0, 0, 0]]
# The top-left corner (x, y in thousandths of the width) kept clear of the
# hours for their first digit, 0 to 2, per typeface: Bionic's 2 leaves its
# top terminal cut loose by the bezel. From `--check`; OverlapView.CORNER.
CORNER = [[(0, 0), (0, 0), (92, 295)], [(0, 0), (0, 0), (0, 0)], [(0, 0), (0, 0), (0, 0)]]
DEFAULTS = dict(style=0, accent=0, data=0, slots=("heart", "steps"), alarm=0)
SAMPLES = {"day": dict(hours="14", minutes="38", date="SAT 31", night=False),
           "night": dict(hours="21", minutes="05", date="SAT 31", night=True)}


def mix(a, fa, b, fb):
    """a × fa + b × fb, channel by channel (OverlapView.mix)."""
    return sum(min(255, int(((a >> s) & 255) * fa + ((b >> s) & 255) * fb)) << s for s in (16, 8, 0))


def knockout(face, m, clip_x, clip_y, corner=(0, 0)):
    """The part of the hours' mask above clip_y or left of clip_x, less
    the top-left corner: the clip regions OverlapView draws the hours
    through."""
    keep = Image.new("L", m.size, 0)
    d = ImageDraw.Draw(keep)
    d.rectangle((0, 0, m.size[0], clip_y), fill=255)
    d.rectangle((0, clip_y, clip_x, m.size[1]), fill=255)
    if corner[0]:
        d.rectangle((0, 0, corner[0], corner[1]), fill=0)
    return Image.composite(m, keep.point(lambda v: 0), keep)


def render(path, mode="day", size=454, st=None):
    st = dict(DEFAULTS, **(st or {}))
    sm = dict(SAMPLES["night" if mode in ("night", "bedside") else "day"])
    if "hours" in st:
        sm["hours"] = f"{st['hours']:02d}"
    if "minutes" in st:
        sm["minutes"] = f"{st['minutes']:02d}"
    night = sm["night"]
    thin = mode in ("aod", "bedside")
    face = Face(size)
    dim = L["night"] if night else 1.0
    accent = accent_color(st)
    data = DATA[st["data"]][1]
    hours_c = mix(data, L["aod_hours"] if thin else L["hours_data"], accent, L["hours_accent"])
    minutes_c = scale(accent, (L["aod_minutes"] if thin else 1.0) * dim)
    if mode == "bedside":
        hours_c, minutes_c = scale(BEDSIDE, 0.85), BEDSIDE
    name = STYLES[st["style"]]

    # The minutes' ink, then the hours knocked out round it
    mf = digit_font(face, name, face.px(L["minutes_digits"]))
    mx, mbase, mbox = place(face, mf, sm["minutes"], face.px(L["minutes_right"]), face.px(L["minutes_y"]), "r")
    hf = digit_font(face, name, face.px(L["hours_digits"]))
    x, base, _ = place(face, hf, sm["hours"], face.px(L["hours_x"]), face.px(L["hours_y"]), "m")
    hm = glyph_mask(face, hf, sm["hours"], x, base)
    edge = min(mbox[0] - face.px(L["gap"]), face.px(L["window"]))
    top = mbox[1] - face.px(L["gap"]) - face.px(RAISE[st["style"]][int(sm["hours"][1])] / 1000)
    cx, cy = CORNER[st["style"]][int(sm["hours"][0])]
    hm = knockout(face, outline_of(hm, SS * 1.5) if thin else hm, edge, top, (face.px(cx / 1000), face.px(cy / 1000)))
    paint(face, hm, hours_c)
    mm = glyph_mask(face, mf, sm["minutes"], mx, mbase)
    paint(face, outline_of(mm, SS * 1.5) if thin else mm, minutes_c)

    # The date, the alarm bell left of it
    left = face.px(L["left"])
    if mode != "bedside":
        date_c = scale(accent, (0.6 if thin else 1.0) * dim)
        spaced(face, left, face.px(L["date_y"]), font("RobotoCondensedBold", L["date_em"], size), sm["date"], date_c,
               face.px(L["track"]), "l")
    if st["alarm"] and mode == "bedside":     # no date: the bell just outside the minutes' top-left corner
        b = face.px(L["bell"])
        bell(face, mbox[0] - b * 0.75, mbox[1] - b * 0.75, b, BEDSIDE)
    elif st["alarm"]:
        bell(face, face.px(L["bell_x"]), face.px(L["date_y"]), face.px(L["bell"]),
             scale(scale(accent, (0.6 if thin else 1.0) * dim), 0.7))
    if thin:
        return face.done(path)

    # The readings, never past reading_right: without units if they don't
    # fit, then the first alone, then in a smaller font. Never without
    # their icons (or another app's label): they are the only cue.
    s = face.px(L["icon"])
    gap = face.px(L["icon_gap"])
    room = min(face.px(L["reading_right"]), mbox[0] - face.px(L["reading_clear"])) - face.px(L["left"])
    def label_font(kind, em):
        return font("RobotoCondensedBold", em * (0.75 if len(LABELS[kind]) <= 3 else 0.62), size)

    for kinds, units, em in ((st["slots"][:2], True, L["reading_em"]), (st["slots"][:2], False, L["reading_em"]),
                             (st["slots"][:1], False, L["reading_em"]), (st["slots"][:1], False, L["small_em"])):
        tf = font("RobotoCondensedBold", em, size)
        uf = font("RobotoCondensedBold", L["reading_em"] * 0.62, size)

        def width(kind):
            value, unit, _ = reading(kind, night)
            w = face.width(tf, value) + (face.width(uf, unit) + SS if units and unit else 0)
            return w + (face.width(label_font(kind, em), LABELS[kind]) if kind in LABELS else s) + gap

        if sum(width(k) for k in kinds) + face.px(L["reading_gap"]) * (len(kinds) - 1) <= room:
            break
    x = face.px(L["left"])
    y = face.px(L["reading_y"])
    quiet = scale(data, QUIET * dim)
    for kind in kinds:
        value, unit, _ = reading(kind, night)
        if kind in LABELS:
            lf = label_font(kind, em)
            face.text(x, y, lf, LABELS[kind], quiet, "lm")
            vx = x + face.width(lf, LABELS[kind]) + gap
        else:
            draw_icon(face, kind, x + s / 2, y, s, quiet, night, True)
            vx = x + s + gap
        b = face.d.textbbox((0, 0), "0", font=tf, anchor="ls")
        vbase = y - (b[1] + b[3]) / 2
        vc = scale(data, L["reading_dim"] * dim)
        face.text(vx, vbase, tf, value, vc, "ls")
        end = vx + face.width(tf, value)
        if units and unit:
            face.text(end + SS, vbase, uf, unit, vc, "ls")
            end += face.width(uf, unit) + SS
        x = end + face.px(L["reading_gap"])
    return face.done(path)


def pieces(px, w, h):
    """Connected pieces of a 1x binary image: (x0, y0, x1, y1) boxes."""
    seen = bytearray(w * h)
    out = []
    for start in range(w * h):
        if not px[start] or seen[start]:
            continue
        seen[start] = 1
        stack = [start]
        x0 = y0 = 10 ** 6
        x1 = y1 = -1
        while stack:
            i = stack.pop()
            x, y = i % w, i // w
            x0, y0, x1, y1 = min(x0, x), min(y0, y), max(x1, x), max(y1, y)
            for j in (i - 1, i + 1, i - w, i + w):
                if 0 <= j < w * h and px[j] and not seen[j] and abs(j % w - x) <= 1:
                    seen[j] = 1
                    stack.append(j)
        out.append((x0, y0, x1, y1))
    return out


def hours_mask(style, hours, size=454):
    """The hours' ink at 1x as a flat 0/1 list, and the minutes' ink top (px)."""
    face = Face(size)
    name = STYLES[style]
    hf = digit_font(face, name, face.px(L["hours_digits"]))
    x, base, _ = place(face, hf, hours, face.px(L["hours_x"]), face.px(L["hours_y"]), "m")
    m = glyph_mask(face, hf, hours, x, base).resize((size, size), Image.LANCZOS)
    mf = digit_font(face, name, face.px(L["minutes_digits"]))
    _, _, mbox = place(face, mf, "00", face.px(L["minutes_right"]), face.px(L["minutes_y"]), "r")
    return [1 if v > 127 else 0 for v in m.get_flattened_data()], (mbox[1] - face.px(L["gap"])) / SS


def edges(style, size=454):
    """Every left edge the knock-out takes over the sixty minutes (px):
    min(the minutes' ink left - gap, window)."""
    face = Face(size)
    mf = digit_font(face, STYLES[style], face.px(L["minutes_digits"]))
    out = set()
    for m in range(60):
        _, _, b = place(face, mf, f"{m:02d}", face.px(L["minutes_right"]), face.px(L["minutes_y"]), "r")
        out.add(int(min(b[0] - face.px(L["gap"]), face.px(L["window"])) / SS))
    return sorted(out)


def window_for(style, hours, size=454, raise_by=0.0, edge=None):
    """The knock-out's left edge and top (px) that leave nothing stray: no
    sliver narrower than `stub` hanging below the window's top at its left
    edge, and no thin piece (under `loose` across) cut loose from its digit
    by the window's top or left edge. Returns (edge, top, how far the top
    had to rise, as a fraction of the width)."""
    px, clip_y = hours_mask(style, hours, size)
    clip_y -= raise_by * size
    start = clip_y
    edge = int(L["window"] * size) if edge is None else edge
    first = edge
    stub = L["stub"] * size
    loose = L["loose"] * size
    for _ in range(12):
        below = [px[i] if (i // size >= clip_y and i % size < edge) else 0 for i in range(size * size)]
        left = [b for b in pieces(below, size, size) if b[2] >= edge - 2 and b[2] - b[0] + 1 < stub]
        shown = [px[i] if (i // size < clip_y or i % size < edge) else 0 for i in range(size * size)]
        cut = pieces(shown, size, size)
        left += [b for b in cut if b[2] >= edge - 2 and b[3] >= clip_y and b[2] - b[0] + 1 < loose]
        top = [b for b in cut if b[3] >= clip_y - 2 and b[2] >= edge and b[3] - b[1] + 1 < loose]
        if not left and not top:
            break
        if left:
            edge = min(b[0] for b in left) - 1
        if top:
            clip_y = min(b[1] for b in top) - 1
    return edge, clip_y, round((start - clip_y) / size + raise_by, 3), first


def flecks(style, hours, edge, size=454, top=None, corner=(0, 0)):
    """Pieces of hour cut off at the bezel thinner than `loose`, given the
    window's left edge and top (px) and the corner kept clear (CORNER)."""
    px, clip_y = hours_mask(style, hours, size)
    clip_y = clip_y if top is None else top
    r = size / 2
    vis = [0] * (size * size)
    for i, v in enumerate(px):
        x, y = i % size, i // size
        if (v and (x - r + 0.5) ** 2 + (y - r + 0.5) ** 2 < r * r and (y < clip_y or x < edge)
                and not (x < corner[0] / 1000 * size and y < corner[1] / 1000 * size)):
            vis[i] = 1
    out = []
    for b in pieces(vis, size, size):
        cx, cy = (b[0] + b[2]) / 2, (b[1] + b[3]) / 2
        near = max(((x - r) ** 2 + (y - r) ** 2) ** 0.5 for x in (b[0], b[2]) for y in (b[1], b[3])) > r - 3
        dims = (b[2] - b[0] + 1, b[3] - b[1] + 1)
        if near and max(dims) > 2 and min(dims) < L["loose"] * size:     # a lone pixel is the disc's own edge
            out.append(b)
    return out


def contrast(c):
    """WCAG contrast of a colour against black."""
    lin = [(v / 255 / 12.92) if v / 255 <= 0.03928 else ((v / 255 + 0.055) / 1.055) ** 2.4 for v in rgb(c)]
    return (0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2] + 0.05) / 0.05


if __name__ == "__main__" and sys.argv[1:2] == ["--check"]:
    # Every hour in every typeface at both sizes: a sliver at the window's
    # edge, or a fleck the bezel cuts off, is a problem
    problems = 0
    for size in (454, 416):
        for s in range(3):
            for e in edges(s, size):
                for h in range(24):
                    edge, top, rose, first = window_for(s, f"{h:02d}", size, RAISE[s][h % 10] / 1000, e)
                    bits = flecks(s, f"{h:02d}", edge, size, top, CORNER[s][h // 10])
                    if edge != first or rose > RAISE[s][h % 10] / 1000 + 0.0015 or bits:
                        print(size, STYLES[s], "edge", e, f"{h:02d}", "moved to", edge, "rose", rose, "flecks", bits)
                        problems += 1
    print(problems, "problems")
    sys.exit()

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "overlap.png"
    mode = sys.argv[2] if len(sys.argv) > 2 else "day"
    size = int(sys.argv[3]) if len(sys.argv) > 3 else 454
    lit = render(out, mode, size, options(sys.argv[4:], {}))
    print(f"{out}: {lit * 100:.1f} % of the screen lit")
