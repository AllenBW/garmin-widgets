import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

// The readings' digits in a row, one to a cell, drawn once into a bitmap: the
// wall's digits in a row are the stream in turn, so a run of cells is one
// copy from here, not a drawText per digit. In the simulator every draw call
// costs about the same (a little under a millisecond, a 3-pixel square as
// much as a digit), so the count of calls is the cost: the wall is 27
// copies instead of 800 digits, the time's lit digits some 60 instead of 280.
// A copy lands each digit within a pixel of where
// drawText would put it.
//
// On black (the wall) the copy is exactly what drawText draws there. On a
// clear background (the lit digits, over the numerals' mass and its edges)
// the simulator draws the digits' anti-aliased edges a little darker than
// drawText does (about 8 % less light over a digit): the watch's own
// blending (premultiplied, SDK BlendMode) is to be read on the wrist.
class Strip {

    var font as FontType;
    var color as Number;
    var stream as Array<Number>;             // the digits it was made from (kept to tell when they change)
    private var _bitmap as Graphics.BufferedBitmap;
    private var _pitch as Float;             // a cell's width, px
    private var _h as Number;

    // The stream from its start for `cells` cells (round again past its end),
    // each digit with its pen `pen` px into its cell; null when the graphics
    // pool has no room (the caller sets the digits as text)
    static function make(font as FontType, color as Number, background as Number, stream as Array<Number>, cells as Number,
                         pitch as Float, pen as Float) as Strip? {
        if (!(Graphics has :createBufferedBitmap)) {
            return null;
        }
        var h = Graphics.getFontHeight(font) + 1;
        try {
            var bitmap = Graphics.createBufferedBitmap({:width => (cells * pitch).toNumber() + 2, :height => h}).get()
                         as Graphics.BufferedBitmap?;
            if (bitmap == null) {
                return null;
            }
            return new Strip(font, color, background, stream, bitmap, cells, pitch, pen, h);
        } catch (e) {
            return null;
        }
    }

    function initialize(font_ as FontType, color_ as Number, background as Number, stream_ as Array<Number>,
                        bitmap as Graphics.BufferedBitmap, cells as Number, pitch as Float, pen as Float, h as Number) {
        font = font_;
        color = color_;
        stream = stream_;
        _bitmap = bitmap;
        _pitch = pitch;
        _h = h;
        var digits = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"] as Array<String>;
        var dc = bitmap.getDc();
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        dc.setColor(background, background);
        dc.clear();
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var length = stream.size();
        for (var k = 0; k < cells; k++) {
            dc.drawText(k * pitch + pen, 0, font, digits[stream[k % length]], Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    // Cells from `k` on, the first in the cell whose left edge is at `x`, up
    // to `right`, with the digits' pen at `top` (as drawText's), and nothing
    // of the strip outside the rows from `y0` to `y1`. Leaves a clip set: the
    // caller clears it when done.
    function draw(dc as Dc, k as Number, x as Float, right as Float, top as Float, y0 as Float, y1 as Float) as Void {
        var left = Math.floor(x + 0.5).toNumber();
        var y = top.toNumber();
        var from = Math.floor(y0 + 0.5).toNumber();
        from = (from > y) ? from : y;
        var to = Math.floor(y1 + 0.5).toNumber();
        to = (to < y + _h) ? to : y + _h;
        dc.setClip(left, from, Math.floor(right + 0.5).toNumber() - left, to - from);
        dc.drawBitmap(Math.floor(x - k * _pitch + 0.5).toNumber(), y, _bitmap);
    }
}
