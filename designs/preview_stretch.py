# Contact sheet of every Stretching God stretch, drawn from the same tables
# the watch uses (quantised angles, the same framing), the start pose as a
# ghost behind the stretch, the stretched muscle in the accent:
#   python3 -I designs/preview_stretch.py out.png [stretch_id ...]
# Pillow lives in a scratchpad venv (see the watch-face-review skill).
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image, ImageDraw, ImageFont
import gen_stretch as G
import stretch_catalogue as C

FONT = os.path.expanduser("~/Library/Application Support/Garmin/ConnectIQ/Fonts/RobotoCondensed-Bold.ttf")
SS = 4
SIZE = 454
WHITE, FAR, GHOST, ACCENT, GRAY = (235, 235, 230), (122, 122, 122), (80, 80, 80), (255, 138, 76), (158, 158, 158)
LIMBS = [("ho", "kn", "th"), ("kn", "an", "sh"), ("an", "to", "foot"), ("so", "el", "ua"), ("el", "ha", "fa")]


def figure(d, st, t, near, far, accent, cx, ground, bw, bh, mirror=False):
    """StretchFigure.draw, in Python."""
    qa = G.quant(st["a"].angles())[1]
    qb = G.quant(st["b"].angles())[1]
    front = bool(st["flags"] & G.F_FRONT)
    ang = G.lerp_angles(qa, qb, t)
    j = G.placed(st, ang)
    lift, x0, x1, top = G.frame(st)
    s = min(bw / (x1 - x0), bh / top)
    mid = (x0 + x1) / 2
    dirn = -s if mirror else s
    xy = {k: (cx + (x - mid) * dirn, ground - (y - lift) * s) for k, (x, y) in j.items()}
    pen = max(3 * SS, 0.052 * s)
    ghost = accent is None
    if ghost:
        pen *= 0.6   # a thin guide, as StretchFigure draws it
    if front:
        far = near
    tg = set() if ghost else set(st["targets"])
    accent = accent or near

    def seg(a, b, c, w):
        w = int(round(w))
        d.line([xy[a], xy[b]], fill=c, width=w)
        for p in (xy[a], xy[b]):
            d.ellipse([p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2], fill=c)

    if st["flags"] & G.F_WALL and not ghost:
        wx = cx + ((x0 - 0.03 if G.wall_back(st) else x1 + 0.03) - mid) * dirn
        d.line([(wx, ground), (wx, ground - 0.95 * s)], fill=far, width=int(max(2 * SS, pen / 2)))
    if st["flags"] & G.F_CHAIR:
        for (ax, ay), (bx, by) in G.chair(j):
            d.line([(cx + (ax - mid) * dirn, ground - (ay - lift) * s), (cx + (bx - mid) * dirn, ground - (by - lift) * s)],
                   fill=GHOST if ghost else FAR, width=int(pen * 0.5))

    def limbs(side, col):
        for a, b, name in LIMBS:
            hit = side + name in tg
            seg(side + a, side + b, accent if hit else col, pen * (0.8 if name == "foot" else 1) * (1.25 if hit else 1))

    limbs("f", far)
    if front:
        seg("nso", "fso", near, pen)
        seg("nho", "fho", near, pen)
    tc = accent if "torso" in tg else near
    seg("hip", "mid", tc, pen * (1.6 if "torso" in tg else 1.3))
    seg("mid", "sh", tc, pen * (1.6 if "torso" in tg else 1.3))
    seg("sh", "head", accent if "neck" in tg else near, pen * (1.0 if "neck" in tg else 0.8))
    hx, hy = xy["head"]
    r = G.R_HEAD * s
    d.ellipse([hx - r, hy - r, hx + r, hy + r], fill=near)
    if G.nose_shows(ang, front):
        nx, ny = xy["nose"]
        rn = r * G.R_NOSE
        d.ellipse([nx - rn, ny - rn, nx + rn, ny + rn], fill=(0, 0, 0))
    limbs("n", near)
    return lift > 0, pen


def panel(st):
    W = SIZE * SS
    im = Image.new("RGB", (W, W), (0, 0, 0))
    d = ImageDraw.Draw(im)
    ground = int(0.66 * W)
    args = (W // 2, ground, int(0.56 * W), int(0.42 * W))
    figure(d, st, 0.0, GHOST, GHOST, None, *args)
    closeup, pen = figure(d, st, 1.0, WHITE, FAR, ACCENT, *args)
    if closeup:
        d.rectangle([0, ground + pen, W, W], fill=(0, 0, 0))
    elif not st["top"]:
        d.line([(0.2 * W, ground + 2 * SS), (0.8 * W, ground + 2 * SS)], fill=GHOST, width=2 * SS)
    f = ImageFont.truetype(FONT, int(0.06 * W))
    small = ImageFont.truetype(FONT.replace("Bold", "Regular"), int(0.042 * W))
    d.text((W / 2, 0.15 * W), st["name"].upper(), font=f, fill=WHITE, anchor="mm")
    kind = f"{st['dose']} reps" if st["kind"] == G.KIND_REPS else f"hold {st['dose']} s"
    sided = " · each side" if st["flags"] & G.F_SIDED else ""
    d.text((W / 2, 0.21 * W), st["id"] + " · " + kind + sided, font=small, fill=GRAY, anchor="mm")
    for k, c in enumerate(st["cues"]):
        d.text((W / 2, (0.75 + 0.055 * k) * W), c, font=small, fill=WHITE if k else GRAY, anchor="mm")
    im = im.resize((SIZE, SIZE), Image.LANCZOS)
    m = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(m).ellipse([0, 0, SIZE - 1, SIZE - 1], fill=255)
    out = Image.new("RGB", (SIZE, SIZE), (30, 30, 30))
    out.paste(im, (0, 0), m)
    return out


def main():
    out = sys.argv[1]
    want = sys.argv[2:]
    sts = [s for s in C.STRETCHES if not want or s["id"] in want]
    cols = min(5, len(sts))
    rows = (len(sts) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (SIZE + 8), rows * (SIZE + 8)), (30, 30, 30))
    for i, st in enumerate(sts):
        sheet.paste(panel(st), ((i % cols) * (SIZE + 8) + 4, (i // cols) * (SIZE + 8) + 4))
    sheet.save(out)
    print(out, len(sts), "stretches")


if __name__ == "__main__":
    main()
