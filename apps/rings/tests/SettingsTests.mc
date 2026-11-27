import Toybox.Application;
import Toybox.Application.WatchFaceConfig;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

// The settings on the watch and the phone (Choices, generated with the
// phone list): the watch's menu (Lib.WatchMenu) is the phone's list and
// writes its properties; the phone and the watch face editor each take,
// whichever was changed last winning (the editor used to win always, so a
// colour set chosen on the phone did nothing on a fēnix 8). Every look in
// every colour set draws, awake and always-on.

function ringsClean() as Void {
    Application.Properties.setValue("Theme", 0);
    Application.Properties.setValue("Look", Lib.Look.YOURS);
    Application.Storage.deleteValue(Lib.Look.KEY);
    Application.Storage.deleteValue(Lib.Look.SEEN);
    Application.Storage.deleteValue(Lib.Config.SOURCE);
}

(:test)
function testRingsMenuAndEditor(logger as Logger) as Boolean {
    ringsClean();
    var w = System.getDeviceSettings().screenWidth;
    var h = System.getDeviceSettings().screenHeight;
    var dc = (Graphics.createBufferedBitmap({:width => w, :height => h}).get() as Graphics.BufferedBitmap).getDc();
    var entries = Choices.entries();
    Test.assertEqualMessage(entries.size(), 2, "look, colour set");
    for (var i = 0; i < Lib.Look.MODES; i++) {
        Test.assertEqualMessage(entries[0][3][i], Lib.Look.ORDER[i], "the menu's looks in the hold's order");
    }
    Test.assertEqualMessage(entries[1][3].size(), 3, "the three sets, as the editor's styles");
    Test.assertEqualMessage(Lib.WatchMenu.current(entries[1]), 0, "Sunset shown");

    var editor = (Application has :WatchFaceConfig) && WatchFaceConfig.getSettings(null) != null;
    var view = new RingsView();
    view.onLayout(dc);
    var sunset = Themes.colors(Themes.SUNSET)[0];
    var forest = Themes.colors(Themes.FOREST)[0];
    Test.assertEqualMessage(view.colors()[0], sunset, "Sunset to begin with");
    Lib.WatchMenu.choose(entries[1], 2);            // the menu: Forest, as the phone would
    Test.assertEqualMessage(Application.Properties.getValue("Theme"), 2, "the menu writes the phone's property");
    view.reloadSettings();
    Test.assertEqualMessage(view.colors()[0], forest, "the phone's, changed last");
    Lib.Config.changedInEditor();                  // as the delegate's onWatchFaceConfigEdited
    view.reloadSettings();
    Test.assertEqualMessage(view.colors()[0], editor ? sunset : forest, "the editor's (its default in the simulator), changed since");
    Lib.Config.changedOnPhone();
    view.reloadSettings();
    Test.assertEqualMessage(view.colors()[0], forest, "the phone's again");

    for (var t = 0; t < 3; t++) {
        Application.Properties.setValue("Theme", t);
        for (var m = 0; m < Lib.Look.MODES; m++) {
            Application.Storage.setValue(Lib.Look.KEY, Lib.Look.ORDER[m]);
            view.reloadSettings();
            view.onUpdate(dc);
            view.onEnterSleep();
            view.onUpdate(dc);
            view.onExitSleep();
        }
    }
    logger.debug(editor ? "the editor's defaults read" : "no watch face editor on this watch");
    ringsClean();
    return true;
}
