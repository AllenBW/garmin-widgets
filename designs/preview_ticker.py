#!/usr/bin/env python3
"""Render the Ticker face (design #25) with sample readings: what TickerView
draws, from the same layout and the same digits (gen_lockup.glyph).

    python3 -I designs/preview_ticker.py out.png [day|widest|empty] [standby] [look=yours|orange|...] [wake=MS]
    python3 -I designs/preview_ticker.py --check

FACE_W=416 (390, 360) for the smaller watches. Prints the share of the round
screen lit. `wake=MS` draws the wake seven minutes after the last look (the
sketch's "seven minutes away", sample-wake.jungle) MS milliseconds in.
Standby is drawn as on the watch: lines a pixel wide with no anti-aliasing,
each cut's inside in black. --check measures it at 454, 416, 390 and 360 px
over the readings that light the most (it must stay under 10 %).
"""
import math
import os
import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))   # run with -I
from gen_lockup import SLANTS, glyph  # noqa: E402
from preview_numbers import LOOKS, rgb  # noqa: E402

SS = 4
# The bands, top tape, time, bottom tape, as fractions of the width (TickerView.Y0, Y1)
Y0 = (0.17, 0.35, 0.74)
Y1 = (0.26, 0.65, 0.83)
GAP = 0.12            # blocks between characters (TickerType.GAP)
ASPECT = 0.6          # a block's width per its height
PITCH = 0.291         # between readings on a thin tape, of the width
SPACE = 0.35          # blocks between minutes on the minute tape
DIM, REACH = 0.34, 1.75
FADE, FAINT, TIME_REACH = 0.8, 0.16, 2.0
STEP = 0.006          # Lib.Aod's step, of the width
TOP = ("date", "sun", "count", "charge")
BOTTOM = ("hr", "steps", "bat", "temp", "hi", "lo")
REST = (1, 3)         # the sun, the temperature
FAMILY = dict(date="data", sun="sun", count="sun", charge="data", hr="body", steps="body", bat="body", temp="wx", hi="wx", lo="wx",
              time="data")

DAY = dict(date="10/31", time="14:38", sun="19:22", count="4:44", charge="87%", hr="72", steps="6214", bat="82", temp="46°",
           hi="52", lo="38")
AWAY = dict(DAY, time="14:31", count="4:51", charge="88%", hr="88", steps="5980", bat="83", temp="45°")
WIDEST = dict(date="11/11", time="20:08", sun="20:08", count="10:08", charge="100%", hr="188", steps="88888", bat="100",
              temp="-88°", hi="-88", lo="-88")
EMPTY = dict(date="1/1", time="00:00", sun="--:--", count="--:--", charge="--", hr="--", steps="--", bat="--", temp="--", hi="--", lo="--")
SAMPLES = dict(day=DAY, widest=WIDEST, empty=EMPTY)


# ---------------------------------------------------------------- the motion (TickerMove, Lib.Motion.ease)

PUSH, SETTLE, BACK = 70, 500, 0.025


def ease(t, dur, fall, amp):
    if t <= 0:
        return 0.0
    if t < PUSH:
        return -BACK * math.sin(math.pi * t / PUSH)
    x = (t - PUSH) / dur
    if x < 1:
        if fall:
            return x * x
        return 4 * x ** 3 if x < 0.5 else 1 - (2 - 2 * x) ** 3 / 2
    y = (t - PUSH - dur) / 1000
    if y * 1000 >= SETTLE:
        return 1.0
    return 1 - amp * math.exp(-y * 10) * abs(math.sin(y * math.pi / 0.12))


def minutes(text):
    h, m = text.split(":")
    return int(h) * 60 + int(m)


def clock(m):
    m %= 1440
    return f"{m // 60:02d}:{m % 60:02d}"


class Wake:
    """The move from `was` to `now`, `t` ms in, as TickerMove times it"""

    def __init__(self, was, now, t):
        self.was, self.now, self.t = was, now, t
        self.last = minutes(now["time"])
        self.steps = min(12, (self.last - minutes(was["time"])) % 1440)
        self.turn, self.slide_at = [], []
        for i, keys in enumerate((TOP, BOTTOM)):
            first = next((k for k, key in enumerate(keys) if was[key] != now[key]), None)
            a = b = REST[i]
            if first is not None:
                delta = first - a                   # round the short way, as TickerView.start
                if delta > len(keys) // 2:
                    delta -= len(keys)
                elif delta < -(len(keys) // 2):
                    delta += len(keys)
                b = a + delta
            self.turn.append((a, b))
            self.slide_at.append(((750, 850)[i]) if a != b else (150, 250)[i])

    def minute(self):
        if self.steps == 0:
            return float(self.last)
        return self.last - self.steps + self.steps * ease(self.t, 450 + 120 * self.steps, False, 0.12 / self.steps)

    def tape(self, i):
        a, b = self.turn[i]
        return a + (b - a) * ease(self.t - (150, 250)[i], (550, 600)[i], False, 0.1)

    def slide(self, i, right):
        return ease(self.t - self.slide_at[i] - right * 60, 360, True, 0.05)


# ---------------------------------------------------------------- drawing

def width(text):
    return sum(glyph(c, "BLACK")[0] for c in text) + GAP * (len(text) - 1)


def line(dr, text, cx, top, height, color, k, old=None, slide=None):
    """`text` centred on cx at `height` px from `top`, k px per output px; the
    characters that differ from `old` slid by `slide(right)`, clipped to their slots"""
    bx = height * ASPECT
    x = cx - width(text) * bx / 2
    moved = sum(1 for a, b in zip(old, text) if a != b) if old and len(old) == len(text) and old != text else 0
    for j, c in enumerate(text):
        w = glyph(c, "BLACK")[0]
        changed = moved and old[j] != c
        if changed:
            moved -= 1
        if changed and slide(moved) < 1:
            p = slide(moved)
            step = (w + GAP) * bx
            clip = (x - GAP * bx / 2, x + (w + GAP / 2) * bx)
            one(dr, old[j], x + p * step, top, height, color, k, clip)
            one(dr, c, x + (p - 1) * step, top, height, color, k, clip)
        else:
            one(dr, c, x, top, height, color, k)
        x += (w + GAP) * bx


def one(dr, c, x, top, height, color, k, clip=None):
    w, fills, cuts = glyph(c, "BLACK")
    bx = height * ASPECT

    def box(q, fill):
        x0, x1 = x + q[0] * bx, x + q[2] * bx
        if clip:
            x0, x1 = max(x0, clip[0]), min(x1, clip[1])
        if (x1 - x0) * k >= 1:
            dr.rectangle((x0 * k, (top + q[1] * height) * k, x1 * k - 1, (top + q[3] * height) * k - 1), fill=fill)

    if c in SLANTS:
        s = SLANTS[c]
        dr.polygon([((x + s[i] * bx) * k, (top + s[i + 1] * height) * k) for i in (0, 2, 4, 6)], fill=color)
    for q in fills:
        box(q, color)
    for q in cuts:
        box(q, (0, 0, 0))


def awake(d, lk, W, move=None):
    size = W * SS
    im = Image.new("RGB", (size, size))
    dr = ImageDraw.Draw(im)
    # the minute tape
    h = (Y1[1] - Y0[1]) * W
    last = minutes(d["time"])
    pos = move.minute() if move else float(last)
    pitch = (width(clock(last)) + SPACE) * h * ASPECT
    for m in range(last, last - 16, -1):
        dd = m - pos
        if dd > TIME_REACH:
            continue
        if dd < -TIME_REACH:
            break
        a = max(FAINT, 1 - abs(dd) * FADE)
        line(dr, clock(m), W / 2 + dd * pitch, Y0[1] * W, h, rgb(lk["data"], a), SS)
    # the thin tapes
    for i, keys in enumerate((TOP, BOTTOM)):
        b = (0, 2)[i]
        h = (Y1[b] - Y0[b]) * W
        pos = move.tape(i) if move else float(REST[i])
        base = int(pos)
        for j in range(base - 3, base + 4):
            dd = j - pos
            if abs(dd) > REACH:
                continue
            key = keys[j % len(keys)]
            shade = DIM + (1 - DIM) * max(0.0, 1 - abs(dd))
            old = move.was[key] if move else None
            line(dr, d[key], W / 2 + dd * PITCH * W, Y0[b] * W, h, rgb(lk[FAMILY[key]], shade), SS, old,
                 (lambda right, i=i: move.slide(i, right)) if move else None)
    return im.resize((W, W), Image.LANCZOS)


def standby(d, lk, W, off=(0, 0)):
    """Lines a pixel wide, as Dc.drawLine with no anti-aliasing, then each cut's inside in black"""
    im = Image.new("RGB", (W, W))
    dr = ImageDraw.Draw(im)

    def outline(text, top, height, color):
        bx = height * ASPECT
        x = W / 2 - width(text) * bx / 2
        for c in text:
            w, fills, cuts = glyph(c, "BLACK")
            X = lambda u: x + u * bx + off[0]
            Y = lambda v: top + v * height + off[1]
            if c in SLANTS:
                s = SLANTS[c]
                pts = [(X(s[i]), Y(s[i + 1])) for i in (0, 2, 4, 6)]
                for n in range(4):
                    dr.line([pts[n], pts[(n + 1) % 4]], fill=color, width=1)
            for u0, v0, u1, v1 in fills:
                dr.line([(X(u0), Y(v0)), (X(u1), Y(v0))], fill=color)
                dr.line([(X(u0), Y(v1)), (X(u1), Y(v1))], fill=color)
                dr.line([(X(u0), Y(v0)), (X(u0), Y(v1))], fill=color)
                dr.line([(X(u1), Y(v0)), (X(u1), Y(v1))], fill=color)
            for q in cuts:
                a, t, b, m = max(q[0], 0), max(q[1], 0), min(q[2], w), min(q[3], 1)
                if t > 0:
                    dr.line([(X(a), Y(t)), (X(b), Y(t))], fill=color)
                if m < 1:
                    dr.line([(X(a), Y(m)), (X(b), Y(m))], fill=color)
                if a > 0:
                    dr.line([(X(a), Y(t)), (X(a), Y(m))], fill=color)
                if b < w:
                    dr.line([(X(b), Y(t)), (X(b), Y(m))], fill=color)
            for q in cuts:
                a, t, b, m = max(q[0], 0), max(q[1], 0), min(q[2], w), min(q[3], 1)
                d0 = -1.5 if q[0] <= 0 else 1.5
                d1 = 1.5 if q[2] >= w else -1.5
                dt = -1.5 if q[1] <= 0 else 1.5
                db = 1.5 if q[3] >= 1 else -1.5
                x0, y0, x1, y1 = X(a) + d0, Y(t) + dt, X(b) + d1, Y(m) + db
                if math.ceil(x1) > math.ceil(x0) and math.ceil(y1) > math.ceil(y0):
                    dr.rectangle((math.ceil(x0), math.ceil(y0), math.ceil(x1) - 1, math.ceil(y1) - 1), fill=(0, 0, 0))
            x += (w + GAP) * bx

    outline(d["time"], Y0[1] * W, (Y1[1] - Y0[1]) * W, rgb(lk["data"]))
    for i, keys in enumerate((TOP, BOTTOM)):
        b = (0, 2)[i]
        key = keys[REST[i]]
        outline(d[key], Y0[b] * W, (Y1[b] - Y0[b]) * W, rgb(lk[FAMILY[key]]))
    return im


def lit(im, W):
    c = Image.new("L", (W, W))
    ImageDraw.Draw(c).ellipse((0, 0, W - 1, W - 1), fill=255)
    black = Image.new("RGB", (W, W))
    black.paste(im, (0, 0), c)
    return sum(black.convert("L").histogram()[13:]) / (math.pi * (W / 2) ** 2), black


def check():
    look = LOOKS["yours"]
    for W in (454, 416, 390, 360):
        worst, at = 0.0, None
        step = int(W * STEP)
        for time in ("08:08", "20:08", "00:00", "18:58", "14:38"):
            for sun in ("20:08", "08:08", "19:22", "--:--"):
                for temp in ("-88°", "88°", "100°", "-12°", "46°"):
                    d = dict(DAY, time=time, sun=sun, temp=temp)
                    share, _ = lit(standby(d, look, W, (2 * step, 2 * step)), W)
                    if share > worst:
                        worst, at = share, (time, sun, temp)
        print(f"worst standby at {W}: {worst * 100:.1f}% {at}")


if __name__ == "__main__":
    if "--check" in sys.argv:
        check()
    else:
        W = int(os.environ.get("FACE_W", 454))
        out = sys.argv[1]
        words = sys.argv[2:]
        sample = next((SAMPLES[a] for a in words if a in SAMPLES), DAY)
        look = next((LOOKS[a[5:]] for a in words if a.startswith("look=")), LOOKS["yours"])
        wake = next((int(a[5:]) for a in words if a.startswith("wake=")), None)
        if "standby" in words:
            share, im = lit(standby(sample, look, W), W)
        else:
            share, im = lit(awake(sample, look, W, Wake(AWAY, DAY, wake) if wake is not None else None), W)
        im.save(out)
        print(f"lit {share * 100:.1f}%")
