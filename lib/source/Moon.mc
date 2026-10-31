import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;

module Lib {

    // Moon phase from the synodic month. No network, no location: good to a
    // few hours, which is plenty for a glyph.
    (:moon)
    module Moon {

        // A reference new moon: 2000-01-06 18:14 UTC, as Unix seconds
        const NEW_MOON_EPOCH = 947182440;
        const SYNODIC_SECONDS = 2551442.877;   // 29.530588853 days

        // 0 = new, 0.25 = first quarter, 0.5 = full, 0.75 = last quarter
        function phase() as Float {
            return phaseAt(Time.now().value());
        }

        // The phase at a Unix time (seconds)
        function phaseAt(unixSeconds as Number) as Float {
            var elapsed = (unixSeconds - NEW_MOON_EPOCH).toFloat() / SYNODIC_SECONDS;
            return elapsed - Math.floor(elapsed).toFloat();
        }

        // Lit fraction of the disc, 0..1
        function illumination(phase as Float) as Float {
            return (1.0 - Math.cos(2.0 * Math.PI * phase).toFloat()) / 2.0;
        }

        // The phase's name: eight names, one per eighth of the cycle, each
        // centred on its principal phase (first quarter runs 0.1875..0.3125)
        function name(phase as Float) as String {
            var eighth = ((phase + 0.0625) * 8.0).toNumber() % 8;
            switch (eighth) {
                case 0: return "New moon";
                case 1: return "Waxing crescent";
                case 2: return "First quarter";
                case 3: return "Waxing gibbous";
                case 4: return "Full moon";
                case 5: return "Waning gibbous";
                case 6: return "Last quarter";
                case 7: return "Waning crescent";
            }
            return "";
        }

        // Draw the moon at (x, y) with radius r: a dim outline, and the lit
        // part filled. Lit on the right while waxing, on the left while
        // waning (northern hemisphere).
        function draw(dc as Dc, x as Number, y as Number, r as Number, phase as Float,
                      litColor as ColorType, outlineColor as ColorType) as Void {
            var c = Math.cos(2.0 * Math.PI * phase).toFloat();
            if (c < 0.98) {   // a new moon is the outline only
                fillLit(dc, x, y, r, phase, c, litColor);
            }
            dc.setPenWidth((r >= 30) ? 2 : 1);
            dc.setColor(outlineColor, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(x, y, r);
        }

        // The lit part: the bright limb, then the terminator back
        function fillLit(dc as Dc, x as Number, y as Number, r as Number, phase as Float, c as Float,
                         litColor as ColorType) as Void {
            var waxing = phase < 0.5;
            var side = waxing ? 1.0 : -1.0;
            var steps = 24;   // smooth at any size the faces draw it
            var points = [] as Array<Graphics.Point2D>;
            // Outer edge on the lit side, top to bottom
            for (var i = 0; i <= steps; i++) {
                var a = -Math.PI / 2 + Math.PI * i / steps;
                points.add([x + side * r * Math.cos(a).toFloat(), y + r * Math.sin(a).toFloat()] as Graphics.Point2D);
            }
            // Terminator, bottom back to top. c = +1 hugs the lit edge (nothing
            // lit), 0 is a straight line (half moon), -1 hugs the far edge (full).
            for (var i = 0; i <= steps; i++) {
                var dy = r - 2.0 * r * i / steps;
                var half = Math.sqrt(r * r - dy * dy).toFloat();
                points.add([x + side * c * half, y + dy] as Graphics.Point2D);
            }
            dc.setColor(litColor, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon(points);
        }
    }
}
