"""The key images for the faces made of numbers (Blocks, Wall, Lockup): the
store screenshot with every reading named, as the 1440 x 720 hero the
Connect IQ phone app shows at the top of a listing and as a square screen
image. Reads docs/store/<face>-screen.jpg; needs Pillow (a venv) and the
simulator's Roboto Condensed.

    python3 -I designs/store_key.py docs/store   # writes <face>-hero.jpg and <face>-key.jpg
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONTS = Path.home() / "Library/Application Support/Garmin/ConnectIQ/Fonts"
BOLD, REG = FONTS / "RobotoCondensed-Bold.ttf", FONTS / "RobotoCondensed-Regular.ttf"
N, SU, WX, BO = (0xF2, 0xEC, 0xE2), (0xFF, 0xB0, 0x20), (0x4D, 0xB2, 0xFF), (0xFF, 0x5C, 0x9E)
GREY = (0x9A, 0x96, 0x90)
SS = 2   # drawn twice over and scaled down


def font(p, px):
    return ImageFont.truetype(str(p), int(px * SS))


def dim(c, k=0.7):
    return tuple(int(v * k) for v in c)


class Page:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.im = Image.new("RGB", (w * SS, h * SS), (0, 0, 0))
        self.dr = ImageDraw.Draw(self.im)

    def face(self, name, cx, cy, d):
        im = Image.open(ROOT / "docs/store" / f"{name}-screen.jpg").convert("RGB")
        im = im.resize((d * SS, d * SS), Image.LANCZOS)
        mask = Image.new("L", im.size, 0)
        ImageDraw.Draw(mask).ellipse((0, 0, im.size[0] - 1, im.size[1] - 1), fill=255)
        self.im.paste(im, ((cx - d // 2) * SS, (cy - d // 2) * SS), mask)
        self.cx, self.cy, self.d = cx, cy, d

    def fx(self, f):
        return ((self.cx - self.d / 2 + f[0] * self.d) * SS, (self.cy - self.d / 2 + f[1] * self.d) * SS)

    def text(self, s, x, y, f, color, anchor="la"):
        self.dr.text((x * SS, y * SS), s, font=f, fill=color, anchor=anchor)

    def width(self, s, f):
        return self.dr.textlength(s, font=f) / SS

    def line(self, pts, color, w=2):
        self.dr.line([(x, y) for x, y in pts], fill=color, width=int(w * SS), joint="curve")

    def ring(self, p, color, r=6):
        x, y = p
        self.dr.ellipse((x - r * SS, y - r * SS, x + r * SS, y + r * SS), outline=color, width=int(2.2 * SS))

    def save(self, path):
        out = self.im.resize((self.w, self.h), Image.LANCZOS)
        out.save(path)
        out.save(str(path).replace(".png", ".jpg"), quality=90, optimize=True)


def column(labels, top, bottom, pitch):
    """Spread label ys apart (each takes its height plus `pitch` of air), staying near their anchors and inside top..bottom"""
    labels.sort(key=lambda l: l["y"])
    ys = [l["y"] for l in labels]
    for _ in range(300):
        for i in range(1, len(ys)):
            need = (labels[i - 1]["h"] + labels[i]["h"]) / 2 + pitch
            gap = ys[i] - ys[i - 1]
            if gap < need:
                push = (need - gap) / 2
                ys[i - 1] -= push
                ys[i] += push
        ys = [min(max(y, top + l["h"] / 2), bottom - l["h"] / 2) for y, l in zip(ys, labels)]
    for l, y in zip(labels, ys):
        l["y"] = y


def wrap(pg, text, fnt, maxw):
    words, lines, cur = text.split(), [], ""
    for w in words:
        t = (cur + " " + w).strip()
        if cur and pg.width(t, fnt) > maxw:
            lines.append(cur)
            cur = w
        else:
            cur = t
    lines.append(cur)
    return lines


def callouts(pg, items, fnt, left_x, right_x, top, bottom, pitch, lead=14, maxw=None):
    """items: dict(text, color, anchor=(fx,fy), side, via=[(fx,fy)...], y=optional canvas y)"""
    lh = fnt.size / SS * 1.05
    for side, edge in (("L", left_x), ("R", right_x)):
        col = [i for i in items if i["side"] == side]
        width = maxw or (edge - 40 if side == "L" else pg.w - 40 - edge)
        for i in col:
            via = i.get("via", [])
            ref = via[-1] if via else i["anchor"]
            i["y"] = i.get("y", pg.fx(ref)[1] / SS)
            i["lines"] = wrap(pg, i["text"], fnt, width)
            i["h"] = lh * len(i["lines"])
        column(col, top, bottom, pitch)
        for i in col:
            lines = i["lines"]
            y0 = i["y"] - lh * (len(lines) - 1) / 2
            for n, s in enumerate(lines):
                pg.text(s, edge, y0 + n * lh, fnt, i["color"], anchor="rm" if side == "L" else "lm")
            start = ((edge + (lead if side == "L" else -lead)) * SS, i["y"] * SS)
            pts = [start] + [pg.fx(v) for v in via] + [pg.fx(i["anchor"])]
            pg.line(pts, dim(i["color"]), 2)
            pg.ring(pts[-1], i["color"])


def title(pg, name, tag, x, y, size=56, tagsize=30):
    pg.text(name.upper(), x, y, font(BOLD, size), N)
    pg.text(tag, x, y + size * 1.12, font(REG, tagsize), GREY)


def legend(pg, x, y, size=28, gap=36):
    """the four families, as coloured words"""
    f = font(REG, size)
    for word, color in (("time and date", N), ("the sun", SU), ("the weather", WX), ("your body", BO)):
        pg.dr.rounded_rectangle((x * SS, (y - size * 0.32) * SS, (x + size * 0.6) * SS, (y + size * 0.32) * SS), radius=4 * SS, fill=color)
        pg.text(word, x + size * 0.9, y, f, color, anchor="lm")
        x += size * 0.9 + pg.width(word, f) + gap


# ------------------------------------------------------------- the readings

BLOCKS = [
    dict(text="hours, 24-hour", color=N, anchor=(0.140, 0.343), side="L"),
    dict(text="date, month/day", color=N, anchor=(0.254, 0.133), side="L"),
    dict(text="heart rate", color=BO, anchor=(0.032, 0.552), side="L"),
    dict(text="temperature", color=WX, anchor=(0.280, 0.600), side="L"),
    dict(text="today's high and low", color=WX, anchor=(0.067, 0.657), side="L"),
    dict(text="steps", color=BO, anchor=(0.268, 0.869), side="L"),
    dict(text="altitude", color=N, anchor=(0.436, 0.953), side="L"),
    dict(text="minutes", color=N, anchor=(0.859, 0.657), side="R"),
    dict(text="time until it", color=SU, anchor=(0.960, 0.431), side="R"),
    dict(text="next sunset or sunrise", color=SU, anchor=(0.922, 0.315), side="R"),
    dict(text="wind speed", color=WX, anchor=(0.746, 0.133), side="R"),
    dict(text="Body Battery", color=BO, anchor=(0.732, 0.869), side="R"),
]

LOCKUP = [
    dict(text="date, month/day", color=N, anchor=(0.184, 0.090), side="L"),
    dict(text="next sunset or sunrise", color=SU, anchor=(0.060, 0.214), side="L"),
    dict(text="time", color=N, anchor=(0.018, 0.437), side="L"),
    dict(text="heart rate", color=BO, anchor=(0.020, 0.661), side="L"),
    dict(text="today's high", color=WX, anchor=(0.079, 0.795), side="L"),
    dict(text="temperature", color=WX, anchor=(0.50, 0.945), side="L"),
    dict(text="time until it", color=SU, anchor=(0.902, 0.182), side="R"),
    dict(text="watch battery", color=N, anchor=(0.939, 0.262), side="R"),
    dict(text="steps", color=BO, anchor=(0.980, 0.621), side="R"),
    dict(text="Body Battery", color=BO, anchor=(0.958, 0.701), side="R"),
    dict(text="today's low", color=WX, anchor=(0.921, 0.795), side="R"),
]

WALL = [
    dict(text="hours", color=N, anchor=(0.215, 0.26), side="L"),
    dict(text="minutes", color=N, anchor=(0.80, 0.74), side="R"),
]
WALL_BAND = [("date", N, 0.027, 0.283), ("next sunset or sunrise", SU, 0.296, 0.531), ("time until it", SU, 0.543, 0.719),
             ("temperature", WX, 0.730, 0.854), ("heart rate", BO, 0.866, 0.973)]

TAGS = {"blocks": "what each number is", "wall": "what each number is", "lockup": "what each number is"}


def wall_strip(pg, x, y, w, labels_above, labels_below, fnt):
    """the band across the middle, magnified, with its readings named"""
    src = Image.open(ROOT / "docs/store/wall-screen.jpg").convert("RGB")
    S = src.size[0]
    y0, y1 = 0.455, 0.547
    crop = src.crop((int(0.012 * S), int(y0 * S), int(0.988 * S), int(y1 * S)))
    k = w / crop.size[0]
    h = int(crop.size[1] * k)
    crop = crop.resize((int(w * SS), int(h * SS)), Image.LANCZOS)
    pg.im.paste(crop, (int(x * SS), int(y * SS)))
    # a zoom callout: the band's ends on the face to the strip's corners
    for fxp, sx in (((0.012, y1), x), ((0.988, y1), x + w)):
        a = pg.fx(fxp)
        pg.line([a, (sx * SS, y * SS)], dim(GREY, 0.6), 1.5)
    pg.dr.rectangle((x * SS, y * SS, (x + w) * SS, (y + h) * SS), outline=dim(GREY, 0.6), width=int(1.5 * SS))
    for n, (text, color, f0, f1) in enumerate(WALL_BAND):
        cx = x + (f0 - 0.012) / (0.988 - 0.012) * w + (f1 - f0) / (0.988 - 0.012) * w / 2
        above = n % 2 == 1
        ty = (y - labels_above) if above else (y + h + labels_below)
        pg.text(text, cx, ty, fnt, color, anchor="mb" if above else "mt")
        pg.line([(cx * SS, (y - 6) * SS if above else (y + h + 6) * SS), (cx * SS, (ty + 6) * SS if above else (ty - 6) * SS)], dim(color), 1.5)
    return h


def hero(name, items, out):
    pg = Page(1440, 720)
    if name == "wall":
        pg.face(name, 400, 350, 560)
        title(pg, name, TAGS[name], 760, 48)
        f = font(REG, 30)
        callouts(pg, items, f, 100, 700, 120, 690, 14)
        h = wall_strip(pg, 770, 360, 630, 22, 22, f)
        pg.text("the small digits are these readings, repeated;", 760, 360 + h + 86, font(REG, 26), GREY)
        pg.text("the time is where they turn bright and bold", 760, 360 + h + 120, font(REG, 26), GREY)
        legend(pg, 48, 680, 26, 30)
    else:
        pg.face(name, 720, 360, 600)
        title(pg, name, TAGS[name], 48, 40)
        callouts(pg, items, font(REG, 34), 400, 1040, 175, 690, 14)
        legend(pg, 48, 672)
    pg.save(out)


def square(name, items, out):
    pg = Page(1000, 1000)
    title(pg, name, TAGS[name], 48, 40, 52, 28)
    if name == "wall":
        pg.face(name, 500, 400, 440)
        f = font(REG, 28)
        callouts(pg, items, f, 250, 750, 200, 620, 14)
        h = wall_strip(pg, 60, 700, 880, 20, 20, f)
        pg.text("the small digits are these readings, repeated; the time is where they turn bright and bold",
                500, 700 + h + 86, font(REG, 24), GREY, anchor="mt")
    else:
        pg.face(name, 500, 530, 540)
        callouts(pg, items, font(REG, 30), 212, 788, 180, 860, 14)
    legend(pg, 48, 950, 26, 30)
    pg.save(out)


if __name__ == "__main__":
    outdir = Path(sys.argv[1])
    for name, items in (("blocks", BLOCKS), ("wall", WALL), ("lockup", LOCKUP)):
        hero(name, [dict(i) for i in items], outdir / f"{name}-hero.png")
        square(name, [dict(i) for i in items], outdir / f"{name}-key.png")
        print(name)
