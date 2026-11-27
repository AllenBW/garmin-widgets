#!/usr/bin/env python3
"""Render the Orb face (design #27) with sample readings: what OrbView draws,
from the same bands and the same digits (gen_lockup.glyph). Lockup's rows
printed round a globe: each band's text spans +-1.25 rad about the vertical
axis, projected orthographically, x = 0.5 + half(y) sin(angle), and dims
toward the limb with cos(angle).

    python3 -I designs/preview_orb.py out.png [day|night|widest|empty|short] [standby] [turn|drum] [look=yours|orange|...] [colors=classic|gold|...|slate] [time=bone|silver|sand|ice|blush] [w=454]
    python3 -I designs/preview_orb.py --check
    python3 -I designs/preview_orb.py --sheet out.png [standby]   # every palette and time colour
    python3 -I designs/preview_orb.py --motion out.gif [away|minute|heart] [look=...]

`--motion` draws a move from the readings of a moment before, a frame every
50 ms, as OrbBand.frame plays it: a band turns half a revolution when at
least half its characters changed (or a reading changed its length), else
each changed digit turns as a drum, units first.

`turn` draws the heart rate's band half way through a turn from the readings
of seven minutes before, `drum` the time's last digit half way round. Prints
the share of the round screen lit. Standby is drawn as on the watch: lines a
pixel wide with no anti-aliasing, the globe turned and shifted for the
minute. --check measures standby over the digits that light the most at
454, 416, 390 and 360 px (it must stay under 10 %, with a margin: the
watch's lines are thicker than Pillow's).
"""
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))   # run with -I
from gen_lockup import SLANTS, glyph  # noqa: E402
from preview_numbers import LOOKS, SAMPLES, rgb, chosen, sheet  # noqa: E402

M = 0.012                 # from the bezel, all round (Lockup's)
A = 1.25                  # each band's half span, in radians about the vertical axis
B = 1.15                  # a drum's half span, in its own radians
GAP, SEG = 0.12, 0.5      # between digits and between readings, in block heights
SS = 4
BLACK, REGULAR = "BLACK", "REGULAR"
N, SU, WX, BO = "data", "sun", "wx", "body"
STANDBY_TURN = 0.035      # the globe's turn per step of the minute's cycle (five steps: +-0.07 rad)
AOD_STEP = 0.006          # Lib.Aod's vertical step, of the width


def half(y):
    d = (0.5 - M) ** 2 - (y - 0.5) ** 2
    return math.sqrt(d) if d > 0 else 0.0


def wrap(a):
    return (a + math.pi) % (2 * math.pi) - math.pi


def width(text, weight):
    return sum(glyph(c, weight)[0] if c in "0123456789:/°-%" else 0.25 for c in text)


class Band:
    """One band: its readings side by side (text, weight, family, level), the
    least room it takes, so a short reading doesn't balloon"""

    def __init__(self, y0, y1, segs, least):
        self.y0, self.y1, self.segs = y0, y1, segs
        self.items, u = [], 0.0
        for si, (text, weight, fam, lvl) in enumerate(segs):
            if si:
                u += SEG
            for ci, c in enumerate(text):
                if ci:
                    u += GAP
                w = glyph(c, weight)[0] if c in "0123456789:/°-%" else 0.25
                self.items.append(dict(c=c, w=w, u=u, weight=weight, fam=fam, lvl=lvl))
                u += w
        lu = sum(width(t, wt) for t, wt in least) + GAP * sum(len(t) - 1 for t, _ in least) + SEG * (len(least) - 1)
        self.U = max(u, lu)
        self.start = (self.U - u) / 2

    def ang(self, u, offset=0.0, rot=0.0):
        return wrap(-A + (u + self.start) / self.U * 2 * A + offset - rot)

    def yat(self, v):
        return self.y0 + v * (self.y1 - self.y0)

    def shade(self, a):
        c = math.cos(a)
        return 0.0 if c <= 0.03 else 0.22 + 0.78 * c ** 0.7


def bands(d, standby=False):
    """the bands, as OrbView.build makes them"""
    if standby:
        return [Band(.052, .128, [(d["date"], BLACK, N, 0)], [("11/11", BLACK)]),
                Band(.150, .290, [(d["sun"], BLACK, SU, 0)], [("11:11", BLACK)]),
                Band(.300, .575, [(d["time"], BLACK, N, 0)], [("11:11", BLACK)]),
                Band(.747, .945, [(d["temp"], BLACK, WX, 0)], [("11°", BLACK)])]
    return [Band(.052, .128, [(d["date"], BLACK, N, 0)], [("11/11", BLACK)]),
            Band(.150, .290, [(d["sun"], BLACK, SU, 0), (d["count"], REGULAR, SU, 1), (d.get("charge", "87%"), REGULAR, N, 2)],
                 [("11:11", BLACK), ("1:11", REGULAR), ("11%", REGULAR)]),
            Band(.300, .575, [(d["time"], BLACK, N, 0)], [("11:11", BLACK)]),
            Band(.587, .735, [(d["hr"], BLACK, BO, 0), (d["steps"], REGULAR, BO, 1), (d["bat"], REGULAR, BO, 2)],
                 [("11", BLACK), ("1111", REGULAR), ("11", REGULAR)]),
            Band(.747, .945, [(d["hi"], REGULAR, WX, 1), (d["temp"], BLACK, WX, 0), (d["lo"], REGULAR, WX, 2)],
                 [("11", REGULAR), ("11°", BLACK), ("11", REGULAR)])]


def color(lk, it, a, full=False):
    share = 1.0 if full or not it["lvl"] else (lk["s"] if it["lvl"] == 1 else lk["t"])
    return rgb(lk[it["fam"]], max(0.0, min(1.0, share * a)))


def segments(b, sl, sr, dv):
    """straight pieces an upright edge needs to stay within half a pixel of its
    curve, as OrbBand.segments: the circle's half width bows most where narrowest"""
    far = b.y0 if abs(b.y0 - 0.5) > abs(b.y1 - 0.5) else b.y1
    h = max(half(far), 0.05)
    curve = (0.5 - M) ** 2 / h ** 3 / 8 * (b.y1 - b.y0) ** 2 * W
    bow = max(abs(sl), abs(sr)) * curve * dv * dv
    return 1 if bow < 0.5 else 2 if bow < 2 else 3 if bow < 4.5 else 4


def rect_pts(b, sl, sr, v0, v1, w, oy=0.0):
    """a rectangle whose upright edges sit at sines sl and sr, from v0 to v1:
    points down the left, then up the right"""
    n = segments(b, sl, sr, v1 - v0)
    ys = [b.yat(v0 + (v1 - v0) * k / n) for k in range(n + 1)]
    return [((0.5 + half(y) * sl) * w, y * w + oy) for y in ys] + [((0.5 + half(y) * sr) * w, y * w + oy) for y in reversed(ys)]


def sine(a):
    return math.sin(max(-math.pi / 2, min(math.pi / 2, a)))


def draw_glyph(dr, b, it, s_of, fill, scale):
    """one character, its rectangles' upright edges at s_of(u in the glyph)"""
    w_, fills, cuts = glyph(it["c"], it["weight"]) if it["c"] in "0123456789:/°-%" else (0.25, [], [])
    sc = lambda pts: [(x * scale, y * scale) for x, y in pts]
    if it["c"] in SLANTS:
        s = SLANTS[it["c"]]
        pts = []
        for i in (0, 2, 4, 6):
            y = b.yat(s[i + 1])
            pts.append(((0.5 + half(y) * s_of(s[i])), y))
        dr.polygon([(x * W * scale, y * W * scale) for x, y in pts], fill=fill)
    for u0, v0, u1, v1 in fills:
        dr.polygon(sc(rect_pts(b, s_of(u0), s_of(u1), v0, v1, W)), fill=fill)
    for u0, v0, u1, v1 in cuts:
        dr.polygon(sc(rect_pts(b, s_of(u0), s_of(u1), v0, v1, W)), fill=(0, 0, 0))


def draw_band(dr, b, lk, offset=0.0, rot=0.0, scale=SS):
    for it in b.items:
        a = b.ang(it["u"] + it["w"] / 2, offset, rot)
        sh = b.shade(a)
        if sh <= 0:
            continue
        draw_glyph(dr, b, it, lambda uu, it=it: sine(b.ang(it["u"] + uu, offset, rot)), color(lk, it, sh), scale)


def draw_drum(dr, b, it, old, drot, lk, scale=SS):
    """a digit as a small globe of its own: the old face turning away, the new coming round"""
    cu = it["u"] + it["w"] / 2
    base = b.shade(b.ang(cu))
    for g, off in ((dict(old, u=it["u"], w=it["w"]), 0.0), (it, math.pi)):
        face = math.cos(wrap(off - drot))
        if face <= 0.03:
            continue
        fw = face * face

        def s_of(uu, g=g, off=off, fw=fw):
            q = uu / g["w"] - 0.5
            a = max(-math.pi / 2, min(math.pi / 2, wrap(2 * B * q + off - drot)))
            m = fw * 2 * q + (1 - fw) * math.sin(a) / math.sin(B)
            return sine(b.ang(cu + it["w"] / 2 * m))
        draw_glyph(dr, b, g, s_of, color(lk, it, base * (0.25 + 0.75 * face ** 0.7)), scale)


def awake(d, lk, motion=None):
    size = W * SS
    im = Image.new("RGB", (size, size))
    dr = ImageDraw.Draw(im)
    now = bands(d)
    if motion == "turn":
        was = bands(dict(d, hr="88", steps="5980", bat="83"))
    for i, b in enumerate(now):
        if motion == "turn" and i == 3:
            draw_band(dr, was[i], lk, 0.0, math.pi / 2 - 0.3)
            draw_band(dr, b, lk, math.pi, math.pi / 2 - 0.3)
        elif motion == "drum" and i == 2:
            for it in b.items[:-1]:
                draw_band_item(dr, b, it, lk)
            draw_drum(dr, b, b.items[-1], dict(b.items[-1], c="7"), math.pi / 2 + 0.2, lk)
        else:
            draw_band(dr, b, lk)
    return im.resize((W, W), Image.LANCZOS)


# ---------------------------------------------------------------- the motion (OrbMoves, OrbBand.frame)

DRUM, DRUM_STEP, DRUM_BAND = 500, 70, 50             # OrbView's
TURN, TURN_GROW, TURN_STEP = 850, 140, 90
PUSH, SETTLE, BACK = 70, 500, 0.025                  # Lib.Motion's

# What changed since you last looked: (was, now), as OrbView.demo's
BASE = SAMPLES["day"]
SCENES = {
    "away": (dict(BASE, time="14:31", count="4:51", charge="88%", hr="88", steps="5980", bat="83", temp="45°"), BASE),
    "minute": (dict(BASE, time="14:37", count="4:45"), BASE),
    "heart": (dict(BASE, hr="70"), BASE),
}


def ease(t, dur, fall, amp):
    """Lib.Motion.ease"""
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


def plan(was, now):
    """per band, as OrbMoves.mode and OrbBand.plan: ("turn", start, dur),
    ("drums", start, [delay or -1 per character]) or None"""
    out = []
    for i, (a, b) in enumerate(zip(bands(was), bands(now))):
        old, new = [s[0] for s in a.segs], [s[0] for s in b.segs]
        if old == new:
            out.append(None)
            continue
        moved = [x != y for p, q in zip(old, new) for x, y in zip(p, q)]
        if [len(s) for s in old] != [len(s) for s in new] or 2 * sum(moved) >= len(moved):
            out.append(("turn", i * TURN_STEP, TURN + TURN_GROW * abs(i - 2)))
            continue
        delays, right = [-1] * len(moved), 0
        for k in range(len(moved) - 1, -1, -1):
            if moved[k]:
                delays[k], right = right * DRUM_STEP, right + 1
        out.append(("drums", i * DRUM_BAND, delays))
    return out


def moving(was, now, lk, t, p=None):
    """the face `t` ms into the move from `was` to `now`"""
    p = p or plan(was, now)
    size = W * SS
    im = Image.new("RGB", (size, size))
    dr = ImageDraw.Draw(im)
    for b, o, m in zip(bands(now), bands(was), p):
        if m and m[0] == "turn" and t - m[1] < PUSH + m[2] + SETTLE:
            rot = math.pi * ease(t - m[1], m[2], False, 0.03)
            draw_band(dr, o, lk, 0.0, rot)
            draw_band(dr, b, lk, math.pi, rot)
        elif m and m[0] == "drums":
            for it, ot, d in zip(b.items, o.items, m[2]):
                e = t - m[1] - d
                if d < 0 or e >= PUSH + DRUM + SETTLE:
                    draw_band_item(dr, b, it, lk)
                else:
                    draw_drum(dr, b, it, ot, math.pi * ease(e, DRUM, False, 0.04), lk)
        else:
            draw_band(dr, b, lk)
    return im.resize((W, W), Image.LANCZOS)


def motion(out, scene, lk):
    """frames every 50 ms (the view's PERIOD) of a move, as out.gif"""
    was, now = SCENES[scene]
    p = plan(was, now)
    span = max(m[1] + (m[2] if m[0] == "turn" else DRUM + max(m[2])) for m in p if m) + PUSH + SETTLE
    frames = [moving(was, now, lk, t, p) for t in range(0, span + 50, 50)]
    frames[0].save(out, save_all=True, append_images=frames[1:] + [frames[-1]] * 20, duration=50, loop=0)
    print(f"{scene}: {sum(1 for m in p if m)} bands move over {span} ms; {out}")
    for i, m in enumerate(p):
        if m:
            print(f"  band {i}: {m[0]} from {m[1]} ms")


def draw_band_item(dr, b, it, lk):
    sh = b.shade(b.ang(it["u"] + it["w"] / 2))
    draw_glyph(dr, b, it, lambda uu: sine(b.ang(it["u"] + uu)), color(lk, it, sh), SS)


def standby(d, lk, minute=0):
    """Lines a pixel wide, as Dc.drawLine with no anti-aliasing, then each
    cut's inside in black; the globe turned and shifted for the minute"""
    im = Image.new("RGB", (W, W))
    dr = ImageDraw.Draw(im)
    rot = ((minute % 5) - 2) * STANDBY_TURN
    step = int(W * AOD_STEP)
    oy = (((2 * minute + minute // 5 + 1) % 5) - 2) * step
    for b in bands(d, True):
        for it in b.items:
            a = b.ang(it["u"] + it["w"] / 2, 0.0, rot)
            sh = b.shade(a)
            if sh <= 0 or it["c"] not in "0123456789:/°-%":
                continue
            col = color(lk, it, sh, True)
            gw, fills, cuts = glyph(it["c"], it["weight"])
            s_of = lambda uu, it=it: sine(b.ang(it["u"] + uu, 0.0, rot))

            def line(u0, v0, u1, v1, other=None):
                if u0 == u1:      # upright: down the curve, as many pieces as the rectangle's two sides need
                    s = s_of(u0)
                    k = segments(b, s, s_of(other), v1 - v0)
                    pts = [b.yat(v0 + (v1 - v0) * n / k) for n in range(k + 1)]
                    for y, y2 in zip(pts, pts[1:]):
                        dr.line([((0.5 + half(y) * s) * W, y * W + oy), ((0.5 + half(y2) * s) * W, y2 * W + oy)], fill=col)
                else:
                    y = b.yat(v0)
                    dr.line([((0.5 + half(y) * s_of(u0)) * W, y * W + oy), ((0.5 + half(y) * s_of(u1)) * W, y * W + oy)], fill=col)

            if it["c"] in SLANTS:
                s = SLANTS[it["c"]]
                pts = [(s[i], s[i + 1]) for i in (0, 2, 4, 6)]
                for i in range(4):
                    (ua, va), (ub, vb) = pts[i], pts[(i + 1) % 4]
                    ya, yb = b.yat(va), b.yat(vb)
                    dr.line([((0.5 + half(ya) * s_of(ua)) * W, ya * W + oy), ((0.5 + half(yb) * s_of(ub)) * W, yb * W + oy)], fill=col)
            for u0, v0, u1, v1 in fills:
                line(u0, v0, u1, v0)
                line(u0, v1, u1, v1)
                line(u0, v0, u0, v1, u1)
                line(u1, v0, u1, v1, u0)
            for q in cuts:
                a0, t, b0, m = max(q[0], 0), max(q[1], 0), min(q[2], gw), min(q[3], 1)
                if t > 0:
                    line(a0, t, b0, t)
                if m < 1:
                    line(a0, m, b0, m)
                if a0 > 0:
                    line(a0, t, a0, m, b0)
                if b0 < gw:
                    line(b0, t, b0, m, a0)
            for q in cuts:      # the inside, 1.5 px in from its own edges, out past the block's rim
                a0, t, b0, m = max(q[0], 0), max(q[1], 0), min(q[2], gw), min(q[3], 1)
                dl, dr_ = (-1.5 if q[0] <= 0 else 1.5), (1.5 if q[2] >= gw else -1.5)
                dt, db = (-1.5 if q[1] <= 0 else 1.5), (1.5 if q[3] >= 1 else -1.5)
                pts = rect_pts(b, s_of(a0), s_of(b0), t, m, W, oy)
                side = len(pts) // 2
                out = []
                for n, (x, y) in enumerate(pts):
                    k = n if n < side else 2 * side - 1 - n
                    nudge = dt if k == 0 else db if k == side - 1 else 0
                    out.append((x + (dl if n < side else dr_), y + nudge))
                dr.polygon(out, fill=(0, 0, 0))
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
W = 454


def check():
    global W
    look = LOOKS["yours"]
    for W in (454, 416, 390, 360):
        worst, at = 0.0, None
        for date in ("10/31", "10/28", "12/28", "11/11", "1/8"):
            for sun in ("19:22", "20:08", "08:08", "11:11"):
                for time in ("14:38", "20:08", "08:08", "11:11", "00:00"):
                    for temp in ("46°", "88°", "-88°", "100°", "--"):
                        d = dict(date=date, sun=sun, time=time, temp=temp)
                        for minute in (0, 2, 4):
                            share, _ = lit(standby(d, look, minute))
                            if share > worst:
                                worst, at = share, dict(d, minute=minute)
        sample, _ = lit(standby(SAMPLES["day"], look, 2))
        print(f"standby at {W}: sample {sample * 100:.1f} %, worst {worst * 100:.1f} % {at}")


if __name__ == "__main__":
    if "--check" in sys.argv:
        check()
    elif "--sheet" in sys.argv:
        words = sys.argv[1:]
        sheet(words[words.index("--sheet") + 1], lambda lk: lit(standby(SAMPLES["day"], lk, 2) if "standby" in words else awake(SAMPLES["day"], lk))[1])
    elif "--motion" in sys.argv:
        args = [a for a in sys.argv[1:] if a != "--motion"]
        motion(args[0], next((a for a in args[1:] if a in SCENES), "away"),
               next((LOOKS[a[5:]] for a in args if a.startswith("look=")), LOOKS["yours"]))
    else:
        out = sys.argv[1]
        words = sys.argv[2:]
        W = next((int(a[2:]) for a in words if a.startswith("w=")), 454)
        sample = next((SAMPLES[a] for a in words if a in SAMPLES), SAMPLES["day"])
        look = chosen(words)
        motion = next((a for a in words if a in ("turn", "drum")), None)
        share, im = lit(standby(sample, look, 2) if "standby" in words else awake(sample, look, motion))
        im.save(out)
        print(f"lit {share * 100:.1f}%")
