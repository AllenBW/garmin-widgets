import Toybox.Lang;

// The three colour sets from the store face the owner picked: the outer,
// middle and inner rings, and the time. Each ring's track is the same hue
// at about a third of the brightness. Then the looks' own (Lib.Look): three
// fluorescent sets, high visibility's in orange, blue and green, and low
// light's.
module Themes {

    const SUNSET = 0;
    const BERRY = 1;
    const FOREST = 2;
    const BLAZE = 3;
    const VOLT = 4;
    const FLARE = 5;
    const BRIGHT = 6;
    const LOW = 7;
    const BRIGHT_BLUE = 8;
    const BRIGHT_GREEN = 9;
    // The personas the daily look steps through, and their names
    const PERSONAS = [SUNSET, BERRY, FOREST, BLAZE, VOLT, FLARE] as Array<Number>;
    const NAMES = ["SUNSET", "BERRY", "FOREST", "BLAZE", "VOLT", "FLARE"] as Array<String>;

    // [outer, middle, inner, time]
    function colors(theme as Number) as Array<Number> {
        switch (theme) {
            case BERRY:  return [0xE040C8, 0xF0143C, 0xFF8C50, 0xE040C8];
            case FOREST: return [0x14C828, 0x6EC6DE, 0x4C82FF, 0x6EC6DE];
            case BLAZE:  return [Lib.Look.FLARE, Lib.Look.BLAZE, 0xFF4F7A, Lib.Look.BLAZE];
            case VOLT:   return [Lib.Look.VOLT, Lib.Look.FLARE, 0x2EE6B0, Lib.Look.VOLT];
            case FLARE:  return [Lib.Look.BLAZE, Lib.Look.FLARE, Lib.Look.VOLT, Lib.Look.FLARE];
            case BRIGHT: return [Lib.Look.VOLT, Lib.Look.BLAZE, Lib.Look.FLARE, Lib.Look.BLAZE];
            case BRIGHT_BLUE:  return [0x00E5FF, Lib.Look.ARC, 0x8C7CFF, Lib.Look.ARC];
            case BRIGHT_GREEN: return [Lib.Look.FLARE, Lib.Look.VOLT, 0x2EE6B0, Lib.Look.VOLT];
            case LOW:    return [0xC8703E, Lib.Look.GLOW, 0xE0B050, Lib.Look.CREAM];
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
