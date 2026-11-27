import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Application.WatchFaceConfig;
import Toybox.Lang;

// Clack's settings, from two places with the same list: the phone app's
// settings, which the watch's own settings menu writes too (resources/
// settings: Style, Accent, DataColor, Date), and the fēnix 8's watch face
// editor (resources/configs/watchface.xml: the styles, the accent colours
// and the data colours). Whichever was changed last wins, as Lib.Config does
// for the other faces: the app calls changedOnPhone from onSettingsChanged,
// the delegate changedInEditor from onWatchFaceConfigEdited. Until either is
// changed, the editor's. The look (Lib.Look) is the phone's and the hold's.
module ClackSettings {

    const SOURCE = "Source";
    const PHONE = "phone";
    const EDITOR = "editor";

    // [the view (a Layout style), the leaves' plastic (its place in
    // Choices.LEAVES), the digits' ink (its place in Choices.DIGITS)]
    function read() as [Number, Number, Number] {
        var style = number("Style", 1, Layout.STYLES - 1);
        var leaf = number("Accent", 0, Choices.LEAVES.size() - 1);
        var digit = number("DataColor", 0, Choices.DIGITS.size() - 1);
        if (editorWins() && Application has :WatchFaceConfig && !PHONE.equals(Storage.getValue(SOURCE))) {
            var config = WatchFaceConfig.getSettings(null);
            if (config != null) {
                var id = config.styleId;
                if (id != null && id >= 0 && id < Layout.STYLES) {
                    style = id;
                }
                var picked = config.accentColor;
                if (picked != null && picked.color != null) {
                    leaf = nearest(picked.color as Number, Choices.LEAVES);
                }
                picked = config.complicationColor;
                if (picked != null && picked.color != null) {
                    digit = nearest(picked.color as Number, Choices.DIGITS);
                }
            }
        }
        return [style, leaf, digit];
    }

    // The date slip shown
    function date() as Boolean {
        var value = Application.Properties.getValue("Date");
        return (value instanceof Boolean) ? value : true;
    }

    // The screenshot builds take the settings from the phone's properties
    // alone (the editor's defaults would win otherwise)
    (:live)
    function editorWins() as Boolean {
        return true;
    }

    (:sample)
    function editorWins() as Boolean {
        return false;
    }

    function changedOnPhone() as Void {
        Storage.setValue(SOURCE, PHONE);
        Lib.Look.changedOnPhone();
    }

    function changedInEditor() as Void {
        Storage.setValue(SOURCE, EDITOR);
    }

    // A number property within 0..most, else the fallback
    function number(key as String, fallback as Number, most as Number) as Number {
        var value = Application.Properties.getValue(key);
        return (value instanceof Number && value >= 0 && value <= most) ? value : fallback;
    }

    // The place in `list` of the colour nearest `color`: the editor offers
    // only the list's, so this is the one picked
    function nearest(color as Number, list as Array<Number>) as Number {
        var best = 0;
        var least = -1;
        for (var i = 0; i < list.size(); i++) {
            var d = 0;
            for (var shift = 16; shift >= 0; shift -= 8) {
                var e = ((color >> shift) & 0xFF) - ((list[i] >> shift) & 0xFF);
                d += e * e;
            }
            if (least < 0 || d < least) {
                least = d;
                best = i;
            }
        }
        return best;
    }
}
