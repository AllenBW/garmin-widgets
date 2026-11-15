import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

// A band's text laid out: each character's place in the tables, its reading,
// its left edge and width in thousandths of the band's height, and the
// angle per unit that spreads the whole across the band's span
class OrbRun {
    var idx as Array<Number>;
    var seg as Array<Number>;
    var u as Array<Number>;
    var gw as Array<Number>;
    var n as Number;
    var k as Float = 0.0;       // radians per unit
    var base as Float = 0.0;    // the angle at u = 0

    function initialize(size as Number) {
        n = size;
        idx = new [size] as Array<Number>;
        seg = new [size] as Array<Number>;
        u = new [size] as Array<Number>;
        gw = new [size] as Array<Number>;
    }
}

// One band of Orb: Lockup's row printed round a globe. Its readings sit side
// by side across an angle of +-1.25 rad about the globe's vertical axis,
// projected orthographically, x = 0.5 + half(y) sin(angle), so the ends
// crowd toward the limb and every edge follows the circle; each digit dims
// toward the limb with cos(angle). The band turns about that axis (the old
// text going round the back as the new comes to the front), or a digit
// turns in its own slot like a small globe (a drum).
//
// Written for few calls, as Lockup's rows are: every part is a polygon here,
// but an upright edge takes only as many points as its curve needs (two at
// the middle of the globe, five at the limb), a rectangle's two sides share
// their square roots, and nothing is allocated per digit.
class OrbBand {

    const MARGIN = 0.012;     // from the bezel, all round (Lockup's)
    const A = 1.25;           // the band's half span, radians
    const B = 1.15;           // a drum's half span, in its own radians
    const SIN_B = 0.9128;     // sin(B)
    const GAP = 120;          // between digits, thousandths of the height
    const SEG = 500;          // between readings
    const FRONT = 0.03;       // a digit whose centre's cosine is below this is round the back
    const HALF_PI = 1.5707963;
    const TWO_PI = 6.2831853;

    var y0 as Float;
    var y1 as Float;
    var keys as Array<Number>;
    var types as Array<Complications.Type?>;
    var dirty as Boolean = true;
    var mode as Number = OrbMoves.NONE;
    var start as Number = 0;            // the motion clock's ms when the motion begins
    var dur as Number = 0;              // a turn's ms
    var polys as Number = 0;            // polygons drawn, counted for the budget

    private var _black as Array<Boolean>;
    private var _colors as Array<Number>;
    private var _least as Number = 0;
    private var _texts as Array<String>;
    private var _run as OrbRun;
    private var _old as OrbRun? = null;
    private var _delays as Array<Number>? = null;   // drums: per character, ms after start, -1 still, -2 landed
    private var _fresh as Boolean = false;          // drums: the next frame draws the band whole first

    // While drawing
    private var _w as Float = 454.0;
    private var _r2 as Float = 0.238;
    private var _dy as Float = 0.0;
    private var _curve as Float = 0.0;   // px an upright edge bows at the limb over the band's height, at most
    private var _top as Number = 0;
    private var _tall as Number = 0;
    private var _rk as Float = 0.0;      // the run being drawn: radians per unit, base angle
    private var _rb as Float = 0.0;
    private var _off as Float = 0.0;     // its offset round the globe and the band's turn
    private var _rot as Float = 0.0;
    private var _iu as Float = 0.0;      // the character's left edge
    private var _drum as Boolean = false;
    private var _cu as Float = 0.0;      // a drum's centre, half width, own offset and turn, and how flat it is
    private var _half as Float = 0.0;
    private var _dOff as Float = 0.0;
    private var _dRot as Float = 0.0;
    private var _fw as Float = 1.0;
    private var _ownW as Float = 1000.0;
    private var _pts as Array<Array<[Numeric, Numeric]>>;
    private var _quad as Array<[Numeric, Numeric]>;

    // `black` the weight of each reading, `colors` its colour at its level,
    // `least` the room it takes at the least, as text, so a short reading
    // doesn't balloon
    function initialize(keys_ as Array<Number>, black as Array<Boolean>, colors as Array<Number>, least as Array<String>,
                        y0_ as Float, y1_ as Float, types_ as Array<Complications.Type?>) {
        keys = keys_;
        types = types_;
        _black = black;
        _colors = colors;
        y0 = y0_;
        y1 = y1_;
        _dy = (y1_ - y0_) / 1000.0;
        _texts = least;
        _run = layout(least);
        var l = _run.u[_run.n - 1] + _run.gw[_run.n - 1];
        _least = l;
        _run = layout(least);
        _pts = new [5] as Array<Array<[Numeric, Numeric]>>;
        for (var s = 1; s <= 4; s++) {
            var a = new [2 * (s + 1)] as Array<[Numeric, Numeric]>;
            for (var i = 0; i < a.size(); i++) {
                a[i] = [0.0, 0.0];
            }
            _pts[s] = a;
        }
        _pts[0] = _pts[1];
        _quad = [[0.0, 0.0], [0.0, 0.0], [0.0, 0.0], [0.0, 0.0]] as Array<[Numeric, Numeric]>;
    }

    function setColors(colors as Array<Number>) as Void {
        _colors = colors;
        dirty = true;
    }

    // ------------------------------------------------------------ layout

    private function layout(texts as Array<String>) as OrbRun {
        var count = 0;
        for (var s = 0; s < texts.size(); s++) {
            count += texts[s].length();
        }
        var run = new OrbRun(count);
        var u = 0;
        var at = 0;
        for (var s = 0; s < texts.size(); s++) {
            var table = _black[s] ? Digits.BLACK : Digits.REGULAR;
            var chars = texts[s].toCharArray();
            if (s > 0 && chars.size() > 0) {
                u += SEG;
            }
            for (var c = 0; c < chars.size(); c++) {
                if (c > 0) {
                    u += GAP;
                }
                var i = Digits.index(chars[c]);
                var w = (i < 0) ? 250 : table[i][0];
                run.idx[at] = i;
                run.seg[at] = s;
                run.u[at] = u;
                run.gw[at] = w;
                at++;
                u += w;
            }
        }
        var room = (u > _least) ? u : _least;
        if (room <= 0) {
            room = 1000;
        }
        run.k = 2.0 * A / room;
        run.base = -A + (room - u) / 2.0 * run.k;
        return run;
    }

    // The readings now: laid out afresh, any motion dropped
    function set(texts as Array<String>) as Void {
        _texts = texts;
        _run = layout(texts);
        _old = null;
        _delays = null;
        mode = OrbMoves.NONE;
        dirty = true;
    }

    function texts() as Array<String> {
        return _texts;
    }

    // From `old` to `now`, from `at` on the motion clock: a turn of the band
    // (`turnAfter` ms later, taking `turnMs`), drums for the changed digits
    // (`drumAfter` ms later, `drumStep` between them), or a plain change.
    // `turns` allows the band's turn.
    function plan(old as Array<String>, now as Array<String>, turns as Boolean, at as Number, turnAfter as Number,
                  turnMs as Number, drumAfter as Number, drumStep as Number) as Void {
        var m = OrbMoves.mode(old, now, turns);
        set(now);
        if (m == OrbMoves.NONE || m == OrbMoves.SNAP) {
            return;
        }
        mode = m;
        start = at + ((m == OrbMoves.TURN) ? turnAfter : drumAfter);
        dur = turnMs;
        _old = layout(old);
        if (m == OrbMoves.DRUMS) {
            _delays = OrbMoves.delays(OrbMoves.changed(old, now), drumStep);
            _fresh = true;
        }
    }

    // The bitmap was made anew: a drum's next frame draws the band whole
    function invalidate() as Void {
        dirty = true;
        _fresh = true;
    }

    // A rough count of the polygons the next draw takes, for the budget
    function cost() as Number {
        if (mode == OrbMoves.DRUMS && !_fresh) {
            var d = _delays as Array<Number>;
            var c = 0;
            for (var i = 0; i < d.size(); i++) {
                if (d[i] >= 0) {
                    c += 4;
                }
            }
            return c;
        }
        return _run.n * 3 + ((mode == OrbMoves.TURN) ? _run.n : 0);
    }

    // For the tests: what moves, "turn", or a mark per character for a drum
    function moving() as String {
        if (mode == OrbMoves.TURN) {
            return "turn";
        }
        if (mode != OrbMoves.DRUMS) {
            return "";
        }
        var d = _delays as Array<Number>;
        var s = "";
        for (var i = 0; i < d.size(); i++) {
            s += (d[i] >= 0) ? "x" : ".";
        }
        return s;
    }

    // ------------------------------------------------------------ drawing

    private function prepare(dc as Dc) as Void {
        var w = dc.getWidth();
        _w = w.toFloat();
        var r = 0.5 - MARGIN;
        _r2 = r * r;
        // The most an upright edge bows from straight over the band's height:
        // the circle's half width curves most where it is narrowest
        var far = (y0 - 0.5).abs() > (y1 - 0.5).abs() ? y0 : y1;
        var h = halfAt(far);
        if (h < 0.05) {
            h = 0.05;
        }
        _curve = _r2 / (h * h * h) / 8.0 * (y1 - y0) * (y1 - y0) * _w;
        _top = (y0 * _w).toNumber();
        _tall = (y1 * _w + 0.999).toNumber() - _top;
        polys = 0;
    }

    function halfAt(y as Float) as Float {
        var d = _r2 - (y - 0.5) * (y - 0.5);
        return (d <= 0.0) ? 0.0 : Math.sqrt(d).toFloat();
    }

    private function clear(dc as Dc) as Void {
        var w = _w.toNumber();
        dc.setClip(0, _top, w, _tall);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(0, _top, w, _tall);
    }

    // The band at rest, cleared first
    function draw(dc as Dc) as Void {
        prepare(dc);
        clear(dc);
        drawRun(dc, _run, 0.0, 0.0);
        dc.clearClip();
        dirty = false;
    }

    // A frame of the motion at `t` on the motion clock; false once it has
    // landed (and the band is drawn at rest)
    function frame(dc as Dc, t as Number, drumMs as Number) as Boolean {
        if (mode == OrbMoves.TURN) {
            var e = t - start;
            if (Lib.Motion.done(e, dur)) {
                set(_texts);
                draw(dc);
                return false;
            }
            var rot = Math.PI * Lib.Motion.ease(e, dur, false, 0.03);
            prepare(dc);
            clear(dc);
            drawRun(dc, _old as OrbRun, 0.0, rot.toFloat());
            drawRun(dc, _run, Math.PI.toFloat(), rot.toFloat());
            dc.clearClip();
            dirty = false;
            return true;
        }
        if (mode == OrbMoves.DRUMS) {
            return drums(dc, t, drumMs);
        }
        if (dirty) {
            draw(dc);
        }
        return false;
    }

    private function drums(dc as Dc, t as Number, drumMs as Number) as Boolean {
        var d = _delays as Array<Number>;
        var old = _old as OrbRun;
        prepare(dc);
        var whole = _fresh || dirty;
        if (whole) {
            clear(dc);
        } else {
            dc.setClip(0, _top, _w.toNumber(), _tall);
        }
        var busy = false;
        for (var i = 0; i < _run.n; i++) {
            var delay = d[i];
            if (delay == -1) {
                if (whole) {
                    still(dc, i);
                }
                continue;
            }
            if (delay == -2) {
                if (whole) {
                    still(dc, i);
                }
                continue;
            }
            var e = t - start - delay;
            if (!whole) {
                slot(dc, i);
            }
            if (Lib.Motion.done(e, drumMs)) {
                d[i] = -2;
                still(dc, i);
                continue;
            }
            busy = true;
            drum(dc, i, old.idx[i], Math.PI * Lib.Motion.ease(e, drumMs, false, 0.04));
        }
        dc.clearClip();
        _fresh = false;
        dirty = false;
        if (!busy) {
            set(_texts);
            dirty = false;
        }
        return busy;
    }

    // One character at rest
    private function still(dc as Dc, i as Number) as Void {
        _drum = false;
        _off = 0.0;
        _rot = 0.0;
        _rk = _run.k;
        _rb = _run.base;
        var a = centre(_run, i);
        var c = Math.cos(a);
        if (c > FRONT) {
            _iu = _run.u[i].toFloat();
            glyph(dc, _run.idx[i], _run.seg[i], shade(c));
        }
    }

    // A drum's slot cleared, half a gap either side
    private function slot(dc as Dc, i as Number) as Void {
        _drum = false;
        _off = 0.0;
        _rot = 0.0;
        _rk = _run.k;
        _rb = _run.base;
        _iu = _run.u[i].toFloat();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        rect(dc, -GAP / 2, 0, _run.gw[i] + GAP / 2, 1000);
    }

    // Character i as a small globe turned `rot` of the way from the old face
    // to the new: each face mapped round the drum, flat when it faces front
    private function drum(dc as Dc, i as Number, was as Number, rot as Numeric) as Void {
        _rk = _run.k;
        _rb = _run.base;
        _off = 0.0;
        _rot = 0.0;
        var c = Math.cos(centre(_run, i));
        if (c <= FRONT) {
            return;
        }
        var base = shade(c);
        var gw = _run.gw[i];
        _cu = _run.u[i] + gw / 2.0;
        _half = gw / 2.0;
        _dRot = rot.toFloat();
        _drum = true;
        for (var f = 0; f < 2; f++) {
            var ch = (f == 0) ? was : _run.idx[i];
            _dOff = (f == 0) ? 0.0 : Math.PI.toFloat();
            var face = Math.cos(_dOff - _dRot);
            if (face <= FRONT || ch < 0) {
                continue;
            }
            _fw = (face * face).toFloat();
            var table = _black[_run.seg[i]] ? Digits.BLACK : Digits.REGULAR;
            _ownW = table[ch][0].toFloat();
            glyph(dc, ch, _run.seg[i], base * (0.25 + 0.75 * Math.pow(face, 0.7)));
        }
        _drum = false;
    }

    // Every character of a run turned `rot` from `off` round the globe
    private function drawRun(dc as Dc, run as OrbRun, off as Float, rot as Float) as Void {
        _drum = false;
        _rk = run.k;
        _rb = run.base;
        _off = off;
        _rot = rot;
        for (var i = 0; i < run.n; i++) {
            var c = Math.cos(centre(run, i));
            if (c <= FRONT || run.idx[i] < 0) {
                continue;
            }
            _iu = run.u[i].toFloat();
            glyph(dc, run.idx[i], run.seg[i], shade(c));
        }
    }

    private function centre(run as OrbRun, i as Number) as Float {
        return wrap(run.base + (run.u[i] + run.gw[i] / 2.0) * run.k + _off - _rot);
    }

    private function wrap(a as Float) as Float {
        while (a > Math.PI) {
            a -= TWO_PI;
        }
        while (a < -Math.PI) {
            a += TWO_PI;
        }
        return a;
    }

    // The limb's dimming, from the cosine of the angle
    private function shade(c as Numeric) as Float {
        return (0.22 + 0.78 * Math.pow(c, 0.7)).toFloat();
    }

    private function glyph(dc as Dc, i as Number, seg as Number, light as Numeric) as Void {
        if (i < 0) {
            return;
        }
        var g = (_black[seg] ? Digits.BLACK : Digits.REGULAR)[i];
        var size = g.size();
        var fillsEnd = 2 + g[1] * 4;
        dc.setColor(Lib.Numbers.scale(_colors[seg], light.toFloat()), Graphics.COLOR_TRANSPARENT);
        var s = Digits.slant(i);
        if (s != null) {
            for (var n = 0; n < 4; n++) {
                var y = y0 + s[n * 2 + 1] * _dy;
                var p = _quad[n];
                p[0] = (0.5 + halfAt(y) * sine(s[n * 2])) * _w;
                p[1] = y * _w;
            }
            dc.fillPolygon(_quad);
            polys++;
        }
        var at = 2;
        while (at < fillsEnd) {
            rect(dc, g[at], g[at + 1], g[at + 2], g[at + 3]);
            at += 4;
        }
        if (at < size) {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            while (at < size) {
                rect(dc, g[at], g[at + 1], g[at + 2], g[at + 3]);
                at += 4;
            }
        }
    }

    // Where a point `uu` across the character lands: the sine of its angle
    // round the globe (on a drum, round the drum first)
    private function sine(uu as Numeric) as Float {
        var a = 0.0;
        if (_drum) {
            var q = uu / _ownW - 0.5;
            var ad = wrap((2.0 * B * q + _dOff - _dRot).toFloat());
            if (ad > HALF_PI) {
                ad = HALF_PI;
            } else if (ad < -HALF_PI) {
                ad = -HALF_PI;
            }
            var m = _fw * 2.0 * q + (1.0 - _fw) * Math.sin(ad) / SIN_B;
            a = _rb + (_cu + _half * m) * _rk;
        } else {
            a = wrap((_rb + (_iu + uu) * _rk + _off - _rot).toFloat());
        }
        if (a > HALF_PI) {
            return 1.0;
        }
        if (a < -HALF_PI) {
            return -1.0;
        }
        return Math.sin(a).toFloat();
    }

    // How many straight pieces an upright edge at sine `sl` or `sr`, `dv`
    // thousandths tall, needs to stay within half a pixel of its curve: one
    // at the middle of the globe, four at the limb
    private function segments(sl as Float, sr as Float, dv as Number) as Number {
        var s = sl.abs() > sr.abs() ? sl.abs() : sr.abs();
        var f = dv / 1000.0;
        var bow = s * _curve * f * f;
        return (bow < 0.5) ? 1 : ((bow < 2.0) ? 2 : ((bow < 4.5) ? 3 : 4));
    }

    // A rectangle of the character, its upright edges following the globe,
    // with as many points as their curve needs (half a pixel off at most)
    private function rect(dc as Dc, u0 as Number, v0 as Number, u1 as Number, v1 as Number) as Void {
        var sl = sine(u0);
        var sr = sine(u1);
        var segs = segments(sl, sr, v1 - v0);
        var pts = _pts[segs];
        var last = 2 * segs + 1;
        var w = _w;
        var r2 = _r2;
        var ya = y0 + v0 * _dy;
        var step = (v1 - v0) * _dy / segs;
        for (var n = 0; n <= segs; n++) {
            var y = ya + step * n;
            var c = y - 0.5;
            var d = r2 - c * c;
            var h = (d <= 0.0) ? 0.0 : Math.sqrt(d);
            var py = y * w;
            var p = pts[n];
            p[0] = (0.5 + h * sl) * w;
            p[1] = py;
            p = pts[last - n];
            p[0] = (0.5 + h * sr) * w;
            p[1] = py;
        }
        dc.fillPolygon(pts);
        polys++;
    }

    // ------------------------------------------------------------ standby

    // The readings as thin outlines, the globe turned `rot` and shifted `oy`
    // px: each fill's edges, each cut's edges inside the block, then each
    // cut's inside in black, which takes the block's edge away across an
    // opening. Lines are a pixel wide, so no anti-aliasing to count.
    function outline(dc as Dc, texts as Array<String>, rot as Float, oy as Number) as Void {
        var run = layout(texts);
        prepare(dc);
        _drum = false;
        _rk = run.k;
        _rb = run.base;
        _off = 0.0;
        _rot = rot;
        for (var i = 0; i < run.n; i++) {
            var ch = run.idx[i];
            var c = Math.cos(centre(run, i));
            if (c <= FRONT || ch < 0) {
                continue;
            }
            _iu = run.u[i].toFloat();
            hollow(dc, ch, run.seg[i], Lib.Numbers.scale(_colors[run.seg[i]], shade(c)), oy);
        }
    }

    private function hollow(dc as Dc, i as Number, seg as Number, color as Number, oy as Number) as Void {
        var g = (_black[seg] ? Digits.BLACK : Digits.REGULAR)[i];
        var w = g[0];
        var first = 2 + g[1] * 4;
        var size = g.size();
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var s = Digits.slant(i);
        if (s != null) {
            for (var n = 0; n < 4; n++) {
                var a = n * 2, b = ((n + 1) % 4) * 2;
                var ya = y0 + s[a + 1] * _dy, yb = y0 + s[b + 1] * _dy;
                dc.drawLine((0.5 + halfAt(ya) * sine(s[a])) * _w, ya * _w + oy, (0.5 + halfAt(yb) * sine(s[b])) * _w, yb * _w + oy);
            }
        }
        var at = 2;
        while (at < first) {
            edges(dc, g[at], g[at + 1], g[at + 2], g[at + 3], false, w, oy);
            at += 4;
        }
        while (at < size) {
            edges(dc, g[at], g[at + 1], g[at + 2], g[at + 3], true, w, oy);
            at += 4;
        }
        if (first < size) {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            at = first;
            while (at < size) {
                inside(dc, g[at], g[at + 1], g[at + 2], g[at + 3], w, oy);
                at += 4;
            }
        }
    }

    // A rectangle's edges; a cut's are kept to the block, leaving out any on its rim
    private function edges(dc as Dc, u0 as Number, v0 as Number, u1 as Number, v1 as Number, cut as Boolean, w as Number,
                           oy as Number) as Void {
        var a = (u0 < 0) ? 0 : u0, b = (u1 > w) ? w : u1, t = (v0 < 0) ? 0 : v0, m = (v1 > 1000) ? 1000 : v1;
        var sl = sine(a), sr = sine(b);
        var ya = y0 + t * _dy, yb = y0 + m * _dy;
        var sw = _w;
        if (!cut || t > 0) {
            var h = halfAt(ya);
            dc.drawLine((0.5 + h * sl) * sw, ya * sw + oy, (0.5 + h * sr) * sw, ya * sw + oy);
        }
        if (!cut || m < 1000) {
            var h = halfAt(yb);
            dc.drawLine((0.5 + h * sl) * sw, yb * sw + oy, (0.5 + h * sr) * sw, yb * sw + oy);
        }
        var left = !cut || a > 0, right = !cut || b < w;
        if (!left && !right) {
            return;
        }
        var segs = segments(sl, sr, m - t);
        var step = (yb - ya) / segs;
        var lastL = 0.0, lastR = 0.0, lastY = 0.0;
        for (var n = 0; n <= segs; n++) {
            var y = ya + step * n;
            var h = halfAt(y);
            var xl = (0.5 + h * sl) * sw, xr = (0.5 + h * sr) * sw, yy = y * sw + oy;
            if (n > 0) {
                if (left) {
                    dc.drawLine(lastL, lastY, xl, yy);
                }
                if (right) {
                    dc.drawLine(lastR, lastY, xr, yy);
                }
            }
            lastL = xl;
            lastR = xr;
            lastY = yy;
        }
    }

    // A cut's inside, a pixel and a half in from its own edges, out past the block's rim
    private function inside(dc as Dc, u0 as Number, v0 as Number, u1 as Number, v1 as Number, w as Number, oy as Number) as Void {
        var a = (u0 < 0) ? 0 : u0, b = (u1 > w) ? w : u1, t = (v0 < 0) ? 0 : v0, m = (v1 > 1000) ? 1000 : v1;
        var dl = (u0 <= 0) ? -1.5 : 1.5, dr = (u1 >= w) ? 1.5 : -1.5;
        var dt = (v0 <= 0) ? -1.5 : 1.5, db = (v1 >= 1000) ? 1.5 : -1.5;
        var sl = sine(a), sr = sine(b);
        var segs = segments(sl, sr, m - t);
        var ya = y0 + t * _dy, step = (m - t) * _dy / segs;
        var pts = _pts[segs];
        var last = 2 * segs + 1;
        for (var n = 0; n <= segs; n++) {
            var y = ya + step * n;
            var h = halfAt(y);
            var nudge = (n == 0) ? dt : ((n == segs) ? db : 0.0);
            var p = pts[n];
            p[0] = (0.5 + h * sl) * _w + dl;
            p[1] = y * _w + oy + nudge;
            p = pts[last - n];
            p[0] = (0.5 + h * sr) * _w + dr;
            p[1] = y * _w + oy + nudge;
        }
        dc.fillPolygon(pts);
    }

    // ------------------------------------------------------------ a press and hold

    // The reading nearest (x, y) on a screen `w` wide, or -1 off the band
    function readingAt(x as Number, y as Number, w as Number) as Number {
        var fw = w.toFloat();
        if (y < y0 * fw || y > y1 * fw || _run.n == 0) {
            return -1;
        }
        var r = 0.5 - MARGIN;
        _r2 = r * r;
        var h = halfAt((y0 + y1) / 2.0) * fw;
        var dx = x - fw / 2.0;
        var best = -1;
        var near = 0.0;
        var first = 0;
        for (var i = 1; i <= _run.n; i++) {
            if (i == _run.n || _run.seg[i] != _run.seg[first]) {
                var mid = (_run.u[first] + _run.u[i - 1] + _run.gw[i - 1]) / 2.0;
                var off = (h * Math.sin(_run.base + mid * _run.k) - dx).abs();
                if (best < 0 || off < near) {
                    best = _run.seg[first];
                    near = off;
                }
                first = i;
            }
        }
        return best;
    }
}
