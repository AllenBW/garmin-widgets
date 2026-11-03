import Toybox.Application;
import Toybox.Application.WatchFaceConfig;
import Toybox.Complications;
import Toybox.Lang;

module Lib {

    // A face's settings, which come from two places with the same choices:
    // the phone app's settings list (resources/settings: Style, Accent,
    // DataColor, Reading1..ReadingN, Bedside) and the fēnix 8's watch face editor
    // (resources/configs/watchface.xml: styles, accent colours, data
    // colours, complications 1..N). Whichever was changed last wins: the
    // app calls changedOnPhone from onSettingsChanged, the delegate
    // changedInEditor from onWatchFaceConfigEdited. Until either is
    // changed, the editor's. Also the faces' shared colours.
    (:config)
    module Config {

        // Amber, Lime, Sky, Flame, Mint, Violet, Rose, Gold: the phone list's accents
        const ACCENTS = [0xFFB020, 0x8CE03C, 0x38A8FF, 0xFF5A36, 0x2EE6B0, 0xA77BFF, 0xFF5C9E, 0xE8D44A] as Array<Number>;
        // Bone, Silver, Sand, Ice, Blush: the data colours
        const DATA = [0xF2ECE2, 0xB4BAC2, 0xE6CFA0, 0xCFE6FF, 0xF8D2D8] as Array<Number>;
        const BEDSIDE = 0x8C2A1C;        // a dim ember red that keeps night vision
        const LIGHT = 0.30;              // the least luminance an accent is drawn with
        const QUIET = 0.75;              // icons and quiet text: the data colour at this

        // The personas the daily look steps through: [accent, data colour],
        // each face choosing the typeface (Gold, Ember, Orchard, Dusk, and
        // the fluorescent orange, green and yellow-green on white)
        const PERSONAS = [
            [0xFFB020, 0xE6CFA0], [0xFF5A36, 0xE6CFA0], [0x8CE03C, 0xF2ECE2], [0xA77BFF, 0xF8D2D8],
            [Look.BLAZE, Look.WHITE], [Look.VOLT, Look.WHITE], [Look.FLARE, Look.WHITE]
        ] as Array<[Number, Number]>;
        const NAMES = ["GOLD", "EMBER", "ORCHARD", "DUSK", "BLAZE", "VOLT", "FLARE"] as Array<String>;

        const SOURCE = "Source";
        const PHONE = "phone";
        const EDITOR = "editor";

        typedef Settings as [Number, Number, Number, Array<Complications.Id>, Boolean];

        // [style, accent (lifted to read on black), data colour, a
        // complication id per slot, the bedside clock on]
        function read(styles as Number, defaults as Array<Complications.Type>) as Settings {
            var style = number("Style", 0, styles - 1);
            var accent = ACCENTS[number("Accent", 0, ACCENTS.size() - 1)];
            var data = DATA[number("DataColor", 0, DATA.size() - 1)];
            var ids = [] as Array<Complications.Id>;
            for (var n = 0; n < defaults.size(); n++) {
                var type = Application.Properties.getValue("Reading" + (n + 1));
                ids.add(new Complications.Id(((type instanceof Number && type > 0) ? type : defaults[n]) as Complications.Type));
            }
            if (Application has :WatchFaceConfig && !PHONE.equals(Application.Storage.getValue(SOURCE))) {
                var config = WatchFaceConfig.getSettings(null);
                if (config != null) {
                    var styleId = config.styleId;
                    if (styleId != null && styleId >= 0 && styleId < styles) {
                        style = styleId;
                    }
                    var picked = config.accentColor;
                    if (picked != null && picked.color != null) {
                        accent = picked.color as Number;
                    }
                    picked = config.complicationColor;
                    if (picked != null && picked.color != null) {
                        data = picked.color as Number;
                    }
                    var refs = config.complicationSettings;
                    if (refs != null) {
                        for (var i = 0; i < refs.size(); i++) {
                            var slot = refs[i].uniqueIdentifier;
                            var id = refs[i].complicationId;
                            if (slot != null && slot >= 1 && slot <= ids.size() && id != null) {
                                ids[slot - 1] = id;
                            }
                        }
                    }
                }
            }
            var bedside = Application.Properties.getValue("Bedside");
            return [style, lift(accent), data, ids, (bedside instanceof Boolean) ? bedside : true];
        }

        // The settings as the look `mode` has them: high visibility and low
        // light in the first typeface, a persona in the face's own choice
        // (`styles`, one per persona); the readings and bedside clock as set
        function look(s as Settings, mode as Number, styles as Array<Number>) as Settings {
            if (mode == Look.BRIGHT) {
                return [0, Look.BLAZE, Look.WHITE, s[3], s[4]];
            }
            if (mode == Look.LOW) {
                return [0, Look.GLOW, Look.CREAM, s[3], s[4]];
            }
            if (mode == Look.DAILY) {
                var p = Look.day(PERSONAS.size());
                return [styles[p], PERSONAS[p][0], PERSONAS[p][1], s[3], s[4]];
            }
            return s;
        }

        // Icons' and quiet text's share of the data colour in a look
        function quiet(mode as Number) as Float {
            return (mode == Look.BRIGHT) ? 1.0 : ((mode == Look.LOW) ? 0.85 : QUIET);
        }

        function changedOnPhone() as Void {
            Application.Storage.setValue(SOURCE, PHONE);
            Look.changedOnPhone();
        }

        function changedInEditor() as Void {
            Application.Storage.setValue(SOURCE, EDITOR);
        }

        // A number property within 0..most, else the fallback
        function number(key as String, fallback as Number, most as Number) as Number {
            var value = Application.Properties.getValue(key);
            return (value instanceof Number && value >= 0 && value <= most) ? value : fallback;
        }

        // The accent as drawn: a dark pick is first brightened until its
        // strongest channel is full, then taken a quarter of the way to white
        // at a time until it holds its own beside the data colours (navy
        // becomes 0x9393FF, not a dusty lavender)
        function lift(color as Number) as Number {
            var r = (color >> 16) & 0xFF;
            var g = (color >> 8) & 0xFF;
            var b = color & 0xFF;
            if (luminance(r, g, b) >= LIGHT) {
                return color;
            }
            var top = (r > g) ? ((r > b) ? r : b) : ((g > b) ? g : b);
            if (top > 0) {
                r = r * 255 / top;
                g = g * 255 / top;
                b = b * 255 / top;
            }
            for (var i = 0; i < 12 && luminance(r, g, b) < LIGHT; i++) {
                r += (255 - r) / 4;
                g += (255 - g) / 4;
                b += (255 - b) / 4;
            }
            return (r << 16) | (g << 8) | b;
        }

        // Relative luminance, near enough (gamma 2)
        function luminance(r as Number, g as Number, b as Number) as Float {
            var fr = r / 255.0;
            var fg = g / 255.0;
            var fb = b / 255.0;
            return 0.2126 * fr * fr + 0.7152 * fg * fg + 0.0722 * fb * fb;
        }

        // A colour at `f` of its brightness
        function scale(color as Number, f as Float) as Number {
            var r = (((color >> 16) & 0xFF) * f).toNumber();
            var g = (((color >> 8) & 0xFF) * f).toNumber();
            var b = ((color & 0xFF) * f).toNumber();
            r = (r > 255) ? 255 : r;
            g = (g > 255) ? 255 : g;
            b = (b > 255) ? 255 : b;
            return (r << 16) | (g << 8) | b;
        }
    }
}
