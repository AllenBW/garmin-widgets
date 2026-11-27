import Toybox.Application;
import Toybox.Application.WatchFaceConfig;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

// The settings on the watch and the phone (Choices, generated with the
// phone list): every look in every accent draws, awake and always-on; the
// watch's menu (Lib.WatchMenu) is the phone's list and writes its
// properties, a switch included; the phone and the watch face editor each
// take, whichever was changed last winning.

function fieldClean() as Void {
    Application.Properties.setValue("AccentColor", 0xFFB020);
    Application.Properties.setValue("Ring", 3);
    Application.Properties.setValue("Signals", true);
    Application.Properties.setValue("Look", Lib.Look.YOURS);
    Application.Storage.deleteValue(Lib.Look.KEY);
    Application.Storage.deleteValue(Lib.Look.SEEN);
    Application.Storage.deleteValue(Lib.Config.SOURCE);
}

(:test)
function testFieldEveryLookAndAccent(logger as Logger) as Boolean {
    fieldClean();
    var w = System.getDeviceSettings().screenWidth;
    var h = System.getDeviceSettings().screenHeight;
    var dc = (Graphics.createBufferedBitmap({:width => w, :height => h}).get() as Graphics.BufferedBitmap).getDc();
    var view = new FieldView();
    view.onLayout(dc);
    view.onUpdate(dc);
    Test.assertMessage(view.chosen()[0] == 0xFFB020 && view.chosen()[1] == 3, "the defaults: amber, the daylight ring");
    var entries = Choices.entries();
    var accents = entries[1][3] as Array<Number>;
    Lib.Config.changedOnPhone();
    for (var c = 0; c < accents.size(); c++) {
        Application.Properties.setValue("AccentColor", accents[c]);
        for (var m = 0; m < Lib.Look.MODES; m++) {
            Application.Storage.setValue(Lib.Look.KEY, Lib.Look.ORDER[m]);
            view.reloadSettings();
            view.onUpdate(dc);
            view.onEnterSleep();
            view.onUpdate(dc);
            view.onExitSleep();
        }
        Application.Storage.deleteValue(Lib.Look.KEY);
        view.reloadSettings();
        Test.assertEqualMessage(view.chosen()[0], accents[c], "accent " + c);
    }
    fieldClean();
    return true;
}

(:test)
function testFieldMenuAndEditor(logger as Logger) as Boolean {
    fieldClean();
    var entries = Choices.entries();
    Test.assertEqualMessage(entries.size(), 8, "look, accent, ring, three slots, alerts, footer");
    for (var i = 0; i < Lib.Look.MODES; i++) {
        Test.assertEqualMessage(entries[0][3][i], Lib.Look.ORDER[i], "the menu's looks in the hold's order");
    }
    for (var n = 0; n < entries.size(); n++) {
        Test.assertEqualMessage(entries[n][2].size(), entries[n][3].size(), "labels and values " + n);
    }
    Test.assertEqualMessage(Lib.WatchMenu.current(entries[1]), 0, "amber shown");
    Test.assertEqualMessage(Lib.WatchMenu.current(entries[2]), 0, "the daylight ring shown first");
    Test.assertEqualMessage(Lib.WatchMenu.current(entries[4]), 1, "the middle slot: steps");
    Test.assertEqualMessage(Lib.WatchMenu.current(entries[6]), 0, "the alerts on");
    Lib.WatchMenu.choose(entries[6], 1);            // a switch: the alerts off
    Test.assertEqualMessage(Application.Properties.getValue("Signals"), false, "the menu writes a switch");
    Test.assertEqualMessage(Lib.WatchMenu.current(entries[6]), 1, "and shows it off");
    Application.Properties.setValue("Signals", true);

    var editor = (Application has :WatchFaceConfig) && WatchFaceConfig.getSettings(null) != null;
    var view = new FieldView();
    Lib.WatchMenu.choose(entries[2], 2);            // the menu: the battery ring, as the phone would
    Test.assertEqualMessage(Application.Properties.getValue("Ring"), 1, "the menu writes the phone's property");
    Lib.WatchMenu.choose(entries[1], 1);            // and cyan
    Test.assertMessage(Lib.Config.PHONE.equals(Application.Storage.getValue(Lib.Config.SOURCE)), "a phone change");
    view.reloadSettings();
    Test.assertMessage(view.chosen()[0] == 0x3EC6E0 && view.chosen()[1] == 1, "the phone's, changed last");
    Lib.Config.changedInEditor();                  // as the delegate's onWatchFaceConfigEdited
    view.reloadSettings();
    if (editor) {
        Test.assertMessage(view.chosen()[0] == 0xFFB020 && view.chosen()[1] == 3, "the editor's (its defaults in the simulator), changed since");
    } else {
        Test.assertMessage(view.chosen()[0] == 0x3EC6E0 && view.chosen()[1] == 1, "no editor: the phone's");
    }
    Lib.Config.changedOnPhone();
    view.reloadSettings();
    Test.assertMessage(view.chosen()[0] == 0x3EC6E0 && view.chosen()[1] == 1, "the phone's again");
    logger.debug(editor ? "the editor's defaults read" : "no watch face editor on this watch");
    fieldClean();
    return true;
}
