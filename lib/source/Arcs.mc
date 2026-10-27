import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

module Lib {

    // Arcs and ring gauges. Angles are in degrees clockwise from 12 o'clock,
    // the same convention as designs/mockups.py, so a layout can be copied
    // straight from a mockup. Dc.drawArc counts counter-clockwise from
    // 3 o'clock, and the conversion lives here.
    (:arcs)
    module Arcs {

        // Mockup angle (clockwise from 12) -> Dc angle (counter-clockwise from 3)
        function toDc(deg12 as Numeric) as Numeric {
            var deg = 90 - deg12;
            while (deg < 0) {
                deg += 360;
            }
            while (deg >= 360) {
                deg -= 360;
            }
            return deg;
        }

        // The point at radius r and deg12 degrees clockwise from 12 o'clock.
        function point(cx as Numeric, cy as Numeric, r as Numeric, deg12 as Numeric) as Graphics.Point2D {
            var rad = Math.toRadians(deg12);
            return [cx + r * Math.sin(rad).toFloat(), cy - r * Math.cos(rad).toFloat()] as Graphics.Point2D;
        }

        // Arc from startDeg12, sweeping sweepDeg degrees clockwise, with the
        // current pen colour.
        function drawClockwise(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric,
                               startDeg12 as Numeric, sweepDeg as Numeric, width as Number) as Void {
            if (sweepDeg <= 0) {
                return;
            }
            dc.setPenWidth(width);
            if (sweepDeg >= 360) {
                dc.drawCircle(cx, cy, r);
                return;
            }
            dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, toDc(startDeg12), toDc(startDeg12 + sweepDeg));
        }

        // Ring gauge: a track over the whole span, then `fraction` (0..1) of
        // it filled from the start, clockwise.
        function drawGauge(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric,
                           startDeg12 as Numeric, spanDeg as Numeric, fraction as Float, width as Number,
                           trackColor as ColorType, fillColor as ColorType) as Void {
            dc.setColor(trackColor, Graphics.COLOR_TRANSPARENT);
            drawClockwise(dc, cx, cy, r, startDeg12, spanDeg, width);
            if (fraction > 1.0) {
                fraction = 1.0;
            }
            if (fraction > 0.0) {
                dc.setColor(fillColor, Graphics.COLOR_TRANSPARENT);
                drawClockwise(dc, cx, cy, r, startDeg12, spanDeg * fraction, width);
            }
        }
    }
}
