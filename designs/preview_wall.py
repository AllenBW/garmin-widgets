#!/usr/bin/env python3
"""Render the Wall face (design #22) with sample readings: what WallView
draws, from the same layout fractions.

    python3 -I designs/preview_wall.py out.png [day|night|widest] [standby] [look=yours|orange|blue|green|low|gold|ember|orchard|dusk]

FACE_W=416 for the 43 mm. Prints the share of the round screen lit (standby
must stay under 10 %).
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))   # run with -I
from preview_numbers import (BB, BM, RB, RR, S, Canvas, args, chord, family, font, it, metrics, place, rgb, solve,  # noqa: E402
                             span, template)


def wall(d, lk, aod=False):
    cv = Canvas()
    big_look = lk.get("big") and not aod
    D, Su, Wx, Bo, s2, _ = family(lk)
    cw, ch, digit_h = 0.0250, 0.0375, 0.0290
    big = Canvas()
    tall = 0.405
    for txt, yy in ((d["hh"], 0.046), (d["mm"], 0.549)):
        w = metrics(template(txt), BB)[0] * tall
        big.text(txt, BB, tall, 0.5 - w / 2, yy, 0xFFFFFF, align="c", width=w)
    mask = big.mask_all
    belt_y0, belt_y1 = 0.462, 0.538
    stream = "".join(c for c in (d["time"] + d["sun"] + d["count"] + d["temp"] + d["hr"] + d["hi"] + d["lo"] + d["date"]
                                 + d["bat"] + d["steps"]) if c.isdigit())
    if not aod:
        fc, fa = (Su, 1.0) if big_look else (D, .13)
        cv.im.paste(Image.new("RGB", (S, S), rgb(fc, fa)), (0, 0), mask)
    f = font(RR, digit_h * S * metrics("0", RR)[1])
    fb = font(RB, digit_h * S * metrics("0", RB)[1])
    _, dy0, _, _ = f.getbbox("0")
    i = 0
    px = mask.load()
    rows, cols = int(1 / ch) + 1, int(1 / cw) + 1
    ox, oy = (1 - cols * cw) / 2, (1 - rows * ch) / 2
    dr = ImageDraw.Draw(cv.im)

    def inside(q, w):
        return 0 <= q < S and 0 <= w < S and px[q, w] > 128

    for rr in range(rows):
        for cc in range(cols):
            c_ = stream[i % len(stream)]
            i += 1
            x, y = ox + cc * cw, oy + rr * ch
            if y + ch > belt_y0 and y < belt_y1:
                continue
            cx, cy = (x + cw / 2) * S, (y + ch / 2) * S
            on = sum(inside(int(cx + dx * cw * S), int(cy + dy * ch * S)) for dx in (-.25, 0, .25) for dy in (-.25, 0, .25)) >= 5
            if aod:
                if not on:
                    continue
                nb = [(cx + cw * S, cy), (cx - cw * S, cy), (cx, cy + ch * S), (cx, cy - ch * S)]
                if all(inside(int(q), int(w)) for q, w in nb):
                    continue
            if big_look:
                col = (0, 0, 0) if on else rgb(D, .22)
            elif aod:
                col = rgb(D, .80)
            else:
                col = rgb(D) if on else rgb(D, .15)
            fnt = (f if aod else fb) if on else f
            bx0, _, bx1, _ = fnt.getbbox(c_)
            dr.text((cx - (bx0 + bx1) / 2, y * S + (ch - digit_h) / 2 * S - dy0), c_, font=fnt, fill=col)
    if aod:
        items = [it(d["date"], BM, D, .8), it(d["sun"], BB, Su, .8)]
        h, a, c = 0.052, 0.25, 0.75
    else:
        items = [it(d["date"], BB, D), it(d["sun"], BB, Su), it(d["count"], BM, Su, s2), it(d["temp"], BM, Wx), it(d["hr"], BB, Bo)]
        h = solve(items, lambda q: chord(0.5 - q / 2, 0.026), .012)
        a, c = span(0.5 - h / 2, 0.026)
    place(cv, items, h, a, c, 0.5 - h / 2, "fill")
    return cv.done()


if __name__ == "__main__":
    out, sample, look, standby = args(sys.argv)
    im, lit = wall(sample, look, standby)
    im.save(out)
    print(f"lit {lit * 100:.1f}%")
