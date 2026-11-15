import Toybox.Graphics;
import Toybox.Lang;

// Lockup's numerals (Digits.mc) laid flat for Ticker: a string of them on one
// line at one height. The tapes never bend, so every part is an upright
// rectangle. Each height's rectangles are worked out in whole pixels once
// (a table per height: the thin tapes' and the time's), so a digit is a
// handful of fillRectangle calls at a rounded left edge, the same shape
// wherever it slides, and nothing is allocated per digit. Counts the
// characters it draws, a frame's cost (TickerView.BUDGET).
class TickerType {

    const GAP = 120;           // thousandths of a block between characters
    const ASPECT = 0.6;        // a block's width per its height
    const UNKNOWN = 250;       // the room a character the numerals don't have takes
    const MOST = 12;           // characters in a text, at most

    var count as Number = 0;   // characters drawn, for the frame's budget

    private var _sx as Float = 0.1;     // px per thousandth of a block, across
    private var _sy as Float = 0.1;     // and down
    private var _top as Float = 0.0;
    private var _topPx as Number = 0;
    private var _lo as Float = 0.0;     // a character wholly outside lo..hi is not drawn
    private var _hi as Float = 454.0;
    private var _clipY as Number = 0;   // the band a sliding digit's slot is clipped within
    private var _clipH as Number = 0;
    private var _w as Number = 454;
    // Per character, its rectangles in px from its rounded top left corner:
    // [fills, x, y, w, h, ...], the fills then the cuts; one table per height
    private var _table as Array<Array<Number>> = [] as Array<Array<Number>>;
    private var _tables as Dictionary<Number, Array<Array<Number>>> = {} as Dictionary<Number, Array<Array<Number>>>;
    private var _index as Array<Number>;        // the characters of the text being drawn, as indexes
    private var _was as Array<Number>;          // and the old text's

    function initialize() {
        _index = new [MOST] as Array<Number>;
        _was = new [MOST] as Array<Number>;
    }

    // A line `height` px tall from `top` (px), drawn only between `lo` and
    // `hi`, inside the rows clipY to clipY + clipH of a dc `w` wide
    function setLine(top as Float, height as Float, lo as Float, hi as Float, clipY as Number, clipH as Number, w as Number) as Void {
        _top = top;
        _topPx = (top + 0.5).toNumber();
        _sy = height / 1000.0;
        _sx = _sy * ASPECT;
        _lo = lo;
        _hi = hi;
        _clipY = clipY;
        _clipH = clipH;
        _w = w;
        var key = (height * 16.0).toNumber();
        var table = _tables[key];
        if (table == null) {
            table = new [Digits.BLACK.size()] as Array<Array<Number>>;
            for (var i = 0; i < table.size(); i++) {
                var g = Digits.BLACK[i];
                var t = [g[1]] as Array<Number>;
                for (var at = 2; at < g.size(); at += 4) {
                    var xa = (g[at] * _sx + 0.5).toNumber();
                    var ya = (g[at + 1] * _sy + 0.5).toNumber();
                    t.add(xa);
                    t.add(ya);
                    t.add((g[at + 2] * _sx + 0.5).toNumber() - xa);
                    t.add((g[at + 3] * _sy + 0.5).toNumber() - ya);
                }
                table[i] = t;
            }
            _tables[key] = table;
        }
        _table = table;
    }

    // px per thousandth of a block, across
    function scale() as Float {
        return _sx;
    }

    // A text's width, in thousandths of a block
    function width(text as String) as Number {
        return widthOf(text.toCharArray());
    }

    private function widthOf(chars as Array<Char>) as Number {
        var sum = GAP * (chars.size() - 1);
        for (var j = 0; j < chars.size(); j++) {
            var i = Digits.index(chars[j]);
            sum += (i < 0) ? UNKNOWN : Digits.BLACK[i][0];
        }
        return sum;
    }

    // `text` centred on cx, in `color`. Given the `old` text, of the same
    // length, and the move under way, the characters that differ slide
    // sideways in their own slots, the old out to the right and the new in
    // from the left, units first (thin tape `tape` of the move)
    function line(dc as Dc, text as String, old as String?, cx as Float, color as Number, move as TickerMove?, tape as Number) as Void {
        var chars = text.toCharArray();
        var n = (chars.size() < MOST) ? chars.size() : MOST;
        var idx = _index;
        var units = GAP * (n - 1);
        for (var j = 0; j < n; j++) {
            var i = Digits.index(chars[j]);
            idx[j] = i;
            units += (i < 0) ? UNKNOWN : Digits.BLACK[i][0];
        }
        var x = cx - units * _sx / 2.0;
        var was = _was;
        var sliding = false;
        var moved = 0;
        if (old != null && move != null && old.length() == text.length() && !old.equals(text)) {
            sliding = true;
            var oc = old.toCharArray();
            for (var j = 0; j < n; j++) {
                was[j] = Digits.index(oc[j]);
                if (was[j] != idx[j]) {
                    moved++;
                }
            }
        }
        for (var j = 0; j < n; j++) {
            var i = idx[j];
            var x1 = x + ((i < 0) ? UNKNOWN : Digits.BLACK[i][0]) * _sx;
            var changed = sliding && was[j] != i;
            if (changed) {
                moved--;                       // now the changed characters to its right
            }
            if (x1 > _lo && x < _hi) {
                var p = changed ? (move as TickerMove).slide(tape, moved) : 1.0;
                if (p >= 1.0) {
                    if (i >= 0) {
                        glyph(dc, i, x, color);
                    }
                } else {
                    var step = x1 - x + GAP * _sx;
                    var s0 = (x - GAP * _sx / 2.0 + 0.5).toNumber();
                    var s1 = (x1 + GAP * _sx / 2.0 + 0.5).toNumber();
                    dc.setClip(s0, _clipY, s1 - s0, _clipH);
                    if (was[j] >= 0) {
                        glyph(dc, was[j], x + p * step, color);
                    }
                    if (i >= 0) {
                        glyph(dc, i, x + (p - 1.0) * step, color);
                    }
                    dc.setClip(0, _clipY, _w, _clipH);
                }
            }
            x = x1 + GAP * _sx;
        }
    }

    // One character, its left at x: the fills in colour, then the cuts in black
    private function glyph(dc as Dc, i as Number, x as Float, color as Number) as Void {
        count++;
        var t = _table[i];
        var size = t.size();
        var fills = 1 + t[0] * 4;
        var left = (x + 0.5).toNumber();
        var top = _topPx;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var s = Digits.slant(i);
        if (s != null) {
            var pts = new [4] as Array<[Numeric, Numeric]>;
            for (var n = 0; n < 4; n++) {
                pts[n] = [left + s[n * 2] * _sx, top + s[n * 2 + 1] * _sy];
            }
            dc.fillPolygon(pts);
        }
        var at = 1;
        while (at < fills) {
            dc.fillRectangle(left + t[at], top + t[at + 1], t[at + 2], t[at + 3]);
            at += 4;
        }
        if (at < size) {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            while (at < size) {
                dc.fillRectangle(left + t[at], top + t[at + 1], t[at + 2], t[at + 3]);
                at += 4;
            }
        }
    }

    // ------------------------------------------------------------ standby

    // `text` centred on cx as outlines a pixel wide, shifted by (ox, oy):
    // each fill's edges, each cut's edges that lie inside the block, then the
    // inside of each cut in black, which also takes the block's edge away
    // across an opening (as LockupRow.outline, upright only)
    function outline(dc as Dc, text as String, cx as Float, color as Number, ox as Number, oy as Number) as Void {
        var chars = text.toCharArray();
        var x = cx - widthOf(chars) * _sx / 2.0;
        for (var j = 0; j < chars.size(); j++) {
            var i = Digits.index(chars[j]);
            if (i >= 0) {
                hollow(dc, i, x, color, ox, oy);
            }
            x += (((i < 0) ? UNKNOWN : Digits.BLACK[i][0]) + GAP) * _sx;
        }
    }

    private function hollow(dc as Dc, i as Number, x as Float, color as Number, ox as Number, oy as Number) as Void {
        count++;
        var g = Digits.BLACK[i];
        var w = g[0];
        var first = 2 + g[1] * 4;
        var size = g.size();
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var s = Digits.slant(i);
        if (s != null) {
            for (var n = 0; n < 4; n++) {
                var a = n * 2, b = ((n + 1) % 4) * 2;
                dc.drawLine(x + s[a] * _sx + ox, _top + s[a + 1] * _sy + oy, x + s[b] * _sx + ox, _top + s[b + 1] * _sy + oy);
            }
        }
        var at = 2;
        while (at < size) {
            frame(dc, x, g[at], g[at + 1], g[at + 2], g[at + 3], at >= first, w, ox, oy);
            at += 4;
        }
        if (first < size) {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            at = first;
            while (at < size) {
                inside(dc, x, g[at], g[at + 1], g[at + 2], g[at + 3], w, ox, oy);
                at += 4;
            }
        }
    }

    // A rectangle's four edges; a cut's are kept to the block, leaving out any on its rim
    private function frame(dc as Dc, x as Float, u0 as Number, v0 as Number, u1 as Number, v1 as Number, cut as Boolean, w as Number,
                           ox as Number, oy as Number) as Void {
        var a = (u0 < 0) ? 0 : u0, b = (u1 > w) ? w : u1, t = (v0 < 0) ? 0 : v0, m = (v1 > 1000) ? 1000 : v1;
        var x0 = x + a * _sx + ox, x1 = x + b * _sx + ox, y0 = _top + t * _sy + oy, y1 = _top + m * _sy + oy;
        if (!cut || t > 0) {
            dc.drawLine(x0, y0, x1, y0);
        }
        if (!cut || m < 1000) {
            dc.drawLine(x0, y1, x1, y1);
        }
        if (!cut || a > 0) {
            dc.drawLine(x0, y0, x0, y1);
        }
        if (!cut || b < w) {
            dc.drawLine(x1, y0, x1, y1);
        }
    }

    // A cut's inside, a pixel or so in from its own edges, out past the block's rim
    private function inside(dc as Dc, x as Float, u0 as Number, v0 as Number, u1 as Number, v1 as Number, w as Number,
                            ox as Number, oy as Number) as Void {
        var a = (u0 < 0) ? 0 : u0, b = (u1 > w) ? w : u1, t = (v0 < 0) ? 0 : v0, m = (v1 > 1000) ? 1000 : v1;
        var d0 = (u0 <= 0 ? -1.5 : 1.5) + ox, d1 = (u1 >= w ? 1.5 : -1.5) + ox;
        var dt = (v0 <= 0 ? -1.5 : 1.5) + oy, db = (v1 >= 1000 ? 1.5 : -1.5) + oy;
        var x0 = x + a * _sx + d0, y0 = _top + t * _sy + dt;
        var wide = x + b * _sx + d1 - x0, tall = _top + m * _sy + db - y0;
        if (wide >= 1.0 && tall >= 1.0) {             // a small cut on a small screen: its edges alone
            dc.fillRectangle(x0, y0, wide, tall);
        }
    }
}
