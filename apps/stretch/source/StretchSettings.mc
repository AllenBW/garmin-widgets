import Toybox.Application.Properties;
import Toybox.Lang;

// The settings from the phone (resources/settings), each with its default
// when a value is missing or odd. Shared by the glance and the app.
(:glance)
module StretchSettings {

    const LEVELS = [75, 100, 150] as Array<Number>;

    function number(key as String, fallback as Number) as Number {
        try {
            var v = Properties.getValue(key);
            if (v instanceof Number) {
                return v;
            }
        } catch (e) {
        }
        return fallback;
    }

    function bool(key as String, fallback as Boolean) as Boolean {
        try {
            var v = Properties.getValue(key);
            if (v instanceof Boolean) {
                return v;
            }
        } catch (e) {
        }
        return fallback;
    }

    // 0 gentle, 1 standard, 2 deep
    function levelIndex() as Number {
        var i = number("Level", 1);
        return i < 0 || i > 2 ? 1 : i;
    }

    // Percent of each hold
    function level() as Number {
        return LEVELS[levelIndex()];
    }

    function contractRelax() as Boolean {
        return bool("ContractRelax", false);
    }

    function record() as Boolean {
        return bool("Record", true);
    }

    function tones() as Boolean {
        return bool("Tones", false);
    }
}
