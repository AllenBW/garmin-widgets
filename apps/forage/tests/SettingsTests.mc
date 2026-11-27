import Toybox.Application;
import Toybox.Application.WatchFaceConfig;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

// The settings on the watch and the phone (Choices, generated with the
// phone list): every look with every honey and time colour draws, awake
// and always-on; the watch's menu (Lib.WatchMenu) is the phone's list and
// writes its properties; the phone and the watch face editor each take,
// whichever was changed last winning.

function forageClean() as Void {
    Application.Properties.setValue("Honey", 0);
    Application.Properties.setValue("TimeColor", 0);
    Application.Properties.setValue("Look", Lib.Look.YOURS);
    Application.Storage.deleteValue(Lib.Look.KEY);
    Application.Storage.deleteValue(Lib.Look.SEEN);
    Application.Storage.deleteValue(Lib.Config.SOURCE);
}

(:test)
function testForageEveryLookAndColour(logger as Logger) as Boolean {
    forageClean();
    var w = System.getDeviceSettings().screenWidth;
    var h = System.getDeviceSettings().screenHeight;
    var dc = (Graphics.createBufferedBitmap({:width => w, :height => h}).get() as Graphics.BufferedBitmap).getDc();
    var view = new ForageView();
    view.onLayout(dc);
    view.onUpdate(dc);
    Test.assertMessage(view.colors()[0] == 0xFFC94A && view.colors()[1] == 0xF2ECE2, "the defaults: today's wax and cream");
    Test.assertMessage(view.timeAt(w / 2, (h * 0.3).toNumber()), "a hold on the time: the looks");
    Test.assertMessage(!view.timeAt(w / 2, (h * 0.7).toNumber()), "a hold on the comb: the weather");
    Lib.Config.changedOnPhone();
    for (var c = 0; c < Choices.HONEY.size(); c++) {
        Application.Properties.setValue("Honey", c);
        Application.Properties.setValue("TimeColor", (c + 1) % Choices.TIME_COLOR.size());
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
        Test.assertMessage(view.colors()[0] == Choices.HONEY[c] && view.colors()[1] == Choices.TIME_COLOR[(c + 1) % Choices.TIME_COLOR.size()], "honey " + c);
    }
    forageClean();
    return true;
}

(:test)
function testForageMenuAndEditor(logger as Logger) as Boolean {
    forageClean();
    var entries = Choices.entries();
    Test.assertEqualMessage(entries.size(), 3, "look, honey, time colour");
    for (var i = 0; i < Lib.Look.MODES; i++) {
        Test.assertEqualMessage(entries[0][3][i], Lib.Look.ORDER[i], "the menu's looks in the hold's order");
    }
    for (var n = 0; n < entries.size(); n++) {
        Test.assertEqualMessage(entries[n][2].size(), entries[n][3].size(), "labels and values " + n);
        Test.assertEqualMessage(Lib.WatchMenu.current(entries[n]), 0, "the default shown first " + n);
    }
    Test.assertEqualMessage(entries[1][3].size(), Choices.HONEY.size(), "the menu has the editor's honeys");
    Test.assertEqualMessage(entries[2][3].size(), Choices.TIME_COLOR.size(), "and its time colours");

    var editor = (Application has :WatchFaceConfig) && WatchFaceConfig.getSettings(null) != null;
    var view = new ForageView();
    Lib.WatchMenu.choose(entries[1], 2);            // the menu: Heather, as the phone would
    Test.assertEqualMessage(Application.Properties.getValue("Honey"), 2, "the menu writes the phone's property");
    view.reloadSettings();
    Test.assertEqualMessage(view.colors()[0], 0xF0A040, "the phone's, changed last");
    Lib.Config.changedInEditor();                  // as the delegate's onWatchFaceConfigEdited
    view.reloadSettings();
    Test.assertEqualMessage(view.colors()[0], editor ? 0xFFC94A : 0xF0A040, "the editor's (its default in the simulator), changed since");
    Lib.Config.changedOnPhone();
    view.reloadSettings();
    Test.assertEqualMessage(view.colors()[0], 0xF0A040, "the phone's again");
    logger.debug(editor ? "the editor's defaults read" : "no watch face editor on this watch");
    forageClean();
    return true;
}
