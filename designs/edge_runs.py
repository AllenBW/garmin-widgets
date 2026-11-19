#!/usr/bin/env python3
"""Edge's tubes (design #58): each digit of Antonio Bold as the runs of
tube that light its edges, and the single-stroke lettering of the date.

A digit's body has every corner rounded (the mockup's `soften`), and its
tubes run just inside its edge, the outer one and the counters'. An edge
is lit by the hours' tube where it faces the upper left and by the
minutes' where it faces the lower right; a run stops where its edge turns
away from both lights. The mockup cut the runs from the outline pixel by
pixel and left stubs. Here each contour is traced as a centre line, and
the runs are made whole:

- a dark stretch between two runs of one light, shorter than JOIN, is lit
  (the runs join);
- two runs of different lights never come closer than GAP, end to end
  (each gives way equally);
- a run shorter than SHORT is dropped.

All lengths are in tube widths. The paths are in ems of the font, x from
the digit's pen, y down from the digits' common ink top. Pillow only.

    python3 -I designs/edge_runs.py        # print each digit's runs
"""
import math
from functools import lru_cache
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
FONT = HERE / "fonts" / "Antonio[wght].ttf"
WEIGHT = 700

# In fractions of the screen width, as the mockup (mockups_neon.edge)
EM = 0.43                      # the numerals' em
SOFTEN = 0.016                 # every corner rounded to about this radius
TUBE = 0.0105                  # a lit tube's width
THIN = 0.0058                  # the same tube in standby
TURN = 0.30                    # an edge is lit while it faces a light by more than this (the cosine, 72.5 degrees)

# In tube widths
JOIN = 3.0                     # a dark stretch shorter than this between runs of one light is lit
GAP = 2.6                      # the least between the ends of two runs of different lights, centre to centre
SHORT = 4.5                    # a run is never shorter than this (the brief: about four tube widths)

TRACE = 1200                   # px per em while tracing
STEP = 0.0035                  # the paths' point spacing, ems (about 0.7 px at 454)
UL, LR, DARK = 0, 1, 2


def _font(size):
    f = ImageFont.truetype(str(FONT), size)
    f.set_variation_by_axes([WEIGHT])
    return f


@lru_cache(maxsize=None)
def metrics():
    """The digits' advances, the common ink top and bottom above and below
    the baseline, in ems."""
    f = _font(TRACE)
    pad = TRACE
    img = Image.new("L", (pad * 12, pad * 3), 0)
    ImageDraw.Draw(img).text((pad, 2 * pad), "0123456789", font=f, fill=255, anchor="ls")
    b = img.point(lambda v: 255 if v > 127 else 0).getbbox()
    adv = {c: f.getlength(c) / TRACE for c in "0123456789"}
    return adv, (b[1] - 2 * pad) / TRACE, (b[3] - 2 * pad) / TRACE


def height():
    """The digits' ink height, ems."""
    _, top, bottom = metrics()
    return bottom - top


def _contours(field, level):
    """Marching squares on an L image: closed contours of `level`, as lists
    of (x, y) in pixel-centre coordinates."""
    w, h = field.size
    data = field.tobytes()
    binary = field.point(lambda v: 255 if v > level else 0)
    mixed = ImageChops.difference(binary.filter(ImageFilter.MaxFilter(3)), binary.filter(ImageFilter.MinFilter(3))).tobytes()
    links = {}

    def cross(x0, y0, x1, y1):
        a, b = data[y0 * w + x0], data[y1 * w + x1]
        t = (level - a) / (b - a)
        return (x0 + (x1 - x0) * t, y0 + (y1 - y0) * t)

    points = {}
    for i, v in enumerate(mixed):
        if not v:
            continue
        y, x = divmod(i, w)
        if x >= w - 1 or y >= h - 1:
            continue
        a, b, c, d = (data[i] > level, data[i + 1] > level, data[i + w + 1] > level, data[i + w] > level)
        case = a | (b << 1) | (c << 2) | (d << 3)
        if case in (0, 15):
            continue
        top, right, bottom, left = (x, y, 0), (x + 1, y, 1), (x, y + 1, 0), (x, y, 1)   # (x, y, 0): the edge right of the pixel; 1: below
        if a != b:
            points[top] = cross(x, y, x + 1, y)
        if b != c:
            points[right] = cross(x + 1, y, x + 1, y + 1)
        if d != c:
            points[bottom] = cross(x, y + 1, x + 1, y + 1)
        if a != d:
            points[left] = cross(x, y, x, y + 1)
        pairs = {1: [(left, top)], 2: [(top, right)], 3: [(left, right)], 4: [(right, bottom)],
                 5: [(left, top), (right, bottom)], 6: [(top, bottom)], 7: [(left, bottom)],
                 8: [(left, bottom)], 9: [(top, bottom)], 10: [(top, right), (left, bottom)],
                 11: [(right, bottom)], 12: [(left, right)], 13: [(top, right)], 14: [(left, top)]}[case]
        for p, q in pairs:
            links.setdefault(p, []).append(q)
            links.setdefault(q, []).append(p)
    out = []
    seen = set()
    for start in sorted(links):
        if start in seen:
            continue
        loop, prev, at = [], None, start
        while at not in seen:
            seen.add(at)
            loop.append(points[at])
            nxt = [k for k in links[at] if k != prev]
            prev, at = at, (nxt[0] if nxt else start)
        if len(loop) > 8:
            out.append(loop)
    return out


def _resample(loop, step):
    """A closed polyline at even spacing (about `step`), as a list."""
    n = len(loop)
    seg = [math.dist(loop[i], loop[(i + 1) % n]) for i in range(n)]
    total = sum(seg)
    count = max(8, round(total / step))
    out, i, walked = [], 0, 0.0
    for k in range(count):
        target = total * k / count
        while walked + seg[i] < target:
            walked += seg[i]
            i += 1
        t = (target - walked) / seg[i] if seg[i] else 0.0
        p, q = loop[i], loop[(i + 1) % n]
        out.append((p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t))
    return out, total / count


def _runs(classes, ds, tube):
    """The lit runs of one closed contour: (light, first index, count),
    made whole by the rules at the top. `classes` is each point's light,
    `ds` the spacing, `tube` the tube's width, in the same unit."""
    n = len(classes)
    if all(c == classes[0] for c in classes):
        return [] if classes[0] == DARK else [(classes[0], 0, n)]
    start = next(i for i in range(n) if classes[i] != classes[i - 1])
    spans = []                                    # [light, first, count] round the contour
    for k in range(n):
        i = (start + k) % n
        if spans and spans[-1][0] == classes[i]:
            spans[-1][2] += 1
        else:
            spans.append([classes[i], i, 1])

    def merge():
        k = 0
        while len(spans) > 1 and k < len(spans):
            a, b = spans[k], spans[(k + 1) % len(spans)]
            if a[0] == b[0]:
                a[2] += b[2]
                spans.remove(b)
                k = 0
            else:
                k += 1

    # dark stretches between two runs of one light: join them
    changed = True
    while changed and len(spans) > 2:
        changed = False
        for k, s in enumerate(spans):
            before, after = spans[k - 1], spans[(k + 1) % len(spans)]
            if s[0] == DARK and before[0] == after[0] and s[2] * ds < JOIN * tube:
                s[0] = before[0]
                merge()
                changed = True
                break
    # stubs: a lit run too short to be a tube goes dark
    changed = True
    while changed:
        changed = False
        for s in sorted(spans, key=lambda s: s[2]):
            if s[0] != DARK and s[2] * ds < SHORT * tube and len(spans) > 1:
                s[0] = DARK
                merge()
                changed = True
                break
    # runs of different lights keep their distance: both ends give way
    need = math.ceil(GAP * tube / ds)
    for k, s in enumerate(spans):
        if s[0] != DARK or len(spans) < 3:
            continue
        before, after = spans[k - 1], spans[(k + 1) % len(spans)]
        short = need - s[2]
        if short > 0 and before[0] != DARK and after[0] != DARK:
            a, b = short // 2, short - short // 2
            before[2] -= a
            s[1] = (s[1] - a) % n
            s[2] += short
            after[1] = (after[1] + b) % n
            after[2] -= b
    if len(spans) == 2:                           # one run round the whole contour but a short dark stretch
        dark = next(s for s in spans if s[0] == DARK)
        lit = next(s for s in spans if s[0] != DARK)
        short = need - dark[2]
        if short > 0:
            a = short // 2
            dark[1] = (dark[1] - a) % n
            dark[2] += short
            lit[1] = (lit[1] + short - a) % n
            lit[2] -= short
    return [(s[0], s[1], s[2]) for s in spans if s[0] != DARK and s[2] * ds >= SHORT * tube]


@lru_cache(maxsize=None)
def digit(c):
    """(advance, [(light, [(x, y), ...]), ...]) for one digit, in ems; a
    closed run (a whole contour in one light) repeats its first point."""
    adv, top, _ = metrics()
    f = _font(TRACE)
    pad = int(TRACE * 0.25)
    size = (int(adv[c] * TRACE) + 2 * pad, int(height() * TRACE) + 2 * pad)
    body = Image.new("L", size, 0)
    ImageDraw.Draw(body).text((pad, pad - top * TRACE), c, font=f, fill=255, anchor="ls")
    if c == "4":
        # the crossbar's stub past the stem softens into a wobble no tube
        # would be bent to: the bar stops at the stem
        hgt = int(height() * TRACE)
        stem = body.crop((0, pad + hgt // 10, size[0], pad + hgt // 3)).getbbox()[2]
        ImageDraw.Draw(body).rectangle((stem, 0, size[0], size[1]), fill=0)
    k = TRACE / EM                                              # px per screen width
    body = body.filter(ImageFilter.GaussianBlur(SOFTEN * k)).point(lambda v: 255 if v > 127 else 0)
    # the centre line: half a tube inside the edge. Blurring the body by s
    # puts the level Phi(d / s) on the line d inside a straight edge.
    s = TUBE * k * 0.5
    d = TUBE * k * 0.5
    level = int(255 * 0.5 * (1 + math.erf(d / s / math.sqrt(2)))) + 0.5
    field = body.filter(ImageFilter.GaussianBlur(s))
    data, w = field.tobytes(), size[0]
    tube = TUBE / EM                                            # ems
    runs = []
    for loop in _contours(field, level):
        pts, ds = _resample(loop, STEP * TRACE)
        n = len(pts)
        span = max(2, round(tube * TRACE * 0.75 / ds))          # the tangent over about a tube's width
        classes = []
        for i in range(n):
            (x0, y0), (x1, y1) = pts[i - span], pts[(i + span) % n]
            tx, ty = x1 - x0, y1 - y0
            ln = math.hypot(tx, ty) or 1.0
            nx, ny = ty / ln, -tx / ln                          # one of the two normals
            px, py = pts[i]
            probe = data[int(py + ny * d * 0.8 + 0.5) * w + int(px + nx * d * 0.8 + 0.5)]
            if probe > level:                                   # it points into the body: turn it outward
                nx, ny = -nx, -ny
            facing = -(nx + ny) / math.sqrt(2)                  # +1 faces the upper left
            classes.append(UL if facing > TURN else (LR if facing < -TURN else DARK))
        for light, first, count in _runs(classes, ds / TRACE, tube):
            closed = count >= n
            path = [((pts[(first + j) % n][0] - pad) / TRACE, (pts[(first + j) % n][1] - pad) / TRACE)
                    for j in range(count + (1 if closed else 0))]
            runs.append((light, path))
    return adv[c], runs


# ---------------------------------------------------------------- lettering
# Single-stroke letters as a sign maker bends them (the mockup's TUBES,
# extended to A to Z, the digits and a hyphen), in a box one unit tall:
# (advance, [paths]).

def arc(cx, cy, rx, ry, a0, a1, n=24):
    """Points on an ellipse; degrees on the screen (0 right, 90 down)."""
    return [(cx + rx * math.cos(math.radians(a0 + (a1 - a0) * i / n)),
             cy + ry * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]


def _letters():
    r = 0.25
    L = {
        "0": (0.50, [arc(r, 0.27, r, 0.27, 180, 360) + arc(r, 0.73, r, 0.27, 0, 180) + [(0.0, 0.27)]]),
        "1": (0.30, [[(0.02, 0.22), (0.24, 0.0), (0.24, 1.0)]]),
        "2": (0.50, [arc(r, 0.26, r, 0.26, 180, 360) + arc(0.20, 0.26, 0.30, 0.34, 0, 60, 8) + [(0.0, 1.0), (0.50, 1.0)]]),
        "3": (0.50, [arc(0.24, 0.25, 0.24, 0.25, -160, 90) + arc(0.24, 0.74, 0.26, 0.26, -90, 160)]),
        "4": (0.52, [[(0.38, 1.0), (0.38, 0.0), (0.0, 0.70), (0.52, 0.70)]]),
        "5": (0.50, [[(0.46, 0.0), (0.06, 0.0), (0.04, 0.46)] + arc(0.23, 0.70, 0.27, 0.30, -125, 150)]),
        "6": (0.50, [arc(0.34, 0.30, 0.34, 0.30, -60, -180, 16)[1:] and
                     ([(0.44, 0.04)] + arc(r, 0.30, r, 0.30, -105, -180, 8) + [(0.0, 0.72)]
                      + arc(r, 0.72, r, 0.28, 180, -180, 32))]),
        "7": (0.50, [[(0.0, 0.0), (0.50, 0.0), (0.18, 1.0)]]),
        "8": (0.50, [arc(r, 0.25, 0.23, 0.25, 90, 450, 32) + arc(r, 0.75, r, 0.25, -90, 270, 32)]),
        "9": (0.50, [arc(r, 0.28, r, 0.28, 0, 360, 32) + [(0.50, 0.70)] + arc(r, 0.70, r, 0.30, 0, 75, 8) + [(0.06, 0.96)]]),
        "A": (0.54, [[(0.0, 1.0), (0.27, 0.0), (0.54, 1.0)], [(0.10, 0.66), (0.44, 0.66)]]),
        "B": (0.48, [[(0.0, 0.48), (0.0, 0.0), (0.24, 0.0)] + arc(0.24, 0.24, 0.22, 0.24, -90, 90, 12) + [(0.0, 0.48), (0.0, 1.0), (0.24, 1.0)]
                     + arc(0.24, 0.74, 0.24, 0.26, 90, -90, 12)]),
        "C": (0.50, [arc(r, 0.27, r, 0.27, -20, -180, 16) + arc(r, 0.73, r, 0.27, 180, 20, 16)]),
        "D": (0.50, [[(0.0, 0.0), (0.0, 1.0), (0.22, 1.0)] + arc(0.22, 0.72, 0.28, 0.28, 90, 0, 8) + arc(0.22, 0.28, 0.28, 0.28, 0, -90, 8) + [(0.0, 0.0)]]),
        "E": (0.44, [[(0.44, 0.0), (0.0, 0.0), (0.0, 1.0), (0.44, 1.0)], [(0.0, 0.5), (0.36, 0.5)]]),
        "F": (0.42, [[(0.42, 0.0), (0.0, 0.0), (0.0, 1.0)], [(0.0, 0.5), (0.34, 0.5)]]),
        "G": (0.52, [arc(r, 0.27, r, 0.27, -20, -180, 16) + arc(r, 0.73, r, 0.27, 180, 0, 16) + [(0.50, 0.54), (0.28, 0.54)]]),
        "H": (0.50, [[(0.0, 0.0), (0.0, 1.0)], [(0.50, 0.0), (0.50, 1.0)], [(0.0, 0.5), (0.50, 0.5)]]),
        "I": (0.12, [[(0.06, 0.0), (0.06, 1.0)]]),
        "J": (0.42, [[(0.42, 0.0), (0.42, 0.76)] + arc(0.21, 0.76, 0.21, 0.24, 0, 160, 12)]),
        "K": (0.48, [[(0.0, 0.0), (0.0, 1.0)], [(0.46, 0.0), (0.0, 0.60)], [(0.16, 0.46), (0.48, 1.0)]]),
        "L": (0.42, [[(0.0, 0.0), (0.0, 1.0), (0.42, 1.0)]]),
        "M": (0.62, [[(0.0, 1.0), (0.0, 0.0), (0.31, 0.62), (0.62, 0.0), (0.62, 1.0)]]),
        "N": (0.52, [[(0.0, 1.0), (0.0, 0.0), (0.52, 1.0), (0.52, 0.0)]]),
        "O": (0.52, [arc(0.26, 0.27, 0.26, 0.27, 180, 360) + arc(0.26, 0.73, 0.26, 0.27, 0, 180) + [(0.0, 0.27)]]),
        "P": (0.48, [[(0.0, 1.0), (0.0, 0.0), (0.22, 0.0)] + arc(0.22, 0.27, 0.26, 0.27, -90, 90, 12) + [(0.0, 0.54)]]),
        "Q": (0.52, [arc(0.26, 0.27, 0.26, 0.27, 180, 360) + arc(0.26, 0.73, 0.26, 0.27, 0, 180) + [(0.0, 0.27)],
                     [(0.30, 0.76), (0.54, 1.04)]]),
        "R": (0.50, [[(0.0, 1.0), (0.0, 0.0), (0.22, 0.0)] + arc(0.22, 0.26, 0.26, 0.26, -90, 90, 12) + [(0.0, 0.52)],
                     [(0.22, 0.52), (0.50, 1.0)]]),
        "S": (0.48, [arc(0.24, 0.25, 0.23, 0.25, -25, -180, 14) + arc(0.24, 0.25, 0.23, 0.25, 180, 90, 8)[1:]
                     + arc(0.24, 0.75, 0.24, 0.25, -90, 0, 8)[1:] + arc(0.24, 0.75, 0.24, 0.25, 0, 155, 14)[1:]]),
        "T": (0.50, [[(0.0, 0.0), (0.50, 0.0)], [(0.25, 0.0), (0.25, 1.0)]]),
        "U": (0.50, [[(0.0, 0.0), (0.0, 0.74)] + arc(r, 0.74, r, 0.26, 180, 0, 16) + [(0.50, 0.0)]]),
        "V": (0.52, [[(0.0, 0.0), (0.26, 1.0), (0.52, 0.0)]]),
        "W": (0.70, [[(0.0, 0.0), (0.16, 1.0), (0.35, 0.30), (0.54, 1.0), (0.70, 0.0)]]),
        "X": (0.50, [[(0.0, 0.0), (0.50, 1.0)], [(0.50, 0.0), (0.0, 1.0)]]),
        "Y": (0.52, [[(0.0, 0.0), (0.26, 0.54), (0.52, 0.0)], [(0.26, 0.54), (0.26, 1.0)]]),
        "Z": (0.48, [[(0.0, 0.0), (0.48, 0.0), (0.0, 1.0), (0.48, 1.0)]]),
        "-": (0.30, [[(0.0, 0.52), (0.30, 0.52)]]),
        " ": (0.30, []),
    }
    return L


LETTERS = _letters()
LETTER_GAP = 0.30              # between letters, in letter heights (the mockup's)


def text_width(s):
    """The width of `s` in letter heights."""
    return sum(LETTERS[c][0] for c in s) + LETTER_GAP * (len(s) - 1)


if __name__ == "__main__":
    adv, top, bottom = metrics()
    print(f"ink height {height():.4f} em, top {top:.4f}, bottom {bottom:.4f}")
    for c in "0123456789":
        a, runs = digit(c)
        t = TUBE / EM
        lens = [(("UL", "LR")[light], round(sum(math.dist(p[i], p[i + 1]) for i in range(len(p) - 1)) / t, 1)) for light, p in runs]
        print(c, f"advance {a:.3f}", lens)
