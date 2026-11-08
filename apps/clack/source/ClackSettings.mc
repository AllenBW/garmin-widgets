import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Application.WatchFaceConfig;
import Toybox.Lang;

// Clack's settings, from two places with the same list: the phone app's
// settings (resources/settings: Style, Date) and the fēnix 8's watch face
// editor (resources/configs/watchface.xml: the styles). Whichever was
// changed last wins, as Lib.Config does for the other faces: the app calls
// changedOnPhone from onSettingsChanged, the delegate changedInEditor from
// onWatchFaceConfigEdited. Until either is changed, the editor's.
module ClackSettings {

    const SOURCE = "Source";
    const PHONE = "phone";
    const EDITOR = "editor";

    // The view: a Layout style
    function style() as Number {
        var style = number("Style", 1, Layout.STYLES - 1);
        if (editorWins() && Application has :WatchFaceConfig && !PHONE.equals(Storage.getValue(SOURCE))) {
            var config = WatchFaceConfig.getSettings(null);
            if (config != null) {
                var id = config.styleId;
                if (id != null && id >= 0 && id < Layout.STYLES) {
                    style = id;
                }
            }
        }
        return style;
    }

    // The date slip shown
    function date() as Boolean {
        var value = Application.Properties.getValue("Date");
        return (value instanceof Boolean) ? value : true;
    }

    // The screenshot builds take the view from the phone's property alone
    // (the editor's default would win otherwise)
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
    }

    // A touch and hold on the face: the next style, round. It is kept as
    // the phone's setting (the property), which wins over the editor's
    // until the editor is next used, as a change on the phone does
    function nextStyle() as Number {
        var next = (style() + 1) % Layout.STYLES;
        Application.Properties.setValue("Style", next);
        changedOnPhone();
        return next;
    }

    function changedInEditor() as Void {
        Storage.setValue(SOURCE, EDITOR);
    }

    // A number property within 0..most, else the fallback
    function number(key as String, fallback as Number, most as Number) as Number {
        var value = Application.Properties.getValue(key);
        return (value instanceof Number && value >= 0 && value <= most) ? value : fallback;
    }
}
