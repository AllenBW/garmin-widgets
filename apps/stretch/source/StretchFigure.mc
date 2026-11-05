import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

// The stick figure: a hip and fourteen angles per pose from StretchData,
// blended between the start (t = 0) and the stretch (t = 1) and drawn as
// thick round-ended lines, the far limbs dimmer, the muscle being
// stretched in the accent, a dark eye for where the face points. The spine
// is two halves so the back can round and arch. The model matches
// designs/gen_stretch.py.
module StretchFigure {

    // Body heights
    const L_TORSO = 0.30;
    const L_HEAD_AT = 0.097;
    const R_HEAD = 0.062;
    const L_UA = 0.165;
    const L_FA = 0.155;
    const L_TH = 0.245;
    const L_SH = 0.245;
    const L_FOOT = 0.075;
    const SH_W = 0.085;
    const HIP_W = 0.05;
    const FRONT_FOOT = 0.35;
    const EYE_AT = 0.5;      // head radii
    const R_EYE = 0.28;
    const SEAT_DROP = 0.035;
    const SEAT_BACK = 0.075;
    const SEAT_FRONT = 0.13;
    const CHAIR_BACK_H = 0.26;

    const SLOTS = 14;
    const META = 13;         // bytes a stretch in StretchData.META

    // Flags in StretchData.META
    const F_FRONT = 1;
    const F_CLOSEUP = 2;
    const F_SIDED = 4;
    const F_WALL = 8;
    const F_PNF = 16;
    const F_WALL_BACK = 32;
    const F_CHAIR = 64;

    // Joints, as pairs in the point array
    const J_HIP = 0;
    const J_MID = 1;
    const J_SH = 2;
    const J_HEAD = 3;
    const J_EYE = 4;
    const J_N = 5;   // near: so, ho, el, ha, kn, an, to
    const J_F = 12;  // far: the same seven
    const JOINTS = 19;
    const SO = 0;
    const HO = 1;
    const EL = 2;
    const HA = 3;
    const KN = 4;
    const AN = 5;
    const TO = 6;
    // The joint an anchor byte names (designs/gen_stretch.py ANCHORS)
    const ANCHORS = [J_HIP, J_N + AN, J_F + AN, J_N + HA, J_F + HA, J_N + KN, J_F + KN, J_N + TO, J_F + TO] as Array<Number>;

    // The angles at blend t, in degrees, the shorter way round
    function angles(i as Number, t as Float) as Array<Float> {
        var p = StretchData.POSES;
        var base = i * 2 * SLOTS;
        var out = new Array<Float>[SLOTS];
        for (var k = 0; k < SLOTS; k++) {
            var a = p[base + k] * 2;
            var d = p[base + SLOTS + k] * 2 - a;
            if (d > 180) {
                d -= 360;
            } else if (d < -180) {
                d += 360;
            }
            out[k] = a + d * t;
        }
        return out;
    }

    // The joints (x, y pairs, y up, body heights), standing on y = 0, the
    // anchor's x where it is in pose A
    function placed(i as Number, t as Float) as Array<Float> {
        var m = StretchData.META;
        var front = (m[i * META + 1] & F_FRONT) != 0;
        var pts = points(angles(i, t), front);
        var anchor = ANCHORS[m[i * META + 10]];
        if (anchor != J_HIP) {
            var dx = (m[i * META + 11] - 128) / 100.0 - pts[2 * anchor];
            for (var k = 0; k < 2 * JOINTS; k += 2) {
                pts[k] += dx;
            }
        }
        return pts;
    }

    function points(ang as Array<Float>, front as Boolean) as Array<Float> {
        var pts = new Array<Float>[2 * JOINTS];
        var lower = Math.toRadians(ang[0] + ang[12]);
        var upper = Math.toRadians(ang[0] - ang[12]);
        var half = L_TORSO / 2;
        set(pts, J_HIP, 0.0, 0.0);
        var mx = (half * Math.cos(lower)).toFloat();
        var my = (half * Math.sin(lower)).toFloat();
        set(pts, J_MID, mx, my);
        var sx = (mx + half * Math.cos(upper)).toFloat();
        var sy = (my + half * Math.sin(upper)).toFloat();
        set(pts, J_SH, sx, sy);
        var head = upper + Math.toRadians(ang[1]);
        var hx = (sx + L_HEAD_AT * Math.cos(head)).toFloat();
        var hy = (sy + L_HEAD_AT * Math.sin(head)).toFloat();
        set(pts, J_HEAD, hx, hy);
        // the eye: ahead seen from the side, turned to a side seen from the front
        var yaw = Math.toRadians(ang[13]);
        var k = R_HEAD * EYE_AT * (front ? Math.sin(yaw) : Math.cos(yaw));
        var face = head - Math.PI / 2;
        set(pts, J_EYE, (hx + k * Math.cos(face)).toFloat(), (hy + k * Math.sin(face)).toFloat());
        // shoulders and hips sit apart only seen from the front
        var spx = Math.cos(upper - Math.PI / 2).toFloat();
        var spy = Math.sin(upper - Math.PI / 2).toFloat();
        var hpx = Math.cos(lower - Math.PI / 2).toFloat();
        var hpy = Math.sin(lower - Math.PI / 2).toFloat();
        for (var s = 0; s < 2; s++) {
            var j = s == 0 ? J_N : J_F;
            var sign = s == 0 ? 1.0 : -1.0;
            var w = front ? SH_W * sign : 0.0;
            var hw = front ? HIP_W * sign : 0.0;
            set(pts, j + SO, sx + w * spx, sy + w * spy);
            set(pts, j + HO, hw * hpx, hw * hpy);
            limb(pts, j + SO, j + EL, ang[2 + 2 * s], L_UA);
            limb(pts, j + EL, j + HA, ang[3 + 2 * s], L_FA);
            limb(pts, j + HO, j + KN, ang[6 + 2 * s], L_TH);
            limb(pts, j + KN, j + AN, ang[7 + 2 * s], L_SH);
            limb(pts, j + AN, j + TO, ang[10 + s], front ? L_FOOT * FRONT_FOOT : L_FOOT);
        }
        // stand on the lowest point, the head's edge included
        var lo = hy - R_HEAD;
        for (var n = 1; n < 2 * JOINTS; n += 2) {
            if (pts[n] < lo) {
                lo = pts[n];
            }
        }
        for (var n = 1; n < 2 * JOINTS; n += 2) {
            pts[n] -= lo;
        }
        return pts;
    }

    function set(pts as Array<Float>, j as Number, x as Float, y as Float) as Void {
        pts[2 * j] = x;
        pts[2 * j + 1] = y;
    }

    function limb(pts as Array<Float>, from as Number, to as Number, deg as Float, len as Float) as Void {
        var r = Math.toRadians(deg);
        set(pts, to, (pts[2 * from] + len * Math.cos(r)).toFloat(), (pts[2 * from + 1] + len * Math.sin(r)).toFloat());
    }

    // Draw stretch i at blend t, mirrored for the right side, standing on
    // `ground` and filling at most w by h centred on cx. A ghost (accent
    // null) is drawn all in `near`, with no props.
    function draw(dc as Dc, i as Number, t as Float, mirror as Boolean, cx as Number, ground as Number,
                  w as Number, h as Number, near as Number, far as Number, accent as Number?) as Void {
        var m = StretchData.META;
        var b = i * META;
        var flags = m[b + 1];
        var front = (flags & F_FRONT) != 0;
        var targets = m[b + 2] | (m[b + 3] << 8);
        var x0 = (m[b + 6] - 128) / 100.0;
        var x1 = (m[b + 7] - 128) / 100.0;
        var top = m[b + 8] / 100.0;
        var lift = m[b + 9] / 100.0;
        var s = w / (x1 - x0);
        if (h / top < s) {
            s = h / top;
        }
        var mid = (x0 + x1) / 2.0;
        var pts = placed(i, t);
        var dir = mirror ? -s : s;
        var xy = new Array<Number>[2 * JOINTS];
        for (var k = 0; k < JOINTS; k++) {
            xy[2 * k] = (cx + (pts[2 * k] - mid) * dir).toNumber();
            xy[2 * k + 1] = (ground - (pts[2 * k + 1] - lift) * s).toNumber();
        }
        var pen = (0.052 * s).toNumber();
        if (pen < 3) {
            pen = 3;
        }
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        if (lift > 0.0) {
            // a close-up stops at the hips
            dc.setClip(0, 0, dc.getWidth(), ground + pen);
        }
        var ghost = accent == null;
        if (ghost) {
            // a thin guide, told from the far limbs by shape as well as shade
            pen = pen * 6 / 10;
        }
        if (front) {
            far = near;
        }
        var acc = ghost ? near : accent as Number;
        dc.setColor(far, Graphics.COLOR_TRANSPARENT);
        if ((flags & F_WALL) != 0 && !ghost) {
            // the wall stands just past the hands at full stretch, ahead or behind
            var wx = (flags & F_WALL_BACK) != 0 ? x0 - 0.03 : x1 + 0.03;
            var sx = (cx + (wx - mid) * dir).toNumber();
            dc.setPenWidth(pen / 2 < 2 ? 2 : pen / 2);
            // no higher than the figure's own box, so it never reaches the words above
            dc.drawLine(sx, ground, sx, ground - ((top < 0.95 ? top : 0.95) * s).toNumber());
        }
        if ((flags & F_CHAIR) != 0) {
            chair(dc, pts[2 * J_HIP], pts[2 * J_HIP + 1] - lift, cx, ground, mid, dir, s, pen / 2);
        }
        // the muscle being stretched is thicker too, not told by colour alone
        var tgt = ghost ? 0 : targets;
        limbs(dc, xy, J_F, 4, tgt, far, acc, pen);
        if (front) {
            seg(dc, xy, J_N + SO, J_F + SO, near, pen);
            seg(dc, xy, J_N + HO, J_F + HO, near, pen);
        }
        var back = (targets & 1) != 0 ? acc : near;
        var backPen = (targets & 1) != 0 && !ghost ? pen * 16 / 10 : pen * 13 / 10;
        seg(dc, xy, J_HIP, J_MID, back, backPen);
        seg(dc, xy, J_MID, J_SH, back, backPen);
        seg(dc, xy, J_SH, J_HEAD, (targets & 2) != 0 ? acc : near, (targets & 2) != 0 && !ghost ? pen : pen * 8 / 10);
        dc.setColor(near, Graphics.COLOR_TRANSPARENT);
        var r = (R_HEAD * s).toNumber();
        dc.fillCircle(xy[2 * J_HEAD], xy[2 * J_HEAD + 1], r);
        var ex = xy[2 * J_EYE] - xy[2 * J_HEAD];
        var ey = xy[2 * J_EYE + 1] - xy[2 * J_HEAD + 1];
        if ((ex * ex + ey * ey) * 10000 > r * r * 225) {
            // shown unless the face is turned nearly square to us (or, side on, away)
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(xy[2 * J_EYE], xy[2 * J_EYE + 1], (R_HEAD * R_EYE * s).toNumber() + 1);
        }
        limbs(dc, xy, J_N, 2, tgt, near, acc, pen);
        if (lift > 0.0) {
            dc.clearClip();
        }
    }

    // Seat, legs and back under a seated hip, in the far colour
    function chair(dc as Dc, hx as Float, hy as Float, cx as Number, ground as Number, mid as Float,
                   dir as Float, s as Float, pen as Number) as Void {
        var seat = (ground - (hy - SEAT_DROP) * s).toNumber();
        var bx = (cx + (hx - SEAT_BACK - mid) * dir).toNumber();
        var fx = (cx + (hx + SEAT_FRONT - mid) * dir).toNumber();
        dc.setPenWidth(pen < 2 ? 2 : pen);
        dc.drawLine(bx, seat, fx, seat);
        dc.drawLine(bx, seat, bx, ground);
        dc.drawLine(fx, seat, fx, ground);
        dc.drawLine(bx, seat, bx, seat - (CHAIR_BACK_H * s).toNumber());
    }

    // One side's arm and leg; bit is that side's upper-arm bit
    function limbs(dc as Dc, xy as Array<Number>, j as Number, bit as Number, targets as Number,
                   colour as Number, accent as Number, pen as Number) as Void {
        // slots: ua fa (bit, bit+1), th sh (bit+4, bit+5), foot (10 or 11)
        var footBit = j == J_N ? 10 : 11;
        part(dc, xy, j + HO, j + KN, targets, bit + 4, colour, accent, pen);
        part(dc, xy, j + KN, j + AN, targets, bit + 5, colour, accent, pen);
        part(dc, xy, j + AN, j + TO, targets, footBit, colour, accent, pen * 8 / 10);
        part(dc, xy, j + SO, j + EL, targets, bit, colour, accent, pen);
        part(dc, xy, j + EL, j + HA, targets, bit + 1, colour, accent, pen);
    }

    // A limb segment, in the accent and a quarter thicker when it is the target
    function part(dc as Dc, xy as Array<Number>, a as Number, b as Number, targets as Number, bit as Number,
                  colour as Number, accent as Number, pen as Number) as Void {
        if ((targets & (1 << bit)) != 0) {
            seg(dc, xy, a, b, accent, pen * 5 / 4);
        } else {
            seg(dc, xy, a, b, colour, pen);
        }
    }

    // A thick line with round ends
    function seg(dc as Dc, xy as Array<Number>, a as Number, b as Number, colour as Number, pen as Number) as Void {
        var ax = xy[2 * a];
        var ay = xy[2 * a + 1];
        var bx = xy[2 * b];
        var by = xy[2 * b + 1];
        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(pen);
        dc.drawLine(ax, ay, bx, by);
        var r = pen / 2;
        dc.fillCircle(ax, ay, r);
        dc.fillCircle(bx, by, r);
    }
}
