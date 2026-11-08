import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

// One reading on one row of Lockup. A row's width runs from a fixed edge or
// from the bezel, and its height never changes: the digits narrow or widen
// to fill it. The digits are upright; only those nearest the bezel bend, the
// row's ends following the circle on every scanline.
//
// The watchdog is the limit here, so this is written for few calls: upright
// parts are plain rectangles, only bending ones polygons, an edge's bend is
// worked out once and not per point, and nothing is allocated per digit.
class LockupRow {

    const MARGIN = 0.012;     // from the bezel, all round
    const GAP = 0.010;        // between digits
    const SIDE = 5;           // points down each bending edge

    var key as Number;        // which reading (LockupView's values)
    var y0 as Float;
    var y1 as Float;
    var lx as Float;          // the fixed left edge, or below 0 for the bezel
    var rx as Float;          // the fixed right edge, or below 0 for the bezel
    var bend as Float;        // the share of the row, from each bezel end, that bends
    var least as Float;       // the least room, in digit widths, so one digit doesn't balloon
    var color as Number = 0;
    var alpha as Float = 1.0;
    var type as Complications.Type?;
    var dirty as Boolean = true;
    private var _table as Array<Array<Number>>;

    // Shared while a row draws
    private var _w as Float = 454.0;
    private var _xlm as Float = 0.0;
    private var _xrm as Float = 0.0;
    private var _wm as Float = 1.0;
    private var _base as Float = 0.0;
    private var _us as Float = 0.0;
    private var _dy as Float = 0.0;
    private var _pts as Array<[Numeric, Numeric]>;

    function initialize(key_ as Number, black as Boolean, lx_ as Float, rx_ as Float, y0_ as Float, y1_ as Float,
                        bend_ as Float, least_ as Float, type_ as Complications.Type?) {
        key = key_;
        lx = lx_;
        rx = rx_;
        y0 = y0_;
        y1 = y1_;
        bend = bend_;
        least = least_;
        type = type_;
        _table = black ? Digits.BLACK : Digits.REGULAR;
        _dy = (y1_ - y0_) / 1000.0;
        _pts = new [SIDE * 2] as Array<[Numeric, Numeric]>;
        for (var i = 0; i < SIDE * 2; i++) {
            _pts[i] = [0.0, 0.0];
        }
    }

    // The circle's half width at y, inside the margin
    function halfAt(y as Float) as Float {
        var r = 0.5 - MARGIN;
        var d = r * r - (y - 0.5) * (y - 0.5);
        return (d <= 0.0) ? 0.0 : Math.sqrt(d).toFloat();
    }

    private function prepare(w as Float) as Void {
        _w = w;
        var h = halfAt((y0 + y1) / 2.0);
        _xlm = (lx < 0.0) ? 0.5 - h : lx;
        _xrm = (rx < 0.0) ? 0.5 + h : rx;
        _wm = _xrm - _xlm;
    }

    // The row's rectangle on screen, for clearing and for a press and hold
    function left(w as Number) as Number {
        return (lx < 0.0) ? 0 : (lx * w).toNumber();
    }

    function right(w as Number) as Number {
        return (rx < 0.0) ? w : (rx * w + 0.999).toNumber();
    }

    function top(w as Number) as Number {
        return (y0 * w).toNumber();
    }

    function bottom(w as Number) as Number {
        return (y1 * w + 0.999).toNumber();
    }

    function contains(x as Number, y as Number, w as Number) as Boolean {
        return x >= left(w) && x <= right(w) && y >= top(w) && y <= bottom(w);
    }

    // Each character's place in the tables, and the scale from thousandths
    // of a block's width to the row's width, the slack shared when text is short
    private function fit(chars as Array<Char>, indexes as Array<Number>) as [Float, Float] {
        var cw = 0;
        for (var j = 0; j < chars.size(); j++) {
            var i = Digits.index(chars[j]);
            indexes[j] = i;
            cw += (i < 0) ? 250 : _table[i][0];
        }
        var room = 1.0 - (GAP * (chars.size() - 1)) / _wm;
        var units = (cw > least * 1000.0) ? cw.toFloat() : least * 1000.0;
        var k = room / units;
        return [k, (units - cw) * k / 2.0];
    }

    // Draws the text, clearing the row first. With `from` and `p`, the digits
    // that differ roll: the old up and out, the new up from below.
    function draw(dc as Dc, text as String, from as String?, p as Float, shade as Number) as Void {
        var w = dc.getWidth();
        prepare(w.toFloat());
        var x = left(w), y = top(w), wide = right(w) - x, tall = bottom(w) - y;
        dc.setClip(x, y, wide, tall);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(x, y, wide, tall);
        var chars = text.toCharArray();
        var indexes = new [chars.size()] as Array<Number>;
        var old = (from != null && from.length() == text.length()) ? from.toCharArray() : null;
        var f = fit(chars, indexes);
        var k = f[0];
        var u = f[1];
        var gap = GAP / _wm;
        for (var j = 0; j < chars.size(); j++) {
            var i = indexes[j];
            var gw = ((i < 0) ? 250 : _table[i][0]) * k;
            if (i >= 0) {
                if (old != null && old[j] != chars[j]) {
                    var was = Digits.index(old[j]);
                    if (was >= 0) {
                        glyph(dc, was, u, gw, shade, -p * 1060.0);
                    }
                    glyph(dc, i, u, gw, shade, (1.0 - p) * 1060.0);
                } else {
                    glyph(dc, i, u, gw, shade, 0.0);
                }
            }
            u += gw + gap;
        }
        dc.clearClip();
    }

    private function glyph(dc as Dc, i as Number, base as Float, gw as Float, shade as Number, off as Float) as Void {
        var g = _table[i];
        _base = base;
        _us = gw / g[0];
        var size = g.size();
        var fillsEnd = 2 + g[1] * 4;
        dc.setColor(shade, Graphics.COLOR_TRANSPARENT);
        var slant = Digits.slant(i);
        if (slant != null) {
            slash(dc, slant, off);
        }
        var at = 2;
        while (at < fillsEnd) {
            rect(dc, g[at], g[at + 1], g[at + 2], g[at + 3], off);
            at += 4;
        }
        if (at < size) {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            while (at < size) {
                rect(dc, g[at], g[at + 1], g[at + 2], g[at + 3], off);
                at += 4;
            }
        }
    }

    // How far a point `uu` across the row follows the bezel on its left
    private function leftPull(uu as Float) as Numeric {
        if (lx >= 0.0 || uu >= bend) {
            return 0.0;
        }
        var f = 1.0 - uu / bend;
        return f * Math.sqrt(f);
    }

    // And on its right
    private function rightPull(uu as Float) as Numeric {
        if (rx >= 0.0 || uu <= 1.0 - bend) {
            return 0.0;
        }
        var f = 1.0 - (1.0 - uu) / bend;
        return f * Math.sqrt(f);
    }

    private function rect(dc as Dc, u0 as Number, v0 as Number, u1 as Number, v1 as Number, off as Float) as Void {
        var ua = _base + u0 * _us;
        var ub = _base + u1 * _us;
        var w = _w;
        var ya = y0 + (v0 + off) * _dy;
        var yb = y0 + (v1 + off) * _dy;
        var xa = _xlm + ua * _wm;
        var xb = _xlm + ub * _wm;
        if ((lx >= 0.0 || ua >= bend) && (rx >= 0.0 || ub <= 1.0 - bend)) {
            var x0 = (xa * w + 0.5).toNumber();
            var t = (ya * w + 0.5).toNumber();
            dc.fillRectangle(x0, t, (xb * w + 0.5).toNumber() - x0, (yb * w + 0.5).toNumber() - t);
            return;
        }
        polygon(dc, xa, xb, ya, yb, leftPull(ua), rightPull(ua), leftPull(ub), rightPull(ub), 0.0, 0.0, 0.0, 0.0, 0.0);
    }

    // A rectangle with its two upright edges following the bezel, nudged by
    // (dl, dr) on its sides, (dt, db) at its top and bottom and dm between, in pixels
    private function polygon(dc as Dc, xa as Float, xb as Float, ya as Float, yb as Float, al as Numeric, ar as Numeric, bl as Numeric, br as Numeric,
                             dl as Numeric, dr as Numeric, dt as Numeric, db as Numeric, dm as Numeric) as Void {
        var w = _w, pts = _pts, r2 = (0.5 - MARGIN) * (0.5 - MARGIN), step = (yb - ya) / (SIDE - 1);
        var last = SIDE * 2 - 1, xlm = _xlm, xrm = _xrm;
        for (var n = 0; n < SIDE; n++) {
            var y = ya + step * n;
            var c = (y < y0) ? y0 : ((y > y1) ? y1 : y);
            var d = r2 - (c - 0.5) * (c - 0.5);
            var h = (d <= 0.0) ? 0.0 : Math.sqrt(d);
            var pl = 0.5 - h - xlm, pr = 0.5 + h - xrm;
            var nudge = (n == 0) ? dt : ((n == SIDE - 1) ? db : dm);
            var p = pts[n];
            p[0] = (xa + pl * al + pr * ar) * w + dl;
            p[1] = y * w + nudge;
            p = pts[last - n];
            p[0] = (xb + pl * bl + pr * br) * w + dr;
            p[1] = y * w + nudge;
        }
        dc.fillPolygon(pts);
    }

    private function slash(dc as Dc, s as Array<Number>, off as Float) as Void {
        var pts = new [4] as Array<[Numeric, Numeric]>;
        for (var n = 0; n < 4; n++) {
            pts[n] = point(_base + s[n * 2] * _us, y0 + (s[n * 2 + 1] + off) * _dy, 0, 0);
        }
        dc.fillPolygon(pts);
    }

    // A point `uu` across the row at height y, in pixels
    private function point(uu as Float, y as Float, ox as Number, oy as Number) as [Numeric, Numeric] {
        var c = (y < y0) ? y0 : ((y > y1) ? y1 : y);
        var h = halfAt(c);
        var x = _xlm + uu * _wm + (0.5 - h - _xlm) * leftPull(uu) + (0.5 + h - _xrm) * rightPull(uu);
        return [x * _w + ox, y * _w + oy];
    }

    // ------------------------------------------------------------ standby

    // The text as thin outlines, shifted by (ox, oy): each fill's edges, each
    // cut's edges that lie inside the block, then the inside of each cut in
    // black, which also takes the block's edge away across an opening
    function outline(dc as Dc, text as String, shade as Number, ox as Number, oy as Number) as Void {
        prepare(dc.getWidth().toFloat());
        var chars = text.toCharArray();
        var indexes = new [chars.size()] as Array<Number>;
        var f = fit(chars, indexes);
        var k = f[0];
        var u = f[1];
        var gap = GAP / _wm;
        for (var j = 0; j < chars.size(); j++) {
            var i = indexes[j];
            var gw = ((i < 0) ? 250 : _table[i][0]) * k;
            if (i >= 0) {
                _base = u;
                _us = gw / _table[i][0];
                hollow(dc, i, shade, ox, oy);
            }
            u += gw + gap;
        }
    }

    private function hollow(dc as Dc, i as Number, shade as Number, ox as Number, oy as Number) as Void {
        var g = _table[i];
        var w = g[0];
        var first = 2 + g[1] * 4;
        var size = g.size();
        dc.setColor(shade, Graphics.COLOR_TRANSPARENT);
        var s = Digits.slant(i);
        if (s != null) {
            for (var n = 0; n < 4; n++) {
                var a = n * 2, b = ((n + 1) % 4) * 2;
                var p = point(_base + s[a] * _us, y0 + s[a + 1] * _dy, ox, oy);
                var q = point(_base + s[b] * _us, y0 + s[b + 1] * _dy, ox, oy);
                dc.drawLine(p[0], p[1], q[0], q[1]);
            }
        }
        var at = 2;
        while (at < first) {
            frame(dc, g[at], g[at + 1], g[at + 2], g[at + 3], false, w, ox, oy);
            at += 4;
        }
        while (at < size) {
            frame(dc, g[at], g[at + 1], g[at + 2], g[at + 3], true, w, ox, oy);
            at += 4;
        }
        if (first < size) {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            at = first;
            while (at < size) {
                inside(dc, g[at], g[at + 1], g[at + 2], g[at + 3], w, ox, oy);
                at += 4;
            }
        }
    }

    // A rectangle's four edges; a cut's are kept to the block, leaving out any on its rim
    private function frame(dc as Dc, u0 as Number, v0 as Number, u1 as Number, v1 as Number, cut as Boolean, w as Number,
                           ox as Number, oy as Number) as Void {
        var a = (u0 < 0) ? 0 : u0, b = (u1 > w) ? w : u1, t = (v0 < 0) ? 0 : v0, m = (v1 > 1000) ? 1000 : v1;
        var ua = _base + a * _us, ub = _base + b * _us;
        var ya = y0 + t * _dy, yb = y0 + m * _dy;
        var sw = _w;
        var upright = (lx >= 0.0 || ua >= bend) && (rx >= 0.0 || ub <= 1.0 - bend);
        var xa = _xlm + ua * _wm, xb = _xlm + ub * _wm;
        if (upright) {
            var x0 = xa * sw + ox, x1 = xb * sw + ox, y2 = ya * sw + oy, y3 = yb * sw + oy;
            if (!cut || t > 0) {
                dc.drawLine(x0, y2, x1, y2);
            }
            if (!cut || m < 1000) {
                dc.drawLine(x0, y3, x1, y3);
            }
            if (!cut || a > 0) {
                dc.drawLine(x0, y2, x0, y3);
            }
            if (!cut || b < w) {
                dc.drawLine(x1, y2, x1, y3);
            }
            return;
        }
        var al = leftPull(ua), ar = rightPull(ua), bl = leftPull(ub), br = rightPull(ub);
        var r2 = (0.5 - MARGIN) * (0.5 - MARGIN), step = (yb - ya) / (SIDE - 1), xlm = _xlm, xrm = _xrm;
        var showLeft = !cut || a > 0, showRight = !cut || b < w;
        var lastL = 0.0, lastR = 0.0, lastY = 0.0;
        for (var n = 0; n < SIDE; n++) {
            var y = ya + step * n;
            var d = r2 - (y - 0.5) * (y - 0.5);
            var h = (d <= 0.0) ? 0.0 : Math.sqrt(d);
            var pl = 0.5 - h - xlm, pr = 0.5 + h - xrm;
            var xl = (xa + pl * al + pr * ar) * sw + ox;
            var xr = (xb + pl * bl + pr * br) * sw + ox;
            var yy = y * sw + oy;
            if (n == 0 && (!cut || t > 0)) {
                dc.drawLine(xl, yy, xr, yy);
            }
            if (n == SIDE - 1 && (!cut || m < 1000)) {
                dc.drawLine(xl, yy, xr, yy);
            }
            if (n > 0) {
                if (showLeft) {
                    dc.drawLine(lastL, lastY, xl, yy);
                }
                if (showRight) {
                    dc.drawLine(lastR, lastY, xr, yy);
                }
            }
            lastL = xl;
            lastR = xr;
            lastY = yy;
        }
    }

    // A cut's inside, a pixel or so in from its own edges, out past the block's rim
    private function inside(dc as Dc, u0 as Number, v0 as Number, u1 as Number, v1 as Number, w as Number,
                            ox as Number, oy as Number) as Void {
        var a = (u0 < 0) ? 0 : u0, b = (u1 > w) ? w : u1, t = (v0 < 0) ? 0 : v0, m = (v1 > 1000) ? 1000 : v1;
        var ua = _base + a * _us, ub = _base + b * _us;
        var ya = y0 + t * _dy, yb = y0 + m * _dy;
        var d0 = (u0 <= 0 ? -1.5 : 1.5) + ox, d1 = (u1 >= w ? 1.5 : -1.5) + ox;
        var dt = (v0 <= 0 ? -1.5 : 1.5) + oy, db = (v1 >= 1000 ? 1.5 : -1.5) + oy;
        var xa = _xlm + ua * _wm, xb = _xlm + ub * _wm;
        if ((lx >= 0.0 || ua >= bend) && (rx >= 0.0 || ub <= 1.0 - bend)) {
            var x0 = xa * _w + d0, y2 = ya * _w + dt;
            dc.fillRectangle(x0, y2, xb * _w + d1 - x0, yb * _w + db - y2);
            return;
        }
        // A slanting edge needs more room, or the black eats into its line
        d0 = (u0 <= 0 ? -2.5 : 2.5) + ox;
        d1 = (u1 >= w ? 2.5 : -2.5) + ox;
        polygon(dc, xa, xb, ya, yb, leftPull(ua), rightPull(ua), leftPull(ub), rightPull(ub), d0, d1, dt, db, oy);
    }
}
