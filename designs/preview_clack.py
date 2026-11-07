#!/usr/bin/env python3
"""Render the Clack face (design #20) with sample readings: what ClackView
will draw, from the same layout fractions, with Pillow and the watch's own
Roboto Condensed Bold.

    python3 -I designs/preview_clack.py out.png [day|night|aod_day|aod_night] [454|416] [hours=21 minutes=05 format=24|12 date=1|0 zoom=0|1 roll=1:120:06 minute=5]

Modes: day (awake, plain cards), night (awake, the lamp on after sunset),
aod_day / aod_night (sleeping: always-on, under 10 % lit, shifted each
minute by Lib.Aod.offset(minute, 4)). format=12 shows a one- or
two-digit hour and an AM/PM flag under it. Each digit is its own leaf:
four cards, hour tens, hour units, minute tens, minute units.
roll=<card>:<angle>:<next>[,<card>:<angle>:<next>] draws those cards
mid-roll (card 0..3; angle 0..180, 0 up, 180 down) falling to <next>, a
digit or "" for a blank leaf. zoom=1 is the zoomed-in variant: the
numbers as large as the circle allows without clipping, the spacing
tightened (ZOOM). Prints the share of the round screen lit.
Approximate to a pixel or two: check the real face with scripts/sim.sh.
"""
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps

sys.path.insert(0, str(Path(__file__).resolve().parent))   # run with -I
from preview_faces import SS, FONTS, FILES, Face, digit_font, glyph_mask, ink_box, outline_of  # noqa: E402

L = dict(
    gap=0.040,                        # the black gap between the hour pair and the minute pair
    inner=0.020,                      # the gap between the two leaves of a pair: each digit is its own leaf
    pad=0.015,                        # a leaf's margin round its digit
    leaf_h=1.32,                      # a leaf's height, times the digit height (the clocks' leaves are about that)
    slot=0.012,                       # the dark slot between the two halves of a leaf, where the axle runs
    corner=0.032,                     # the leaves' corner radius
    pin=0.009,                        # the pivot pins at the slot's ends: radius
    stack=3, stack_step=0.006, stack_inset=0.004,   # the fallen leaves below and the waiting leaves above, as edges
    cy=0.5,                           # the slot: an axle across the whole face
    margin=0.012,                     # the digits clear the bezel by this
    date_y=0.815, date_em=0.044,      # the date (and the AM/PM flag) under the leaves
    lamp=(0.04, -0.06, 0.95),         # the lamp after sunset: centre and radius, out of frame upper left
    spill=0.17, spill_r=0.75,         # its pool on the black
    aod_step=4,                       # Lib.Aod.offset step, device px
    aod_erode=0,                      # standby: device px taken off the digits' strokes before filling and outlining them
)
# the zoomed-in variant (zoom=1): the numbers as large as the circle allows
# without clipping any digit, so the spacing gives way: the leaves nearly
# touch, the digits nearly touch their leaves' edges, and the outer digits'
# corners come to within a few pixels of the bezel
ZOOM = dict(gap=0.028, inner=0.012, pad=0.006, margin=0.004,
            aod_erode=3)              # the bigger digits would light 11 % in standby; eroded 3 px they light 9.5 % (9.8 % on 416)
# a leaf is black plastic lit from above: the upper half brightest at its top, the lower half in the
# upper half's shadow just under the slot, each half's lower edge catching a line of light
DAY = dict(leaf_top=(44, 44, 44), leaf_mid=(26, 26, 26), leaf_shade=(14, 14, 14), leaf_bot=(32, 32, 32), edge=(78, 78, 78), pin=(60, 60, 60), pin_hl=(120, 120, 120),
           stack=(40, 40, 40), ink=(232, 232, 232), ink_lit=(232, 232, 232), lit=1.0, date=(170, 170, 170), spill=None)
NIGHT = dict(leaf_top=(26, 15, 7), leaf_mid=(14, 8, 4), leaf_shade=(6, 3, 2), leaf_bot=(18, 10, 5), edge=(120, 70, 28), pin=(60, 36, 14), pin_hl=(170, 110, 50),
             stack=(44, 26, 10), ink=(150, 96, 48), ink_lit=(255, 218, 160), lit=(92, 52, 18), date=(214, 150, 84), spill=(255, 150, 60))
AOD = dict(day=(128, 128, 128), night=(150, 104, 54))
THETA = [0, 10, 25, 50, 100, 150, 180, 162, 180, 172, 180, 180]   # the round-three sketch's roll (kept for the record)

# ---- the mechanism (ClackView.roll): the drum pushes the leaf slowly off
# its stop, the leaf drops under gravity, drags on the leaf beneath it
# partway down, and bounces off the stop. Each flip draws its own numbers.
MECH = dict(
    g=420.0,                 # 3g / 2L for a leaf about 35 mm from hinge to edge, rad/s^2
    air=3.2,                 # air drag on the thin card, 1/rad: caps the fall near 11 rad/s, a third of a second for the drop
    release=(12.0, 30.0),    # the angle at which the leaf slips off the stop, degrees
    creep=(0.6, 1.4),        # how long the push takes, s (the real clock takes longer; this is what fits a wake)
    drag=(0.0, 1.0),         # 0 a clean drop, 1 a leaf that hangs on the one beneath it
    drag_k=55.0,             # the drag's strength at 1, 1/s, over the middle of the arc
    drag_at=(70.0, 125.0),   # where the leaves rub, degrees
    bounce=(0.15, 0.40),     # restitution at the stop
    settle=3.0,              # degrees of rebound below which the leaf is at rest
)


def roll_profile(fps=30, seed=0, kind=None, creep=None):
    """The leaf's angle at each frame of one flip, from the mechanism:
    (theta degrees, t seconds). `kind` picks a character: "crisp", "floppy",
    "hesitant"; otherwise the seed draws one. `creep` overrides the push's
    length (0 for a catch-up flap that is already off its stop)."""
    import random
    rnd = random.Random(seed)
    lo, hi = MECH["release"]; release = rnd.uniform(lo, hi)
    lo, hi = MECH["creep"]; push = rnd.uniform(lo, hi) if creep is None else creep
    lo, hi = MECH["drag"]; drag = rnd.uniform(lo, hi)
    lo, hi = MECH["bounce"]; e = rnd.uniform(lo, hi)
    if kind == "crisp":
        drag, e = 0.05, 0.2
    elif kind == "floppy":
        drag, e = 1.0, 0.35
    elif kind == "hesitant":
        drag, e, release = 0.75, 0.25, 26.0
    frames = []
    dt = 1 / fps
    t = 0.0
    # the push: slow, slightly accelerating, to the release angle
    n = max(1, int(round(push * fps)))
    for k in range(n):
        frames.append((release * ((k + 1) / n) ** 1.3, t))
        t += dt
    # the drop: integrate at 1 ms, sample each frame
    th = math.radians(release); om = 0.0; h = 0.001; clock = 0.0
    a0, a1 = (math.radians(v) for v in MECH["drag_at"])
    mid, half = (a0 + a1) / 2, (a1 - a0) / 2
    settled = False
    while not settled and clock < 3.0:
        for _ in range(int(round(dt / h))):
            bell = max(0.0, 1 - ((th - mid) / half) ** 2)
            alpha = MECH["g"] * math.sin(th) - MECH["air"] * om * abs(om) - MECH["drag_k"] * drag * bell * om
            om += alpha * h
            th += om * h
            if th >= math.pi:
                th = math.pi
                if om > 0:
                    om = -e * om
                    if abs(om) < math.radians(MECH["settle"]) * 25:   # too little energy to lift the leaf visibly
                        om = 0.0
                        settled = True
            clock += h
        frames.append((math.degrees(th), t))
        t += dt
    frames.append((180.0, t))
    return frames


def roll_summary(frames):
    """creep, fall and bounce times of a profile, s."""
    rel = next((t for th, t in frames if th > MECH["release"][0] + 0.5 and th < 60), 0)
    land = next((t for th, t in frames if th >= 179.5), frames[-1][1])
    return dict(creep=round(rel, 2), fall=round(land - rel, 2), total=round(frames[-1][1], 2), frames=len(frames))

DEFAULTS = dict(hours="14", minutes="38", format="24", date="1", minute=None, roll=None, pm=None, dateText="SAT 31", zoom="0")
SAMPLES = {"day": dict(hours="14", minutes="38"), "night": dict(hours="21", minutes="05")}


def radial(size, cx, cy, r, power=1.5, steps=64):
    m = Image.new("L", size, 0)
    d = ImageDraw.Draw(m)
    for i in range(steps, 0, -1):
        rr = r * i / steps
        d.ellipse((cx - rr, cy - rr, cx + rr, cy + rr), fill=int(255 * (1 - i / steps) ** power))
    return m


def grad(w, h, top, bot, power=1.0):
    """A w x h image shaded from `top` to `bot`."""
    g = ImageOps.invert(Image.linear_gradient("L")).resize((w, max(1, h)))
    if power != 1.0:
        g = g.point(lambda v: int(255 * (v / 255) ** power))
    return Image.composite(Image.new("RGB", (w, max(1, h)), top), Image.new("RGB", (w, max(1, h)), bot), g)


def lamp_mask(face, size, ox, oy):
    S = face.img.size[0]
    lx, ly, lr = L["lamp"]
    return radial(size, lx * S - ox, ly * S - oy, lr * S)


def mul(img, f):
    return img.point(lambda v: min(255, int(v * f)))


class Clack:
    """One face at one size: fonts, card geometry and the sample state."""

    def __init__(self, size, st):
        self.face = Face(size)
        self.S = self.face.px
        self.st = st
        self.L = {**L, **(ZOOM if st.get("zoom") == "1" else {})}
        self.H, self.font, self.cell = self.digit_height()
        S = self.S
        G, g = self.L["gap"], self.L["inner"]
        cw = int(S(self.cell))
        self.ch = int(S(self.H * self.L["leaf_h"]))
        self.y0 = S(self.L["cy"]) - self.ch / 2
        # (x0, width) of the four leaves, left to right, and the x of each digit's centre
        self.cards = [(S(0.5 - G / 2 - g - 2 * self.cell), cw), (S(0.5 - G / 2 - self.cell), cw),
                      (S(0.5 + G / 2), cw), (S(0.5 + G / 2 + self.cell + g), cw)]
        self.centres = [0.5 - G / 2 - g - 1.5 * self.cell, 0.5 - G / 2 - 0.5 * self.cell, 0.5 + G / 2 + 0.5 * self.cell, 0.5 + G / 2 + g + 1.5 * self.cell]
        self.small = ImageFont.truetype(str(FONTS / FILES["RobotoCondensedRegular"]), int(self.S(self.L["date_em"])))

    def digit_height(self):
        """The largest digit height whose widest digit, in its own card, still
        clears the bezel at the outer cards (ClackView.layout). Returns the
        height, the font and a card's cell width, fractions of the width."""
        S = self.S
        G, g = self.L["gap"], self.L["inner"]
        for H in [x / 1000 for x in range(420, 200, -2)]:
            f = digit_font(self.face, "RobotoCondensedBold", S(H))
            d = ink_box(f, "0123456789")
            h = (d[3] - d[1]) / S(1)
            w1 = max((ink_box(f, t)[2] - ink_box(f, t)[0]) / S(1) for t in "0123456789")
            cell = w1 + 2 * self.L["pad"]
            cx = 0.5 + G / 2 + g + 1.5 * cell                     # the outer card's digit centre
            corners = ((cx + w1 / 2, 0.5 - h / 2), (cx + w1 / 2, 0.5 + h / 2))
            if all(math.hypot(px - 0.5, py - 0.5) <= 0.5 - self.L["margin"] for px, py in corners):
                return H, f, cell
        raise SystemExit("no digit size fits")

    def texts(self):
        """The four leaves' digits; a blank leaf for a one-digit 12-hour hour.
        A sequence mid-way may hand the leaves in directly as `digits`."""
        if self.st.get("digits"):
            return list(self.st["digits"])
        h, m = self.st["hours"], self.st["minutes"]
        if self.st["format"] == "12":
            n = int(h) % 12
            h = str(12 if n == 0 else n)
        h = h.rjust(2, " ")
        return [h[0].strip(), h[1], m[0], m[1]]

    def pm(self):
        if self.st["format"] != "12":
            return None
        return "PM" if int(self.st["hours"]) >= 12 else "AM"

    # ---- awake
    def halves(self, cw, ch):
        """The two halves of a leaf as masks: rounded rectangles either side of the slot."""
        S = self.S
        slot = int(S(self.L["slot"]) / 2)
        r = int(S(self.L["corner"]))
        top = Image.new("L", (cw, ch), 0)
        ImageDraw.Draw(top).rounded_rectangle((0, 0, cw - 1, ch // 2 - slot - 1), r, fill=255)
        bot = Image.new("L", (cw, ch), 0)
        ImageDraw.Draw(bot).rounded_rectangle((0, ch // 2 + slot, cw - 1, ch - 1), r, fill=255)
        return top, bot

    def card(self, i, text, pal, night):
        """Leaf i showing one digit (or nothing): black plastic lit from above,
        split by the slot, the digit centred on the leaf, the pivot pins at
        the slot's ends. Returns the leaf image and its mask."""
        ox, cw = self.cards[i]
        oy, ch = self.y0, self.ch
        S = self.S
        top, bot = self.halves(cw, ch)
        h = ch // 2
        # each half shaded top to bottom: light from above, the lower half in the upper half's shadow
        upper = grad(cw, h, pal["leaf_top"], pal["leaf_mid"])
        lower = grad(cw, ch - h, pal["leaf_shade"], pal["leaf_bot"], power=0.6)
        im = Image.new("RGB", (cw, ch), (0, 0, 0))
        im.paste(upper, (0, 0))
        im.paste(lower, (0, h))
        if night:
            lit = Image.composite(Image.new("RGB", (cw, ch), pal["lit"]), Image.new("RGB", (cw, ch), (0, 0, 0)), lamp_mask(self.face, (cw, ch), ox, oy))
            im = Image.blend(im, Image.composite(lit, im, Image.new("L", (cw, ch), 160)), 0.7)
        if text:
            b = ink_box(self.font, text)
            d = ink_box(self.font, "0123456789")
            x = self.S(self.centres[i]) - ox - (b[0] + b[2]) / 2
            basey = ch / 2 - (d[1] + d[3]) / 2
            m = Image.new("L", (cw, ch), 0)
            ImageDraw.Draw(m).text((x, basey), text, font=self.font, fill=255, anchor="ls")
            ink = Image.new("RGB", (cw, ch), pal["ink"])
            if night:
                ink = Image.composite(Image.new("RGB", (cw, ch), pal["ink_lit"]), ink, lamp_mask(self.face, (cw, ch), ox, oy))
            im.paste(ink, (0, 0), m)
        d = ImageDraw.Draw(im)
        slot = int(S(self.L["slot"]) / 2)
        # the upper half's lower edge catches the light; the lower half's top sits in shadow; both lower edges show their thickness
        d.line((int(S(self.L["corner"]) * 0.5), h - slot - 1, cw - int(S(self.L["corner"]) * 0.5), h - slot - 1), fill=pal["edge"], width=SS)
        d.line((int(S(self.L["corner"]) * 0.5), ch - 1, cw - int(S(self.L["corner"]) * 0.5), ch - 1), fill=pal["edge"], width=SS // 2)
        mask = Image.new("L", (cw, ch), 0)
        mask.paste(top, (0, 0), top)
        mask.paste(bot, (0, 0), bot)
        return im, mask

    def pins(self, i, pal):
        """The pivot pins at both ends of leaf i's slot, drawn on the face."""
        ox, cw = self.cards[i]
        S = self.S
        y = S(self.L["cy"])
        r = S(self.L["pin"])
        d = ImageDraw.Draw(self.face.img)
        for x in (ox + r * 1.2, ox + cw - r * 1.2):
            d.ellipse((x - r, y - r, x + r, y + r), fill=pal["pin"])
            d.ellipse((x - r * 0.55, y - r * 0.75, x + r * 0.25, y - r * 0.05), fill=pal["pin_hl"])

    def stack(self, i, pal):
        """The leaves yet to fall, stacked behind the upper half, and the
        fallen ones behind the lower half: their edges show above and below."""
        ox, cw = self.cards[i]
        S = self.S
        d = ImageDraw.Draw(self.face.img)
        inset, step = S(self.L["stack_inset"]), S(self.L["stack_step"])
        for k in range(1, self.L["stack"] + 1):
            x0, x1 = ox + inset * k + S(self.L["corner"]) * 0.4, ox + cw - inset * k - S(self.L["corner"]) * 0.4
            d.line((x0, self.y0 + self.ch + step * k, x1, self.y0 + self.ch + step * k), fill=pal["stack"], width=max(SS // 2, 1))
            if k <= 2:
                d.line((x0, self.y0 - step * k, x1, self.y0 - step * k), fill=pal["stack"], width=max(SS // 2, 1))

    def hinge(self, im):
        """The slot is part of the leaf (halves); nothing to add."""
        return im

    def flap_frame(self, cur, nxt, theta, pal, night):
        """cur falling to nxt, the top flap at theta degrees (0 up, 180 down)."""
        cw, ch = cur.size
        h = ch // 2
        scene = nxt.copy()                                    # the next leaf, in view behind the flap from the moment it lifts
        scene.paste(cur.crop((0, h, cw, ch)), (0, h))         # the current lower half, until the flap's back lands on it
        self.hinge(scene)
        if theta <= 0:
            return scene
        d = ImageDraw.Draw(scene)
        c, s = math.cos(math.radians(theta)), math.sin(math.radians(theta))
        edge = pal["ink"] if night else (90, 90, 90)
        top, bot = self.halves(cw, ch)
        if theta < 90:
            fh = max(SS, int(h * c))
            flap = mul(cur.crop((0, 0, cw, h)).resize((cw, fh)), 1 - (0.6 if night else 0.35) * s)   # turns from the lamp above
            scene.paste(flap, (0, h - fh), top.crop((0, 0, cw, h)).resize((cw, fh)))                  # its own foreshortened outline: the next leaf shows round its corners
            if theta > 15:
                d.line((0, h - fh, cw, h - fh), fill=tuple(int(v * s) for v in edge), width=SS)
        elif theta > 90:
            fh = max(SS, int(h * -c))
            t = (theta - 90) / 90
            flap = mul(nxt.crop((0, h, cw, ch)).resize((cw, fh)), 1 + (0.5 if night else 0.2) * (1 - t))   # its back faces the lamp, then settles
            scene.paste(flap, (0, h), bot.crop((0, h, cw, ch)).resize((cw, fh)))
            sh = int(0.12 * ch * (1 - t) + 0.01 * ch)
            if h + fh + 1 < ch:
                shadow = ImageOps.invert(Image.linear_gradient("L")).resize((cw, sh)).point(lambda v: int(v * (0.7 * (1 - t) + 0.1)))
                scene.paste(Image.new("RGB", (cw, sh), (0, 0, 0)), (0, h + fh), shadow)
            d.line((0, h + fh, cw, h + fh), fill=edge, width=SS)
        else:
            d.rectangle((0, h - SS, cw, h + SS), fill=edge)
        return scene

    def spill(self, pal):
        if not pal["spill"]:
            return
        S = self.face.img.size[0]
        lx, ly, _ = self.L["lamp"]
        m = radial((S, S), lx * S, ly * S, self.L["spill_r"] * S, power=2.2).point(lambda v: int(v * self.L["spill"]))
        self.face.img.paste(Image.new("RGB", (S, S), pal["spill"]), (0, 0), m)

    def caption(self, text, cx, pal):
        """Small spaced capitals on a lower flap: the date, the AM/PM flag."""
        d = ImageDraw.Draw(self.face.img)
        gap = 0.10 * self.small.size
        tw = sum(d.textlength(c, font=self.small) for c in text) + gap * (len(text) - 1)
        x = self.S(cx) - tw / 2
        for c in text:
            d.text((x, self.S(self.L["date_y"])), c, font=self.small, fill=pal["date"], anchor="lm")
            x += d.textlength(c, font=self.small) + gap

    def awake(self, night):
        pal = NIGHT if night else DAY
        self.spill(pal)
        texts = self.texts()
        roll = self.st["roll"] or {}
        for i in range(4):
            self.stack(i, pal)
            im, mask = self.card(i, texts[i], pal, night)
            if i in roll:
                theta, nxt = roll[i]
                nim, _ = self.card(i, nxt, pal, night)
                im = self.flap_frame(im, nim, theta, pal, night)
                mask = self.flap_mask(mask, theta)
            ox, cw = self.cards[i]
            self.face.img.paste(im, (int(ox), int(self.y0)), mask)
            self.pins(i, pal)
        if self.st["date"] == "1":
            self.caption(self.st["dateText"], (self.centres[2] + self.centres[3]) / 2, pal)
        if self.pm():
            self.caption(self.pm(), (self.centres[0] + self.centres[1]) / 2, pal)

    def flap_mask(self, mask, theta):
        """While a flap is mid-fall the leaf's silhouette barely changes: the
        next leaf is right behind the falling flap, so its upper half stays in
        view the whole time, and the falling back covers part of the lower
        half. The frame itself is drawn by flap_frame; the mask just has to
        admit what it drew."""
        cw, ch = mask.size
        h = ch // 2
        out = mask.copy()
        d = ImageDraw.Draw(out)
        c = math.cos(math.radians(theta))
        if 0 < theta < 90:
            fh = max(SS, int(h * c))
            d.rectangle((0, h - fh, cw, h), fill=255)             # the flap in front of the slot; above it the next leaf's upper half stays in view
        elif theta >= 90:
            d.rectangle((0, 0, cw, h), fill=0)
            top, _ = self.halves(cw, ch)
            out.paste(top, (0, 0), top)                           # the next leaf's upper half, now in view
            fh = max(SS, int(h * -c))
            d.rectangle((0, h, cw, h + fh), fill=255)
        return out

    # ---- sleeping
    def sleeping(self, night):
        """Always-on: the lamp turned down. The hour card's upper flaps stay
        lit, its lower flaps and the minute card's digits are edges, the
        hinge crosses the face. Shifted by Lib.Aod.offset(minute, step)."""
        col = AOD["night" if night else "day"]
        dim = tuple(int(v * 0.8) for v in col)
        minute = self.st["minute"] if self.st["minute"] is not None else int(self.st["minutes"])
        dx = ((minute % 5) - 2) * self.L["aod_step"] * SS
        dy = (((2 * minute + minute // 5 + 1) % 5) - 2) * self.L["aod_step"] * SS
        texts = self.texts()
        S = self.S
        ymid = S(self.L["cy"]) + dy
        for i in range(4):
            if not texts[i]:
                continue
            b = ink_box(self.font, texts[i])
            d = ink_box(self.font, "0123456789")
            x = S(self.centres[i]) + dx - (b[0] + b[2]) / 2
            basey = ymid - (d[1] + d[3]) / 2
            m = glyph_mask(self.face, self.font, texts[i], x, basey)
            if self.L["aod_erode"]:
                m = m.filter(ImageFilter.MinFilter(2 * int(round(self.L["aod_erode"] * SS)) + 1))
            if i < 2:
                top = Image.new("L", m.size, 0)
                ImageDraw.Draw(top).rectangle((0, 0, m.size[0], ymid - SS), fill=255)
                self.face.img.paste(Image.new("RGB", m.size, col), (0, 0), Image.composite(m, Image.new("L", m.size, 0), top))
                self.face.img.paste(Image.new("RGB", m.size, dim), (0, 0), Image.composite(outline_of(m, 2), Image.new("L", m.size, 0), ImageOps.invert(top)))
            else:
                self.face.img.paste(Image.new("RGB", m.size, dim), (0, 0), outline_of(m, 2))
        ImageDraw.Draw(self.face.img).line((0, ymid + SS, S(1), ymid + SS), fill=tuple(int(v * 0.5) for v in col), width=SS)


def render(path, mode="day", size=454, st=None):
    st = {**DEFAULTS, **SAMPLES["night" if mode.endswith("night") else "day"], **(st or {})}
    clack = Clack(size, st)
    if mode in ("day", "night"):
        clack.awake(mode == "night")
    else:
        clack.sleeping(mode.endswith("night"))
    return clack.face.done(path) if path else clack.face


def options(args):
    """hours=21 minutes=05 format=12 date=0 roll=3:120:9,2:60:0 minute=5 -> a dict."""
    st = {}
    for a in args:
        k, v = a.split("=", 1)
        if k == "roll":
            st[k] = {}
            for part in v.split(","):
                card, angle, nxt = part.split(":")
                st[k][int(card)] = (float(angle), nxt)
        elif k == "minute":
            st[k] = int(v)
        else:
            st[k] = v
    return st


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    out, mode, size, rest = sys.argv[1], "day", 454, []
    for a in sys.argv[2:]:
        if a in ("day", "night", "aod_day", "aod_night"):
            mode = a
        elif a in ("454", "416"):
            size = int(a)
        else:
            rest.append(a)
    lit = render(out, mode, size, options(rest))
    print(f"{out}: {mode} {size}px, {lit * 100:.1f} % of the screen lit")
