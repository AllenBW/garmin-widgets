#!/usr/bin/env python3
"""Render the Blocks face (design #21) with sample readings: what BlocksView
draws, from the same layout fractions.

    python3 -I designs/preview_blocks.py out.png [day|night|widest] [standby] [look=yours|orange|blue|green|low|gold|ember|orchard|dusk]

FACE_W=416 for the 43 mm. Prints the share of the round screen lit (standby
must stay under 10 %).
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))   # run with -I
from preview_numbers import BB, BM, Canvas, args, family, it, metrics, place, solve, span, stack, template  # noqa: E402


def blocks(d, lk, aod=False):
    cv = Canvas()
    M, G, RG = 0.022, 0.015, 0.020
    mode = "line" if aod else "fill"
    D, Su, Wx, Bo, s2, s3 = family(lk)
    mid, H = 0.500, 0.300
    hw = metrics(template(d["hh"]), BB)[0] * H
    hy, my = mid - G / 2 - H, mid + G / 2
    hx = span(hy, M)[0] + .006
    mx = span(my + H, M)[1] - hw - .006
    cv.text(d["hh"], BB, H, hx, hy, D, mode=mode, align="c", width=hw)
    cv.text(d["mm"], BB, H, mx, my, D, mode=mode, align="c", width=hw)
    # the corner right of the hours: the sun, stacked up from the middle to the bezel
    xr = hx + hw + G
    y, top = mid - G / 2, hy
    for r in ([it(d["count"], BM, Su, s2)], [it(d["sun"], BB, Su)]):
        hh = solve(r, lambda q, y=y: span(y - q, M)[1] - xr, RG)
        place(cv, r, hh, xr, span(y - hh, M)[1], y - hh, mode)
        y -= hh + G
        top = min(top, y + G)
    # the corner left of the minutes: heart rate and the weather
    xl = mx - G
    y, bot = mid + G / 2, my + H
    rows = ([it(d["hr"], BB, Bo), it(d["temp"], BM, Wx)], [it(d["hi"], BM, Wx, s2), it(d["lo"], BM, Wx, s3)])
    for r in rows[:1] if aod else rows:   # no high and low in standby: the lit budget
        hh = solve(r, lambda q, y=y: xl - span(y + q, M)[0], RG)
        place(cv, r, hh, span(y + hh, M)[0], xl, y, mode)
        y += hh + G
        bot = max(bot, y - G)
    if aod:
        stack(cv, [[it(d["date"], BM, D, .8)]], top, -1, M, G, RG, mode)
    else:
        stack(cv, [[it(d["date"], BB, D), it(d["wind"], BM, Wx, s2)]], top, -1, M, G, RG, mode)
        stack(cv, [[it(d["steps"], BM, Bo, s2), it(d["bat"], BM, Bo, s3)], [it(d["alt"], BM, D, s3)]], bot, 1, M, G, RG, mode)
    return cv.done()


if __name__ == "__main__":
    out, sample, look, standby = args(sys.argv)
    im, lit = blocks(sample, look, standby)
    im.save(out)
    print(f"lit {lit * 100:.1f}%")
