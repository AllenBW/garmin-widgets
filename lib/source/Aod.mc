import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;

module Lib {

    // Always-on (low power) display helpers for AMOLED burn-in protection:
    // at most 10 % of pixels lit, and no pixel lit for more than 3 minutes.
    (:aod)
    module Aod {

        // True when the device enforces burn-in protection (AMOLED/MicroLED).
        function required() as Boolean {
            var settings = System.getDeviceSettings();
            return (settings has :requiresBurnInProtection) && settings.requiresBurnInProtection;
        }

        // Offset for this minute: visits every cell of a 5x5 grid once in 25
        // minutes, and moves along both axes every minute, so a long
        // horizontal or vertical stroke never stays on the same pixels.
        // Range is -2*step .. +2*step on each axis.
        function offset(minute as Number, step as Number) as [Number, Number] {
            var dx = ((minute % 5) - 2) * step;
            var dy = (((2 * minute + minute / 5 + 1) % 5) - 2) * step;
            return [dx, dy];
        }

        // Quarter-brightness version of a 0xRRGGBB colour.
        function dim(color as Number) as Number {
            return (color >> 2) & 0x3F3F3F;
        }

        // Hollow text: the glyphs are drawn offset by one pixel in four
        // directions in `color`, then once more in black on top, so only a
        // thin outline stays lit. Works with any font, no outline font needed.
        function drawHollowText(dc as Dc, x as Numeric, y as Numeric, font as FontType,
                                text as String, color as ColorType, justification as Number) as Void {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x - 1, y, font, text, justification);
            dc.drawText(x + 1, y, font, text, justification);
            dc.drawText(x, y - 1, font, text, justification);
            dc.drawText(x, y + 1, font, text, justification);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, font, text, justification);
        }
    }
}
