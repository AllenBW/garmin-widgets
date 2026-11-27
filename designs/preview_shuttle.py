#!/usr/bin/env python3
"""Render the Shuttle face (design #26) with sample readings: what ShuttleView
draws, from the same rows and the same digits (gen_lockup.glyph), awake, in
standby, and in motion.

    python3 -I designs/preview_shuttle.py out.png [day|night|widest|empty|short] [standby] [look=yours|orange|blue|green|low|gold|ember|orchard|dusk] [colors=classic|gold|...|slate] [time=bone|silver|sand|ice|blush]
    python3 -I designs/preview_shuttle.py --motion out.png [minute|heart|away|midnight]
    python3 -I designs/preview_shuttle.py --check
    python3 -I designs/preview_shuttle.py --sheet out.png [standby]   # every palette and time colour

FACE_W=416 (390, 360) for the other screens. Prints the share of the round
screen lit. Standby is drawn as on the watch: lines a pixel wide with no
anti-aliasing. --check measures it over the digits that light the most (it
must stay under 10 %). --motion draws a sheet of frames of a move (and
out.gif, a frame every 50 ms) the way ShuttleRow does: each changed digit
slides out of its slot as the new one slides in behind it, clipped to the
slot's bounding box, units first, the bands alternating direction.

The layout is Lockup's (designs/preview_lockup.py), kept here on its own so
that the two faces can part.
"""
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))   # run with -I
from gen_lockup import SLANTS, glyph  # noqa: E402
from preview_numbers import LOOKS, SAMPLES, W, rgb, chosen, sheet  # noqa: E402

M, GAP, ITEM, RG = 0.012, 0.010, 0.024, 0.013
SIDE = 5
BLACK, REGULAR = "BLACK", "REGULAR"
SS = 4

# The motion: ShuttleRow and ShuttleView
SLIDE, BOUNCE, STAGGER, BAND_LAG = 360, 0.05, 60, 50
PUSH, SETTLE, BACK = 70, 500, 0.025          # Lib.Motion


def ease(t, dur=SLIDE, amp=BOUNCE):
    """Lib.Motion.ease in its falling form"""
    if t <= 0:
        return 0.0
    if t < PUSH:
        return -BACK * math.sin(math.pi * t / PUSH)
    x = (t - PUSH) / dur
    if x < 1:
        return x * x
    y = (t - PUSH - dur) / 1000.0
    if y * 1000 >= SETTLE:
        return 1.0
    return 1.0 - amp * math.exp(-y * 10) * abs(math.sin(y * math.pi / 0.12))


def done(t, dur=SLIDE):
    return t >= PUSH + dur + SETTLE


def half(y):
    d = (0.5 - M) ** 2 - (y - 0.5) ** 2
    return math.sqrt(d) if d > 0 else 0.0


class Row:
    def __init__(self, key, band, text, weight, color, alpha, lx, rx, y0, y1, bend=0.30, least=1.0):
        self.key, self.band, self.dir = key, band, 1 if band % 2 == 0 else -1
        self.text, self.weight, self.color, self.alpha = text, weight, color, alpha
        self.lx, self.rx, self.y0, self.y1, self.bend, self.least = lx, rx, y0, y1, bend, least
        ym = (y0 + y1) / 2
        self.xlm = 0.5 - half(ym) if lx is None else lx
        self.xrm = 0.5 + half(ym) if rx is None else rx
        self.wm = self.xrm - self.xlm

    def pulls(self, uu):
        fl = max(0.0, 1 - uu / self.bend) if self.lx is None else 0.0
        fr = max(0.0, 1 - (1 - uu) / self.bend) if self.rx is None else 0.0
        return fl ** 1.5, fr ** 1.5

    def point(self, uu, y):
        c = min(self.y1, max(self.y0, y))
        h = half(c)
        fl, fr = self.pulls(uu)
        return self.xlm + uu * self.wm + (0.5 - h - self.xlm) * fl + (0.5 + h - self.xrm) * fr, y

    def glyphs(self, text=None):
        """(character, u of its left, u per block width)"""
        text = self.text if text is None else text
        cw = sum(glyph(c, self.weight)[0] for c in text)
        room = 1 - GAP * (len(text) - 1) / self.wm
        units = max(cw, self.least)
        k = room / units
        u = (units - cw) * k / 2
        for c in text:
            yield c, u, k
            u += glyph(c, self.weight)[0] * k + GAP / self.wm

    def yat(self, v):
        return self.y0 + v * (self.y1 - self.y0)

    def corners(self, u0, v0, u1, v1, base, k):
        pts = []
        for n in range(SIDE):
            pts.append(self.point(base + u0 * k, self.yat(v0 + (v1 - v0) * n / (SIDE - 1))))
        for n in reversed(range(SIDE)):
            pts.append(self.point(base + u1 * k, self.yat(v0 + (v1 - v0) * n / (SIDE - 1))))
        return pts

    def box(self):
        """the row's rectangle in pixels, as ShuttleRow's left, top, right, bottom"""
        left = 0 if self.lx is None else int(self.lx * W)
        right = W if self.rx is None else int(self.rx * W + 0.999)
        return left, int(self.y0 * W), right, int(self.y1 * W + 0.999)

    def slot(self, ua, ub):
        """a slot's clip in pixels: its bounding box over the row's height, kept to the row"""
        upright = (self.lx is not None or ua >= self.bend) and (self.rx is not None or ub <= 1 - self.bend)
        if upright:
            xa, xb = (self.xlm + ua * self.wm) * W, (self.xlm + ub * self.wm) * W
        else:
            ym = min(self.y1, max(self.y0, 0.5))
            xa = min(self.point(ua, y)[0] for y in (self.y0, self.y1, ym)) * W
            xb = max(self.point(ub, y)[0] for y in (self.y0, self.y1, ym)) * W
        left, top, right, bottom = self.box()
        x0, x1 = max(int(xa), left), min(int(xb + 0.999), right)
        return x0, top, max(x1, x0 + 1), bottom


def face(d, lk, aod):
    """the rows, as ShuttleView.build makes them"""
    D, Su, Wx, Bo, s, t = lk["data"], lk["sun"], lk["wx"], lk["body"], lk["s"], lk["t"]
    if aod:
        return [Row("date", 0, d["date"], REGULAR, D, .8, None, None, .052, .128, .60, 3.0),
                Row("sun", 1, d["sun"], BLACK, Su, .9, None, None, .160, .288, least=3.6),
                Row("time", 2, d["time"], BLACK, D, 1, None, None, .300, .575, least=3.6),
                Row("temp", 4, d["temp"], BLACK, Wx, .9, .30, .70, .747, .945, least=1.8)]
    h = half(.214)
    sun = .5 - h + 2 * h * .60
    h = half(.661)
    body = .5 - h + 2 * h * .46
    room = .148 - RG
    hb = room / 2
    return [Row("date", 0, d["date"], BLACK, D, 1 if s == 1 else .85, None, None, .052, .128, .60, 3.0),
            Row("sun", 1, d["sun"], BLACK, Su, 1, None, sun, .140, .288, least=3.6),
            Row("count", 1, d["count"], REGULAR, Su, 1, sun + ITEM, None, .140, .140 + room * .62, least=3.0),
            Row("charge", 1, d.get("charge", "87%"), REGULAR, D, t, sun + ITEM, None, .140 + room * .62 + RG, .288, least=2.6),
            Row("time", 2, d["time"], BLACK, D, 1, None, None, .300, .575, least=3.6),
            Row("hr", 3, d["hr"], BLACK, Bo, 1, None, body, .587, .735, least=1.6),
            Row("steps", 3, d["steps"], REGULAR, Bo, s, body + ITEM, None, .587, .587 + hb, least=2.6),
            Row("bat", 3, d["bat"], REGULAR, Bo, t, body + ITEM, None, .587 + hb + RG, .735, least=1.5),
            Row("temp", 4, d["temp"], BLACK, Wx, 1, .31, .69, .747, .945, least=1.8),
            Row("hi", 4, d["hi"], REGULAR, Wx, s, None, .31 - ITEM, .747, .842, .70, 1.5),
            Row("lo", 4, d["lo"], REGULAR, Wx, t, .69 + ITEM, None, .747, .842, .70, 1.5)]


def paint(dr, r, c, base, k, color, mask=None):
    """one character at `base`, `k` u per block width; on `mask` too, where it draws"""
    size = W * SS
    scale = lambda pts: [(x * size, y * size) for x, y in pts]
    _, fills, cuts = glyph(c, r.weight)
    shapes = []
    if c in SLANTS:
        s = SLANTS[c]
        shapes.append(([r.point(base + s[i] * k, r.yat(s[i + 1])) for i in (0, 2, 4, 6)], color))
    shapes += [(r.corners(*q, base, k), color) for q in fills]
    shapes += [(r.corners(*q, base, k), (0, 0, 0)) for q in cuts]
    for pts, fill in shapes:
        dr.polygon(scale(pts), fill=fill)
        if mask is not None:
            mask.polygon(scale(pts), fill=255)


def awake(rows, motion=None, t=0):
    """the rows; with `motion` ({key: (from, lead)}), `t` ms into the move"""
    size = W * SS
    im = Image.new("RGB", (size, size))
    dr = ImageDraw.Draw(im)
    for r in rows:
        color = rgb(r.color, r.alpha)
        old = None
        if motion and r.key in motion and len(motion[r.key][0]) == len(r.text):
            old, lead = motion[r.key]
        placed = list(r.glyphs())
        if old is not None:
            # The moving digits first, units first, each clipped to its slot
            after = sum(1 for a, b in zip(old, r.text) if a != b)
            for j, (c, base, k) in enumerate(placed):
                if old[j] == c:
                    continue
                after -= 1
                local = t - lead - STAGGER * after
                gw = glyph(c, r.weight)[0] * k
                kold = gw / glyph(old[j], r.weight)[0]     # the old digit takes the new one's width
                if local <= 0:
                    paint(dr, r, old[j], base, kold, color)
                    continue
                if done(local):
                    paint(dr, r, c, base, k, color)
                    continue
                p = ease(local)
                gap = GAP / r.wm
                step, reach = gw + gap, gw + gap / 2
                layer = Image.new("RGB", (size, size))
                mask = Image.new("L", (size, size))
                ld, md = ImageDraw.Draw(layer), ImageDraw.Draw(mask)
                if p * step < reach:
                    paint(ld, r, old[j], base + r.dir * p * step, kold, color, md)
                if (1 - p) * step < reach:
                    paint(ld, r, c, base + r.dir * (p - 1) * step, k, color, md)
                x0, y0, x1, y1 = r.slot(base - gap / 2, base + reach)
                clip = Image.new("L", (size, size))
                ImageDraw.Draw(clip).rectangle((x0 * SS, y0 * SS, x1 * SS - 1, y1 * SS - 1), fill=255)
                mask = Image.composite(mask, Image.new("L", (size, size)), clip)
                im = Image.composite(layer, im, mask)
                dr = ImageDraw.Draw(im)
        for j, (c, base, k) in enumerate(placed):
            if old is None or old[j] == c:
                paint(dr, r, c, base, k, color)
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

# What changed since you last looked (the sketches' scenarios)
BASE = dict(SAMPLES["day"], charge="87%")
SCENES = {
    "minute": (BASE, dict(BASE, time="14:39", count="4:43")),
    "heart": (BASE, dict(BASE, hr="74")),
    "away": (dict(BASE, count="4:51", charge="88%", time="14:31", hr="88", steps="5980", bat="83", temp="45°"), BASE),
    # the date's ends bend the most: its slots' boxes reach furthest into their neighbours
    "midnight": (dict(BASE, date="10/31", time="23:59", count="0:01"), dict(BASE, date="11/01", time="00:00", count="0:00")),
}


def plan(rows, was):
    """{key: (from, lead)} for the rows that move, as ShuttleView.stagger works it out"""
    moving = {r.key: r for r in rows if was[r.key] != r.text and len(was[r.key]) == len(r.text)}
    moved = {k: sum(1 for a, b in zip(was[k], r.text) if a != b) for k, r in moving.items()}
    lx = lambda r: -1.0 if r.lx is None else r.lx
    out = {}
    for k, r in moving.items():
        lead = BAND_LAG * r.band + sum(STAGGER * moved[q] for q, s in moving.items() if s.band == r.band and lx(s) > lx(r))
        out[k] = (was[k], lead, lead + STAGGER * (moved[k] - 1))
    return out


def motion(out, scene):
    was, now = SCENES[scene]
    look = LOOKS["yours"]
    rows = face(now, look, False)
    p = plan(rows, was)
    span = max(tail for _, _, tail in p.values()) + PUSH + SLIDE + SETTLE
    frames = []
    for t in range(0, span + 50, 50):
        frames.append(awake(rows, {k: (f, lead) for k, (f, lead, _) in p.items()}, t))
    gif = Path(out).with_suffix(".gif")
    frames[0].save(gif, save_all=True, append_images=frames[1:] + [frames[-1]] * 20, duration=50, loop=0)
    picks = [0, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 16]
    picks = [i for i in picks if i < len(frames)]
    cell = W // 2
    sheet = Image.new("RGB", (cell * 4, cell * ((len(picks) + 3) // 4)))
    for n, i in enumerate(picks):
        sheet.paste(frames[i].resize((cell, cell), Image.LANCZOS), ((n % 4) * cell, (n // 4) * cell))
        ImageDraw.Draw(sheet).text(((n % 4) * cell + 6, (n // 4) * cell + 4), f"{i * 50} ms", fill=(150, 150, 150))
    sheet.save(out)
    print(f"{scene}: {len(p)} readings move over {span} ms; {out}, {gif}")
    for k, (f, lead, tail) in sorted(p.items(), key=lambda kv: kv[1][1]):
        print(f"  {k}: {f} -> {now[k]}, units at {lead} ms, last digit at {tail} ms")


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
    elif "--sheet" in sys.argv:
        words = sys.argv[1:]
        sheet(words[words.index("--sheet") + 1], lambda lk: lit(standby(face(SAMPLES["day"], lk, True)) if "standby" in words else awake(face(SAMPLES["day"], lk, False)))[1])
    elif "--motion" in sys.argv:
        args = [a for a in sys.argv[1:] if a != "--motion"]
        motion(args[0], next((a for a in args[1:] if a in SCENES), "away"))
    else:
        out = sys.argv[1]
        words = sys.argv[2:]
        sample = next((SAMPLES[a] for a in words if a in SAMPLES), SAMPLES["day"])
        look = chosen(words)
        aod = "standby" in words
        rows = face(sample, look, aod)
        share, im = lit(standby(rows) if aod else awake(rows))
        im.save(out)
        print(f"lit {share * 100:.1f}%")
