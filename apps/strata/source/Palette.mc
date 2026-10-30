import Toybox.Lang;

// The colours the data picks
module Palette {

    const GRAY = 0x8A8A8A;

    // The layers' colour by day and by night, one pair per Strata setting:
    // Soil, Clay, Moss, Slate, Sand. All about as bright, so a reading
    // reads the same on any of them.
    const STRATA_DAY = [0x5C4A2E, 0x7A402E, 0x44582E, 0x405268, 0x76705A] as Array<Number>;
    const STRATA_NIGHT = [0x3E4556, 0x573B34, 0x2C4A44, 0x2A466A, 0x4E4A40] as Array<Number>;

    // Every fourth layer, per Accent setting: the outside temperature,
    // tone on tone (a paler strata), or Ochre, Lichen or Ember
    const ACCENT_TEMPERATURE = 0;
    const ACCENT_TONE = 1;
    const ACCENTS = [0, 0, 0xE0B050, 0x6FA8A0, 0xC8703E] as Array<Number>;
    const MOONLIGHT = 0x9FB4C8;              // the temperature's layers at night: the strata half way to this

    // The time, per TimeColor setting: Bone, the accent, Sandstone
    const TIME_ACCENT = 1;
    const TIMES = [0xF2ECE2, 0, 0xD9B98C] as Array<Number>;
    const CREAM = 0xE6DCCB;

    // The strata setting whose day colour is `color` (the editor's accent
    // colour), Soil for any other
    function strataFromColor(color as Number) as Number {
        var i = STRATA_DAY.indexOf(color);
        return (i >= 0) ? i : 0;
    }

    // The layers' colour for setting `choice` (Soil if out of range)
    function strata(choice as Number, night as Boolean) as Number {
        var colors = night ? STRATA_NIGHT : STRATA_DAY;
        return colors[(choice >= 0 && choice < colors.size()) ? choice : 0];
    }

    // The accent at full strength, for the time: the temperature's colour,
    // a pale strata for tone on tone, or the fixed colour
    function accent(choice as Number, celsius as Float?, earth as Number) as Number {
        if (choice == ACCENT_TONE) {
            return blend(earth, CREAM, 0.55);
        }
        if (choice <= ACCENT_TEMPERATURE || choice >= ACCENTS.size()) {
            return temperature(celsius);
        }
        return ACCENTS[choice];
    }

    // The accent layers' colour: dimmed so they stay earth, not neon (the
    // fixed colours less, so they hold their own on any strata)
    function layerAccent(choice as Number, celsius as Float?, earth as Number, night as Boolean) as Number {
        if (choice == ACCENT_TONE) {
            return blend(earth, CREAM, 0.25);
        }
        if (choice <= ACCENT_TEMPERATURE || choice >= ACCENTS.size()) {
            return night ? blend(earth, MOONLIGHT, 0.5) : scale(temperature(celsius), 0.65);
        }
        return scale(ACCENTS[choice], night ? 0.7 : 0.8);
    }

    // The time's colour for setting `choice`
    function time(choice as Number, accentChoice as Number, celsius as Float?, earth as Number) as Number {
        if (choice == TIME_ACCENT) {
            return accent(accentChoice, celsius, earth);
        }
        return TIMES[(choice >= 0 && choice < TIMES.size()) ? choice : 0];
    }

    // The accent layers take the outside temperature's colour, in mineral
    // tones: glacial slate below freezing, through lichen, moss and ochre,
    // to terracotta and red clay in the heat. Stops in Fahrenheit, blended
    // in between; grey with no temperature yet.
    const STOPS_F = [25.0, 45.0, 60.0, 72.0, 85.0, 100.0] as Array<Float>;
    const STOPS_COLOR = [0x8FB8C8, 0x6FA8A0, 0x8FAE6A, 0xD2A24C, 0xC8703E, 0xB84A3A] as Array<Number>;

    function temperature(celsius as Float?) as Number {
        if (celsius == null) {
            return GRAY;
        }
        var f = celsius * 9.0 / 5.0 + 32.0;
        if (f <= STOPS_F[0]) {
            return STOPS_COLOR[0];
        }
        var last = STOPS_F.size() - 1;
        if (f >= STOPS_F[last]) {
            return STOPS_COLOR[last];
        }
        var i = 0;
        while (f > STOPS_F[i + 1]) {
            i++;
        }
        var t = (f - STOPS_F[i]) / (STOPS_F[i + 1] - STOPS_F[i]);
        return blend(STOPS_COLOR[i], STOPS_COLOR[i + 1], t);
    }

    // `color` with each channel scaled by f (0 to 1)
    function scale(color as Number, f as Float) as Number {
        return blend(0x000000, color, f);
    }

    // c0 at t = 0, c1 at t = 1, channel by channel
    function blend(c0 as Number, c1 as Number, t as Float) as Number {
        var r = channel(c0 >> 16, c1 >> 16, t);
        var g = channel(c0 >> 8, c1 >> 8, t);
        var b = channel(c0, c1, t);
        return (r << 16) | (g << 8) | b;
    }

    function channel(a as Number, b as Number, t as Float) as Number {
        a = a & 0xFF;
        b = b & 0xFF;
        return (a + (b - a) * t + 0.5).toNumber();
    }
}
