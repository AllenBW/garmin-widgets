import Toybox.Lang;

// The three colour sets from the store face the owner picked: the outer,
// middle and inner rings, and the time. Each ring's track is the same hue
// at about a third of the brightness.
module Themes {

    const SUNSET = 0;
    const BERRY = 1;
    const FOREST = 2;

    // [outer, middle, inner, time]
    function colors(theme as Number) as Array<Number> {
        switch (theme) {
            case BERRY:  return [0xE040C8, 0xF0143C, 0xFF8C50, 0xE040C8];
            case FOREST: return [0x14C828, 0x6EC6DE, 0x4C82FF, 0x6EC6DE];
        }
        return [0x6EC6DE, 0xFF8A50, 0xF0C419, 0xFF8A50];
    }

    // A colour at `f` of its brightness, channel by channel
    function shade(color as Number, f as Float) as Number {
        var r = (((color >> 16) & 0xFF) * f).toNumber();
        var g = (((color >> 8) & 0xFF) * f).toNumber();
        var b = ((color & 0xFF) * f).toNumber();
        return (r << 16) | (g << 8) | b;
    }
}
