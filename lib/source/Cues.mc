import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

module Lib {

    // What each button does right now, as a short arc on the bezel beside
    // the button and a word inside it, on a black patch so the word stays
    // readable where content reaches the edge. The angles (clockwise from
    // twelve) are where Garmin's own button hints sit on the fenix 8
    // family, from the device personality files: START 58, BACK 123,
    // DOWN 237, UP 270. `at` says which cue a touch landed on, so the
    // corners of the screen act as the buttons beside them.
    (:cues)
    module Cues {

        const START = 58;
        const BACK = 123;
        const DOWN = 237;
        const UP = 270;
        const SPAN = 11;   // half the arc, in degrees

        // What `at` returns
        const TAP_NONE = 0;
        const TAP_START = 1;
        const TAP_BACK = 2;
        const TAP_UP = 3;
        const TAP_DOWN = 4;

        // Which cue a touch at (x, y) on a w by h screen landed on: near the
        // bezel and within thirty degrees of a cue's angle, else TAP_NONE
        function at(x as Number, y as Number, w as Number, h as Number) as Number {
            var cx = w / 2;
            var cy = h / 2;
            var r = (w < h ? w : h) / 2;
            var dx = (x - cx).toFloat();
            var dy = (y - cy).toFloat();
            if (Math.sqrt(dx * dx + dy * dy) < r * 0.55) {
                return TAP_NONE;
            }
            var angle = Math.toDegrees(Math.atan2(dx, -dy)).toFloat();
            if (angle < 0) {
                angle += 360.0;
            }
            var cues = [START, BACK, UP, DOWN] as Array<Number>;
            var taps = [TAP_START, TAP_BACK, TAP_UP, TAP_DOWN] as Array<Number>;
            var best = TAP_NONE;
            var bestDiff = 30.0;
            for (var i = 0; i < cues.size(); i++) {
                var diff = (angle - cues[i]).abs();
                if (diff > 180.0) {
                    diff = 360.0 - diff;
                }
                if (diff < bestDiff) {
                    bestDiff = diff;
                    best = taps[i];
                }
            }
            return best;
        }

        // One cue: the arc at `angle` in arcColour, the label in textColour
        // in `font` just inside it, on a black patch
        function draw(dc as Dc, angle as Number, label as String, font as FontType, arcColour as Number, textColour as Number) as Void {
            var w = dc.getWidth();
            var h = dc.getHeight();
            var cx = w / 2;
            var cy = h / 2;
            var r = (w < h ? w : h) / 2;
            // drawArc counts degrees anticlockwise from three o'clock
            var from = 90 - angle - SPAN;
            dc.setColor(arcColour, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth((h * 0.014).toNumber() + 2);
            dc.drawArc(cx, cy, r - 3, Graphics.ARC_COUNTER_CLOCKWISE, from, from + 2 * SPAN);
            dc.setPenWidth(1);
            // the word sits just inside the arc; the left ones a little further in, the screen is narrower there
            var inset = angle > 180 ? 0.09 : 0.07;
            var radius = r - (h * inset).toNumber();
            var rad = Math.toRadians(angle);
            var x = cx + (radius * Math.sin(rad)).toNumber();
            var y = cy - (radius * Math.cos(rad)).toNumber();
            // on a black patch, so the word stays readable where content reaches the edge
            var size = dc.getTextDimensions(label, font);
            var pad = (h * 0.012).toNumber() + 2;
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
            dc.fillRoundedRectangle(x - size[0] / 2 - pad, y - size[1] / 2 - 1, size[0] + 2 * pad, size[1] + 2, pad);
            dc.setColor(textColour, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, font, label, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }
}
