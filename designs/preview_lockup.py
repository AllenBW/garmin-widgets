#!/usr/bin/env python3
"""Render the Lockup face (design #20) with sample readings: what LockupView
draws, from the same rows and the same digits (gen_lockup.glyph).

    python3 -I designs/preview_lockup.py out.png [day|night|widest|empty] [standby] [look=yours|orange|blue|green|low|gold|ember|orchard|dusk]
    python3 -I designs/preview_lockup.py --check

FACE_W=416 for the 43 mm. Prints the share of the round screen lit. Standby
is drawn as on the watch: lines a pixel wide with no anti-aliasing. --check
measures it over the digits that light the most (it must stay under 10 %).
"""
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))   # run with -I
from gen_lockup import SLANTS, glyph  # noqa: E402
from preview_numbers import LOOKS, SAMPLES, W, rgb  # noqa: E402

M, GAP, ITEM, RG = 0.012, 0.010, 0.024, 0.013
SIDE = 5
BLACK, REGULAR = "BLACK", "REGULAR"
SS = 4


def half(y):
    d = (0.5 - M) ** 2 - (y - 0.5) ** 2
    return math.sqrt(d) if d > 0 else 0.0


class Row:
    def __init__(self, text, weight, color, alpha, lx, rx, y0, y1, bend=0.30, least=1.0):
        self.text, self.weight, self.color, self.alpha = text, weight, color, alpha
        self.lx, self.rx, self.y0, self.y1, self.bend, self.least = lx, rx, y0, y1, bend, least
        ym = (y0 + y1) / 2
        self.xlm = 0.5 - half(ym) if lx is None else lx
        self.xrm = 0.5 + half(ym) if rx is None else rx

    def pulls(self, uu):
        fl = max(0.0, 1 - uu / self.bend) if self.lx is None else 0.0
        fr = max(0.0, 1 - (1 - uu) / self.bend) if self.rx is None else 0.0
        return fl ** 1.5, fr ** 1.5

    def point(self, uu, y):
        c = min(self.y1, max(self.y0, y))
        h = half(c)
        fl, fr = self.pulls(uu)
        return self.xlm + uu * (self.xrm - self.xlm) + (0.5 - h - self.xlm) * fl + (0.5 + h - self.xrm) * fr, y

    def glyphs(self):
        """(character, u of its left, u per block width)"""
        wm = self.xrm - self.xlm
        cw = sum(glyph(c, self.weight)[0] for c in self.text)
        room = 1 - GAP * (len(self.text) - 1) / wm
        units = max(cw, self.least)
        k = room / units
        u = (units - cw) * k / 2
        for c in self.text:
            yield c, u, k
            u += glyph(c, self.weight)[0] * k + GAP / wm

    def yat(self, v):
        return self.y0 + v * (self.y1 - self.y0)

    def corners(self, u0, v0, u1, v1, base, k):
        pts = []
        for n in range(SIDE):
            pts.append(self.point(base + u0 * k, self.yat(v0 + (v1 - v0) * n / (SIDE - 1))))
        for n in reversed(range(SIDE)):
            pts.append(self.point(base + u1 * k, self.yat(v0 + (v1 - v0) * n / (SIDE - 1))))
        return pts


def face(d, lk, aod):
    """the rows, as LockupView.build makes them"""
    D, Su, Wx, Bo, s, t = lk["data"], lk["sun"], lk["wx"], lk["body"], lk["s"], lk["t"]
    if aod:
        return [Row(d["date"], REGULAR, D, .8, None, None, .052, .128, .60, 3.0),
                Row(d["sun"], BLACK, Su, .9, None, None, .160, .288, least=3.6),
                Row(d["time"], BLACK, D, 1, None, None, .300, .575, least=3.6),
                Row(d["temp"], BLACK, Wx, .9, .30, .70, .747, .945, least=1.8)]
    h = half(.214)
    sun = .5 - h + 2 * h * .60
    h = half(.661)
    body = .5 - h + 2 * h * .46
    room = .148 - RG
    hb = room / 2
    return [Row(d["date"], BLACK, D, 1 if s == 1 else .85, None, None, .052, .128, .60, 3.0),
            Row(d["sun"], BLACK, Su, 1, None, sun, .140, .288, least=3.6),
            Row(d["count"], REGULAR, Su, 1, sun + ITEM, None, .140, .140 + room * .62, least=3.0),
            Row(d.get("charge", "87%"), REGULAR, D, t, sun + ITEM, None, .140 + room * .62 + RG, .288, least=2.6),
            Row(d["time"], BLACK, D, 1, None, None, .300, .575, least=3.6),
            Row(d["hr"], BLACK, Bo, 1, None, body, .587, .735, least=1.6),
            Row(d["steps"], REGULAR, Bo, s, body + ITEM, None, .587, .587 + hb, least=2.6),
            Row(d["bat"], REGULAR, Bo, t, body + ITEM, None, .587 + hb + RG, .735, least=1.5),
            Row(d["temp"], BLACK, Wx, 1, .31, .69, .747, .945, least=1.8),
            Row(d["hi"], REGULAR, Wx, s, None, .31 - ITEM, .747, .842, .70, 1.5),
            Row(d["lo"], REGULAR, Wx, t, .69 + ITEM, None, .747, .842, .70, 1.5)]


def awake(rows):
    size = W * SS
    im = Image.new("RGB", (size, size))
    dr = ImageDraw.Draw(im)
    scale = lambda pts: [(x * size, y * size) for x, y in pts]
    for r in rows:
        color = rgb(r.color, r.alpha)
        for c, base, k in r.glyphs():
            _, fills, cuts = glyph(c, r.weight)
            if c in SLANTS:
                s = SLANTS[c]
                dr.polygon(scale([r.point(base + s[i] * k, r.yat(s[i + 1])) for i in (0, 2, 4, 6)]), fill=color)
            for q in fills:
                dr.polygon(scale(r.corners(*q, base, k)), fill=color)
            for q in cuts:
                dr.polygon(scale(r.corners(*q, base, k)), fill=(0, 0, 0))
    return im.resize((W, W), Image.LANCZOS)


def standby(rows, off=(0, 0)):
    """Lines a pixel wide, as Dc.drawLine with no anti-aliasing, then each cut's inside in black"""
    im = Image.new("RGB", (W, W))
    dr = ImageDraw.Draw(im)
    px = lambda p: (p[0] * W + off[0], p[1] * W + off[1])

    def line(r, u0, v0, u1, v1, base, k, color):
        for n in range(SIDE - 1):
            a = r.point(base + u0 * k + (u1 - u0) * k * n / (SIDE - 1), r.yat(v0 + (v1 - v0) * n / (SIDE - 1)))
            b = r.point(base + u0 * k + (u1 - u0) * k * (n + 1) / (SIDE - 1), r.yat(v0 + (v1 - v0) * (n + 1) / (SIDE - 1)))
            dr.line([px(a), px(b)], fill=color, width=1)

    for r in rows:
        color = rgb(r.color, r.alpha)
        for c, base, k in r.glyphs():
            w, fills, cuts = glyph(c, r.weight)
            if c in SLANTS:
                s = SLANTS[c]
                pts = [(s[i], s[i + 1]) for i in (0, 2, 4, 6)]
                for i in range(4):
                    line(r, *pts[i], *pts[(i + 1) % 4], base, k, color)
            for u0, v0, u1, v1 in fills:
                line(r, u0, v0, u1, v0, base, k, color)
                line(r, u0, v1, u1, v1, base, k, color)
                line(r, u0, v0, u0, v1, base, k, color)
                line(r, u1, v0, u1, v1, base, k, color)
            for q in cuts:
                a, t, b, m = max(q[0], 0), max(q[1], 0), min(q[2], w), min(q[3], 1)
                if t > 0:
                    line(r, a, t, b, t, base, k, color)
                if m < 1:
                    line(r, a, m, b, m, base, k, color)
                if a > 0:
                    line(r, a, t, a, m, base, k, color)
                if b < w:
                    line(r, b, t, b, m, base, k, color)
            for q in cuts:
                a, t, b, m = max(q[0], 0), max(q[1], 0), min(q[2], w), min(q[3], 1)
                dl, dr_, dt, db = (-1.5 if q[0] <= 0 else 1.5), (1.5 if q[2] >= w else -1.5), (-1.5 if q[1] <= 0 else 1.5), (1.5 if q[3] >= 1 else -1.5)
                pts = []
                for n in range(SIDE):
                    v = t + (m - t) * n / (SIDE - 1)
                    nudge = dt if n == 0 else db if n == SIDE - 1 else 0
                    x, y = px(r.point(base + a * k, r.yat(v)))
                    pts.append((x + dl, y + nudge))
                for n in reversed(range(SIDE)):
                    v = t + (m - t) * n / (SIDE - 1)
                    nudge = dt if n == 0 else db if n == SIDE - 1 else 0
                    x, y = px(r.point(base + b * k, r.yat(v)))
                    pts.append((x + dr_, y + nudge))
                dr.polygon(pts, fill=(0, 0, 0))
    return im


def lit(im):
    c = Image.new("L", (W, W))
    ImageDraw.Draw(c).ellipse((0, 0, W - 1, W - 1), fill=255)
    black = Image.new("RGB", (W, W))
    black.paste(im, (0, 0), c)
    return sum(black.convert("L").histogram()[13:]) / (math.pi * (W / 2) ** 2), black


EMPTY = dict(time="00:00", sun="--:--", count="--:--", temp="--", hr="--", hi="--", lo="--", date="1/1", bat="--", steps="--", charge="--")
SHORT = dict(time="07:05", sun="07:12", count="0:05", temp="5°", hr="58", hi="9", lo="-2", date="3/5", bat="7", steps="0", charge="5%")
SAMPLES = dict(SAMPLES, empty=EMPTY, short=SHORT)


def check():
    worst = 0.0
    look = LOOKS["yours"]
    for date in ("10/31", "10/28", "12/28", "11/11", "1/8"):
        for sun in ("19:22", "20:08", "08:08", "11:11"):
            for time in ("14:38", "20:08", "08:08", "11:11", "00:00"):
                for temp in ("46°", "88°", "-88°", "100°", "--"):
                    d = dict(date=date, sun=sun, time=time, temp=temp)
                    share, _ = lit(standby(face(d, look, True), (3, 3)))
                    if share > worst:
                        worst = share
                        at = d
    print(f"worst standby at {W}: {worst * 100:.1f}% {at}")


if __name__ == "__main__":
    if "--check" in sys.argv:
        check()
    else:
        out = sys.argv[1]
        words = sys.argv[2:]
        sample = next((SAMPLES[a] for a in words if a in SAMPLES), SAMPLES["day"])
        look = next((LOOKS[a[5:]] for a in words if a.startswith("look=")), LOOKS["yours"])
        aod = "standby" in words
        rows = face(sample, look, aod)
        share, im = lit(standby(rows) if aod else awake(rows))
        im.save(out)
        print(f"lit {share * 100:.1f}%")
