import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

module Lib {

    // The readings' icons: each `s` tall, centred on (cx, cy), in one colour,
    // filled where it can be and in 3 px lines where it can't, so they carry
    // about the same ink. The same shapes as the faces' preview scripts. Draws the kinds
    // in Slots, so a face links slots too.
    (:icons)
    module Icons {

        var _width as Number = 454;   // the screen's, for the line weights

        function setWidth(w as Number) as Void {
            _width = w;
        }

        // A line `n` px wide on the 454 px screen, scaled to this one
        function pen(n as Float) as Number {
            var p = Math.round(n * _width / 454.0).toNumber();
            return (p < 1) ? 1 : p;
        }

        // The icon for a reading kind. `way` (Slots.Reading's) picks sunrise
        // over sunset and the barometer's arrow, `night` the moon over the sun
        // in the weather, `level` the battery's fill.
        function draw(dc as Dc, kind as Number, cx as Float, cy as Float, s as Float, color as Number,
                      night as Boolean, way as Number, level as Number) as Void {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            switch (kind) {
                case Slots.HEART:         heart(dc, cx, cy, s); break;
                case Slots.STEPS:         shoe(dc, cx, cy, s); break;
                case Slots.BATTERY:       battery(dc, cx, cy, s, level, color); break;
                case Slots.BODY:          bolt(dc, cx, cy, s); break;
                case Slots.STRESS:        stress(dc, cx, cy, s); break;
                case Slots.TEMPERATURE:   weather(dc, cx, cy + s * 0.11, s, color, night); break;   // its ink sits high
                case Slots.CALORIES:      flame(dc, cx, cy, s); break;
                case Slots.FLOORS:        stairs(dc, cx, cy, s); break;
                case Slots.INTENSITY:     chevrons(dc, cx, cy, s); break;
                case Slots.ALTITUDE:      mountain(dc, cx, cy, s); break;
                case Slots.PULSE_OX:      drop(dc, cx, cy, s, color); break;
                case Slots.BREATH:        lungs(dc, cx, cy, s, color); break;
                case Slots.SUN:           sun(dc, cx, cy, s, way > 0); break;
                case Slots.NOTIFICATIONS: bubble(dc, cx, cy, s); break;
                case Slots.RECOVERY:      hourglass(dc, cx, cy, s); break;
                case Slots.PRESSURE:      trend(dc, cx, cy, s, way, 1.0, 0.0, 0.0, -1.0); break;
                case Slots.SLEEP:         bed(dc, cx, cy, s); break;
                case Slots.CALENDAR:      calendar(dc, cx, cy, s); break;
            }
        }

        // Points (x, y) as fractions of s round (cx, cy)
        function shape(cx as Float, cy as Float, s as Float, xy as Array<Float>) as Array<Graphics.Point2D> {
            var points = [] as Array<Graphics.Point2D>;
            for (var i = 0; i + 1 < xy.size(); i += 2) {
                points.add([cx + xy[i] * s, cy + xy[i + 1] * s] as Graphics.Point2D);
            }
            return points;
        }

        function heart(dc as Dc, cx as Float, cy as Float, s as Float) as Void {
            s = s * 0.9;
            var r = s * 0.25;
            var top = cy - s * 0.2;
            dc.fillCircle(cx - r, top, r);
            dc.fillCircle(cx + r, top, r);
            dc.fillPolygon([[cx - 2 * r + r * 0.06, top + r * 0.3], [cx + 2 * r - r * 0.06, top + r * 0.3],
                            [cx, cy + s * 0.48]] as Array<Graphics.Point2D>);
        }

        // A running shoe from the side, toe to the right, a black welt over the sole
        function shoe(dc as Dc, cx as Float, cy as Float, s as Float) as Void {
            dc.fillPolygon(shape(cx, cy, s, [-0.50, 0.36, -0.50, -0.14, -0.42, -0.24, -0.30, -0.26, -0.24, -0.12, -0.08, -0.22,
                                             0.02, -0.36, 0.14, -0.32, 0.20, -0.10, 0.40, 0.00, 0.50, 0.16, 0.50, 0.36] as Array<Float>));
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(pen(1.5));
            dc.drawLine(cx - s * 0.5, cy + s * 0.22, cx + s * 0.5, cy + s * 0.22);
        }

        // Lying down, filled to `level` per cent: a shell, its black inside,
        // then the charge, each inset by whole pixels so it holds at 20 px
        function battery(dc as Dc, cx as Float, cy as Float, s as Float, level as Number, color as Number) as Void {
            var bw = s;
            var bh = s * 0.62;
            var left = cx - bw / 2 - s * 0.05;
            var top = cy - bh / 2;
            var w = pen(2.0);
            var gap = pen(2.0);
            dc.fillRoundedRectangle(left, top, bw, bh, s * 0.12);
            dc.fillRectangle(left + bw, cy - bh * 0.22, s * 0.11, bh * 0.44);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(left + w, top + w, bw - 2 * w, bh - 2 * w);
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            var f = (level < 0) ? 0 : ((level > 100) ? 100 : level);
            var inset = w + gap;
            dc.fillRectangle(left + inset, top + inset, (bw - 2 * inset) * f / 100.0, bh - 2 * inset);
        }

        function bolt(dc as Dc, cx as Float, cy as Float, s as Float) as Void {
            dc.fillPolygon(shape(cx, cy, s, [0.06, -0.5, 0.42, -0.5, 0.16, -0.08, 0.42, -0.08, -0.20, 0.5, -0.06, 0.08, -0.40, 0.08] as Array<Float>));
        }

        // A ring broken by a jagged line: tension
        function stress(dc as Dc, cx as Float, cy as Float, s as Float) as Void {
            var r = s * 0.42;
            dc.setPenWidth(pen(3.0));
            dc.drawCircle(cx, cy, r);
            var p = shape(cx, cy, r, [-1.0, 0.0, -0.45, 0.0, -0.2, -0.55, 0.15, 0.55, 0.4, 0.0, 1.0, 0.0] as Array<Float>);
            for (var i = 1; i < p.size(); i++) {
                dc.drawLine(p[i - 1][0], p[i - 1][1], p[i][0], p[i][1]);
            }
        }

        function cloud(dc as Dc, cx as Float, cy as Float, s as Float, grow as Float) as Void {
            dc.fillCircle(cx - s * 0.24, cy + s * 0.16, s * 0.17 + grow);
            dc.fillCircle(cx - s * 0.02, cy + s * 0.06, s * 0.24 + grow);
            dc.fillCircle(cx + s * 0.22, cy + s * 0.17, s * 0.16 + grow);
            dc.fillRoundedRectangle(cx - s * 0.42 - grow, cy + s * 0.14 - grow, s * 0.8 + 2 * grow, s * 0.19 + 2 * grow, s * 0.095 + grow);
        }

        // A sun (a moon at night) half behind a cloud, the cloud cut out by a black rim
        function weather(dc as Dc, cx as Float, cy as Float, s as Float, color as Number, night as Boolean) as Void {
            var sx = cx + s * 0.16;
            var sy = cy - s * 0.18;
            var sr = s * 0.22;
            if (night) {
                // a crescent opening to the upper right, clear of the cloud
                var mx = cx + s * 0.12;
                var my = cy - s * 0.16;
                var mr = s * 0.3;
                dc.fillCircle(mx, my, mr);
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(mx + mr * 0.6, my - mr * 0.45, mr);
            } else {
                dc.setPenWidth(pen(2.0));
                for (var i = 0; i < 8; i++) {
                    var a = Math.PI * i / 4;
                    var c = Math.cos(a);
                    var n = Math.sin(a);
                    dc.drawLine(sx + c * sr * 1.4, sy + n * sr * 1.4, sx + c * sr * 1.85, sy + n * sr * 1.85);
                }
                dc.fillCircle(sx, sy, sr);
            }
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            cloud(dc, cx, cy, s, s * 0.07);
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            cloud(dc, cx, cy, s, 0.0);
        }

        // A flame with a tongue licking up its left side
        function flame(dc as Dc, cx as Float, cy as Float, s as Float) as Void {
            dc.fillPolygon(shape(cx, cy, s, [0.02, -0.50, 0.22, -0.22, 0.34, 0.02, 0.36, 0.22, 0.26, 0.40, 0.0, 0.50, -0.26, 0.40,
                                             -0.36, 0.20, -0.30, -0.04, -0.18, -0.20, -0.12, 0.0, -0.04, -0.20] as Array<Float>));
        }

        function stairs(dc as Dc, cx as Float, cy as Float, s as Float) as Void {
            s = s * 0.9;
            dc.fillPolygon(shape(cx, cy, s, [-0.48, 0.46, -0.48, 0.16, -0.16, 0.16, -0.16, -0.14, 0.16, -0.14, 0.16, -0.44,
                                             0.48, -0.44, 0.48, 0.46] as Array<Float>));
        }

        // Two up-chevrons, one over the other (intensity minutes)
        function chevrons(dc as Dc, cx as Float, cy as Float, s as Float) as Void {
            dc.setPenWidth(pen(3.5));
            for (var i = -1; i <= 1; i += 2) {
                var y = cy + i * s * 0.2;
                dc.drawLine(cx - s * 0.42, y + s * 0.2, cx, y - s * 0.2);
                dc.drawLine(cx, y - s * 0.2, cx + s * 0.42, y + s * 0.2);
            }
        }

        // A bed from the side, a pillow at its head (sleep score)
        function bed(dc as Dc, cx as Float, cy as Float, s as Float) as Void {
            dc.fillRectangle(cx - s * 0.5, cy - s * 0.3, s * 0.14, s * 0.7);       // the headboard
            dc.fillRectangle(cx - s * 0.5, cy + s * 0.04, s, s * 0.2);             // the mattress
            dc.fillRectangle(cx + s * 0.38, cy + s * 0.04, s * 0.12, s * 0.36);    // the foot
            dc.fillRoundedRectangle(cx - s * 0.3, cy - s * 0.14, s * 0.28, s * 0.16, s * 0.06);
        }

        function mountain(dc as Dc, cx as Float, cy as Float, s as Float) as Void {
            dc.fillPolygon(shape(cx, cy, s, [-0.1, -0.45, 0.32, 0.4, -0.54, 0.4] as Array<Float>));
            dc.fillPolygon(shape(cx, cy, s, [0.28, -0.12, 0.54, 0.4, 0.0, 0.4] as Array<Float>));
        }

        // A drop with an O in it: oxygen, not water
        function drop(dc as Dc, cx as Float, cy as Float, s as Float, color as Number) as Void {
            var r = s * 0.3;
            var by = cy + s * 0.5 - r;
            var points = [[cx, cy - s * 0.5]] as Array<Graphics.Point2D>;
            for (var i = 0; i <= 12; i++) {
                var a = Math.PI * (-0.2 + 1.4 * i / 12);
                points.add([cx + r * Math.cos(a), by + r * Math.sin(a)] as Graphics.Point2D);
            }
            dc.fillPolygon(points);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(pen(2.0));
            dc.drawCircle(cx, by, r * 0.48);
        }

        function lungs(dc as Dc, cx as Float, cy as Float, s as Float, color as Number) as Void {
            dc.setPenWidth(pen(3.0));
            dc.drawLine(cx, cy - s * 0.5, cx, cy - s * 0.1);
            dc.fillEllipse(cx - s * 0.25, cy + s * 0.09, s * 0.2, s * 0.39);
            dc.fillEllipse(cx + s * 0.25, cy + s * 0.09, s * 0.2, s * 0.39);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(cx - s * 0.04, cy - s * 0.3, s * 0.08, s * 0.78);
        }

        // The sun half risen on its horizon under a chevron: up for sunrise, down for sunset
        function sun(dc as Dc, cx as Float, cy as Float, s as Float, rise as Boolean) as Void {
            var hy = cy + s * 0.36;
            var r = s * 0.3;
            var points = [] as Array<Graphics.Point2D>;
            for (var i = 0; i <= 10; i++) {
                var a = Math.PI * i / 10;
                points.add([cx + r * Math.cos(a), hy - r * Math.sin(a)] as Graphics.Point2D);
            }
            dc.fillPolygon(points);
            dc.setPenWidth(pen(2.5));
            dc.drawLine(cx - s * 0.52, hy, cx + s * 0.52, hy);
            var k = s * 0.26;
            var near = hy - r - s * 0.12;
            var far = near - s * 0.3;
            var wing = rise ? near : far;
            var tip = rise ? far : near;
            dc.setPenWidth(pen(3.0));
            dc.drawLine(cx - k, wing, cx, tip);
            dc.drawLine(cx, tip, cx + k, wing);
        }

        // A speech bubble (notifications)
        function bubble(dc as Dc, cx as Float, cy as Float, s as Float) as Void {
            s = s * 0.9;
            dc.fillRoundedRectangle(cx - s * 0.5, cy - s * 0.42, s, s * 0.62, s * 0.16);
            dc.fillPolygon(shape(cx, cy, s, [-0.26, 0.16, -0.02, 0.16, -0.3, 0.46] as Array<Float>));
        }

        function hourglass(dc as Dc, cx as Float, cy as Float, s as Float) as Void {
            dc.fillPolygon(shape(cx, cy, s, [-0.32, -0.46, 0.32, -0.46, 0.05, 0.0, 0.32, 0.46, -0.32, 0.46, -0.05, 0.0] as Array<Float>));
        }

        // The barometer's trend, an arrow: up and forward while it rises
        // (`way` 1), down and forward while it falls (-1), straight on while
        // it holds (0). (ax, ay) is the text's forward direction on the
        // screen and (ux, uy) its up, so the arrow can follow text set round
        // a rim; (1, 0) and (0, -1) on a level line.
        function trend(dc as Dc, cx as Float, cy as Float, s as Float, way as Number,
                       ax as Float, ay as Float, ux as Float, uy as Float) as Void {
            // the arrow's direction in the text's frame
            var f = (way == 0) ? 1.0 : 0.7071;
            var v = way * 0.7071;
            var dx = f * ax + v * ux;
            var dy = f * ay + v * uy;
            // and its side, a quarter turn from it
            var px = -dy;
            var py = dx;
            var tip = s * 0.46;
            var back = s * 0.46;
            var head = s * 0.42;
            var wide = s * 0.30;
            var neckX = cx + dx * (tip - head);
            var neckY = cy + dy * (tip - head);
            dc.setPenWidth(pen(3.5));
            dc.drawLine(cx - dx * back, cy - dy * back, neckX, neckY);
            dc.fillPolygon([[cx + dx * tip, cy + dy * tip], [neckX + px * wide, neckY + py * wide],
                            [neckX - px * wide, neckY - py * wide]] as Array<Graphics.Point2D>);
        }

        function calendar(dc as Dc, cx as Float, cy as Float, s as Float) as Void {
            dc.setPenWidth(pen(2.5));
            dc.drawRoundedRectangle(cx - s * 0.44, cy - s * 0.36, s * 0.88, s * 0.82, s * 0.08);
            dc.fillRectangle(cx - s * 0.44, cy - s * 0.36, s * 0.88, s * 0.26);
            dc.drawLine(cx - s * 0.22, cy - s * 0.5, cx - s * 0.22, cy - s * 0.28);
            dc.drawLine(cx + s * 0.22, cy - s * 0.5, cx + s * 0.22, cy - s * 0.28);
        }

        // A filled bell (an alarm is set)
        function bell(dc as Dc, cx as Float, cy as Float, s as Float, color as Number) as Void {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            var r = s * 0.34;
            var top = cy - s * 0.13;
            var points = [] as Array<Graphics.Point2D>;
            for (var i = 0; i <= 10; i++) {
                var a = Math.PI * i / 10;
                points.add([cx + r * Math.cos(a), top - r * Math.sin(a)] as Graphics.Point2D);
            }
            points.add([cx - s * 0.46, cy + s * 0.26] as Graphics.Point2D);
            points.add([cx + s * 0.46, cy + s * 0.26] as Graphics.Point2D);
            dc.fillPolygon(points);
            dc.fillCircle(cx, cy + s * 0.37, s * 0.1);
        }

        // A phone with a slash through it: the phone isn't connected
        function phoneOff(dc as Dc, cx as Float, cy as Float, s as Float, color as Number) as Void {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(pen(2.5));
            dc.drawRoundedRectangle(cx - s * 0.24, cy - s * 0.46, s * 0.48, s * 0.92, s * 0.08);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(pen(6.0));
            dc.drawLine(cx - s * 0.42, cy + s * 0.42, cx + s * 0.42, cy - s * 0.42);
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(pen(3.0));
            dc.drawLine(cx - s * 0.42, cy + s * 0.42, cx + s * 0.42, cy - s * 0.42);
        }
    }
}
