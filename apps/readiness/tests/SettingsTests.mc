import Toybox.Application;
import Toybox.Application.WatchFaceConfig;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

// The settings on the watch and the phone (Choices, generated with the
// phone list): every look in every colour draws, awake and always-on; the
// watch's menu is the phone's list and writes its properties; the phone and
// the watch face editor each take, whichever was changed last winning.

function readinessClean() as Void {
    Application.Properties.setValue("Accent", 0);
    Application.Properties.setValue("DataColor", 0);
    Application.Properties.setValue("Look", Lib.Look.YOURS);
    Application.Storage.deleteValue(Lib.Look.KEY);
    Application.Storage.deleteValue(Lib.Look.SEEN);
    Application.Storage.deleteValue(Lib.Config.SOURCE);
}

(:test)
function testReadinessEveryLookAndColour(logger as Logger) as Boolean {
    readinessClean();
    var w = System.getDeviceSettings().screenWidth;
    var h = System.getDeviceSettings().screenHeight;
    var dc = (Graphics.createBufferedBitmap({:width => w, :height => h}).get() as Graphics.BufferedBitmap).getDc();
    var view = new ReadinessView();
    view.onLayout(dc);
    var r = new Readings();
    r.bodyBattery = 74;
    r.stress = 28;
    r.sleepScore = 82;
    r.trainingStatus = "Productive";
    view.setReadings(r);
    view.onUpdate(dc);
    Test.assertMessage(view.timeAt(w / 2, (h * 0.44).toNumber()), "a hold on the time: the looks");
    Test.assertMessage(!view.timeAt((w * 0.12).toNumber(), h / 2), "a hold on the gauge: its widget");
    Test.assertMessage(view.colors()[0] == 0x46D18A && view.colors()[1] == 0xFF7A3D, "the defaults: today's green and orange");

    Lib.Config.changedOnPhone();
    for (var c = 0; c < Choices.ACCENT.size(); c++) {
        Application.Properties.setValue("Accent", c);
        Application.Properties.setValue("DataColor", (c + 2) % Choices.DATA_COLOR.size());
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
        Test.assertMessage(view.colors()[0] == Choices.ACCENT[c] && view.colors()[1] == Choices.DATA_COLOR[(c + 2) % Choices.DATA_COLOR.size()], "colour " + c);
    }
    readinessClean();
    return true;
}

(:test)
function testReadinessMenuAndEditor(logger as Logger) as Boolean {
    readinessClean();
    var entries = Choices.entries();
    Test.assertEqualMessage(entries.size(), 3, "look, Body Battery, stress");
    for (var i = 0; i < Lib.Look.MODES; i++) {
        Test.assertEqualMessage(entries[0][3][i], Lib.Look.ORDER[i], "the menu's looks in the hold's order");
    }
    for (var n = 0; n < entries.size(); n++) {
        Test.assertEqualMessage(entries[n][2].size(), entries[n][3].size(), "labels and values " + n);
        Test.assertEqualMessage(Lib.WatchMenu.current(entries[n]), 0, "the default shown first " + n);
    }
    Test.assertEqualMessage(entries[1][3].size(), Choices.ACCENT.size(), "the menu has the editor's colours");
    Test.assertEqualMessage(entries[2][3].size(), Choices.DATA_COLOR.size(), "both lists");

    var editor = (Application has :WatchFaceConfig) && WatchFaceConfig.getSettings(null) != null;
    var view = new ReadinessView();
    Lib.WatchMenu.choose(entries[1], 3);            // the menu: Blue, as the phone would
    Test.assertEqualMessage(Application.Properties.getValue("Accent"), 3, "the menu writes the phone's property");
    Test.assertMessage(Lib.Config.PHONE.equals(Application.Storage.getValue(Lib.Config.SOURCE)), "and is a phone change");
    view.reloadSettings();
    Test.assertEqualMessage(view.colors()[0], 0x38A8FF, "the phone's choice, changed last");
    Lib.Config.changedInEditor();                  // as the delegate's onWatchFaceConfigEdited
    view.reloadSettings();
    Test.assertEqualMessage(view.colors()[0], editor ? 0x46D18A : 0x38A8FF, "the editor's (its default in the simulator), changed since");
    Lib.Config.changedOnPhone();
    view.reloadSettings();
    Test.assertEqualMessage(view.colors()[0], 0x38A8FF, "the phone's again");
    Lib.WatchMenu.choose(entries[0], 4);            // low light
    Test.assertEqualMessage(Lib.Look.mode(), Lib.Look.LOW, "the menu's look is on");
    logger.debug(editor ? "the editor's defaults read" : "no watch face editor on this watch");
    readinessClean();
    return true;
}
