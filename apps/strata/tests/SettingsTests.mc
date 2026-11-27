import Toybox.Application;
import Toybox.Application.WatchFaceConfig;
import Toybox.Lang;
import Toybox.Test;

// The settings on the watch and the phone (Choices, generated with the
// phone list): the watch's menu (Lib.WatchMenu) is the phone's list and
// writes its properties, switches included; the phone and the watch face
// editor each take, whichever was changed last winning (the editor used to
// win always, so the strata chosen on the phone did nothing on a fēnix 8).
// testStrataDrawsBothModes draws every colour and every look.

function strataClean() as Void {
    Application.Properties.setValue("Strata", 0);
    Application.Properties.setValue("TimeColor", 0);
    Application.Properties.setValue("TimeStyle", 0);
    Application.Properties.setValue("Stones", true);
    Application.Properties.setValue("Look", Lib.Look.YOURS);
    Application.Storage.deleteValue(Lib.Look.KEY);
    Application.Storage.deleteValue(Lib.Look.SEEN);
    Application.Storage.deleteValue(Lib.Config.SOURCE);
}

(:test)
function testStrataMenuAndEditor(logger as Logger) as Boolean {
    strataClean();
    var entries = Choices.entries();
    Test.assertEqualMessage(entries.size(), 11, "look, four readings, strata, accent, time colour, time style, two switches");
    for (var i = 0; i < Lib.Look.MODES; i++) {
        Test.assertEqualMessage(entries[0][3][i], Lib.Look.ORDER[i], "the menu's looks in the hold's order");
    }
    for (var n = 0; n < entries.size(); n++) {
        Test.assertEqualMessage(entries[n][2].size(), entries[n][3].size(), "labels and values " + n);
    }
    Test.assertEqualMessage(entries[5][3].size(), Choices.STRATA.size(), "the strata: the editor's accent colours");
    Test.assertEqualMessage(entries[7][3].size(), Choices.TIME_COLOR.size(), "the time colours: the editor's data colours");
    Test.assertEqualMessage(Lib.WatchMenu.current(entries[2]), 1, "the second reading: the chance of rain");
    Lib.WatchMenu.choose(entries[10], 1);           // a switch: no stones
    Test.assertEqualMessage(Application.Properties.getValue("Stones"), false, "the menu writes a switch");
    Application.Properties.setValue("Stones", true);

    var editor = (Application has :WatchFaceConfig) && WatchFaceConfig.getSettings(null) != null;
    var view = new StrataView();
    var c = view.chosen();
    Test.assertMessage(c[0] == 0 && c[1] == 0 && c[2] == 0, "Soil, Bone, filled to begin with");
    Lib.WatchMenu.choose(entries[5], 3);            // the menu: Slate, as the phone would
    Lib.WatchMenu.choose(entries[7], 4);            // Lichen
    Lib.WatchMenu.choose(entries[8], 1);            // in outline
    view.reloadSettings();
    c = view.chosen();
    Test.assertMessage(c[0] == 3 && c[1] == 4 && c[2] == 1, "the phone's, changed last");
    Lib.Config.changedInEditor();                  // as the delegate's onWatchFaceConfigEdited
    view.reloadSettings();
    c = view.chosen();
    if (editor) {
        Test.assertMessage(c[0] == 0 && c[1] == 0 && c[2] == 0, "the editor's (its defaults in the simulator), changed since");
    } else {
        Test.assertMessage(c[0] == 3 && c[1] == 4 && c[2] == 1, "no editor: the phone's");
    }
    Lib.Config.changedOnPhone();
    view.reloadSettings();
    c = view.chosen();
    Test.assertMessage(c[0] == 3 && c[1] == 4 && c[2] == 1, "the phone's again");
    logger.debug(editor ? "the editor's defaults read" : "no watch face editor on this watch");
    strataClean();
    return true;
}
