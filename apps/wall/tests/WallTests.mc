import Toybox.Application;
import Toybox.Application.WatchFaceConfig;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;
import Toybox.Time;

// Run No Evil tests for Wall: scripts/test.sh wall [device]. Lib.Numbers is
// tested with Blocks.

// Update until the wall is all drawn, as the frames would
function wallFill(view as WallView, dc as Dc) as Void {
    for (var i = 0; i < 10 && !view.built(); i++) {
        view.onUpdate(dc);
    }
    view.onUpdate(dc);
}

(:test)
function testWallDrawsEveryMode(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var dc = (Graphics.createBufferedBitmap({:width => settings.screenWidth, :height => settings.screenHeight}).get()
              as Graphics.BufferedBitmap).getDc();

    var view = new WallView();
    view.onLayout(dc);

    // Whatever the simulator provides
    var started = System.getTimer();
    wallFill(view, dc);
    logger.debug("awake, the wall filling: " + (System.getTimer() - started) + " ms");
    Test.assertMessage(view.built(), "the wall fills within ten frames");

    // Nothing yet, the samples, and the widest of everything
    view.setValues(["1/1", "00", "00", "--:--", "--:--", "--", "--", "--", "--", "--", "--", "--", "--"] as Array<String>);
    wallFill(view, dc);
    view.setValues(["10/31", "21", "05", "07:12", "10:07", "28°", "41", "24", "58", "11382", "47", "1240", "6"] as Array<String>);
    wallFill(view, dc);
    view.setValues(["11/11", "11", "11", "17:01", "11:11", "-12°", "-4", "-19", "148", "21114", "100", "11240", "31"] as Array<String>);
    wallFill(view, dc);
    started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("awake, from the bitmaps: " + (System.getTimer() - started) + " ms");

    // Standby
    view.setAwake(false);
    started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("standby: " + (System.getTimer() - started) + " ms");
    view.setAwake(true);
    view.onUpdate(dc);

    var stats = System.getSystemStats();
    logger.debug("memory: " + stats.usedMemory + " of " + stats.totalMemory + " bytes used");
    return true;
}

// A start: the time alone first, the wall behind it two frames on, and the
// time drawn just twice. A wake within the minute draws nothing again.
(:test)
function testWallLights(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var dc = (Graphics.createBufferedBitmap({:width => settings.screenWidth, :height => settings.screenHeight}).get()
              as Graphics.BufferedBitmap).getDc();
    var view = new WallView();
    view.onLayout(dc);
    var minute = Time.now().value() / 60;
    view.onUpdate(dc);
    Test.assertEqualMessage(view.composed, 1, "the first frame draws the time");
    Test.assertMessage(!view.built() && !view.settled(), "and not the wall");
    wallFill(view, dc);
    Test.assertMessage(view.built() && view.settled(), "the wall, whole");
    var composed = view.composed;
    view.onUpdate(dc);
    Test.assertEqualMessage(view.composed, composed, "a settled frame draws nothing again");
    view.onEnterSleep();
    view.onUpdate(dc);
    view.onExitSleep();
    view.onUpdate(dc);
    Test.assertMessage(view.settled(), "settled again in the wake's first frame");
    if (Time.now().value() / 60 == minute) {    // (the minute didn't turn while the test ran)
        Test.assertEqualMessage(composed, 1 + 1, "the time drawn twice on a start");
        Test.assertEqualMessage(view.composed, composed, "a wake within the minute draws the time again nowhere");
    }
    return true;
}

// The band's readings open their widgets; everywhere else the looks
(:test)
function testWallTargets(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var w = settings.screenWidth;
    var dc = (Graphics.createBufferedBitmap({:width => w, :height => settings.screenHeight}).get() as Graphics.BufferedBitmap).getDc();
    var view = new WallView();
    view.onLayout(dc);
    view.setValues(["10/31", "14", "38", "19:22", "4:44", "46°", "52", "38", "72", "6214", "82", "1240", "12"] as Array<String>);
    view.onUpdate(dc);
    view.onUpdate(dc);           // the band comes the frame after the time
    Test.assertMessage(view.targetAt((w * 0.5).toNumber(), (w * 0.25).toNumber()) == null, "the time is no target");
    Test.assertMessage(view.targetAt((w * 0.10).toNumber(), (w * 0.5).toNumber()) == Complications.COMPLICATION_TYPE_CALENDAR_EVENTS, "the date");
    Test.assertMessage(view.targetAt((w * 0.92).toNumber(), (w * 0.5).toNumber()) == Complications.COMPLICATION_TYPE_HEART_RATE, "heart rate");
    return true;
}

// Every look draws, awake and in standby, the look's name for a moment
(:test)
function testWallLooks(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var dc = (Graphics.createBufferedBitmap({:width => settings.screenWidth, :height => settings.screenHeight}).get()
              as Graphics.BufferedBitmap).getDc();
    var view = new WallView();
    view.onLayout(dc);
    Application.Storage.setValue(Lib.Look.KEY, Lib.Look.LOW);
    for (var m = 0; m < Lib.Look.MODES; m++) {
        Test.assertEqualMessage(Lib.Look.next(), Lib.Look.ORDER[(Lib.Look.ORDER.indexOf(Lib.Look.LOW) + m + 1) % Lib.Look.MODES], "the next look");
        view.reloadSettings();
        wallFill(view, dc);
        view.setAwake(false);
        view.onUpdate(dc);
        view.setAwake(true);
    }
    Application.Storage.deleteValue(Lib.Look.KEY);
    return true;
}

// The generated tables: every digit lights something in each block, within
// the grid, and its edge is part of what it lights
(:test)
function testWallNumerals(logger as Logger) as Boolean {
    for (var b = 0; b < 2; b++) {
        Test.assertEqualMessage(Numerals.LIT[b].size(), 10, "ten digits");
        for (var d = 0; d < 10; d++) {
            var lit = Numerals.LIT[b][d];
            var edge = Numerals.EDGE[b][d];
            Test.assertEqualMessage(lit.size(), Numerals.COUNT[b], "a row per grid row");
            var cells = 0;
            for (var r = 0; r < lit.size(); r++) {
                Test.assertEqualMessage(edge[r] & lit[r], edge[r], "the edge is lit");
                Test.assertMessage(lit[r] < (1 << LIT_RUN), "a run of lit cells fits the strip");
                for (var bits = lit[r]; bits != 0; bits = bits >> 1) {
                    cells += bits & 1;
                }
            }
            Test.assertMessage(cells > 10, "digit " + d + " lights cells");
        }
    }
    return true;
}

// Your look in every set of the families' colours and every colour for the
// time, awake and in standby; the defaults are the face's own colours
(:test)
function testWallColors(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var dc = (Graphics.createBufferedBitmap({:width => settings.screenWidth, :height => settings.screenHeight}).get()
              as Graphics.BufferedBitmap).getDc();
    var c = Lib.Numbers.yours(0, Lib.Config.DATA[0]);
    var own = Lib.Numbers.colors(Lib.Look.YOURS);
    Test.assertMessage(c.neutral == own.neutral && c.sun == own.sun && c.weather == own.weather && c.body == own.body
                       && c.second == own.second && c.third == own.third && !c.fluorescent, "the defaults are the face's own");
    Test.assertEqualMessage(Lib.Numbers.yours(99, 0x123456).sun, own.sun, "a set out of range is Classic");

    var look = Application.Storage.getValue(Lib.Look.KEY);
    var source = Application.Storage.getValue(Lib.Config.SOURCE);
    Application.Storage.setValue(Lib.Look.KEY, Lib.Look.YOURS);
    var view = new WallView();
    view.onLayout(dc);
    for (var p = 0; p < Lib.Numbers.PALETTES.size(); p++) {
        for (var d = 0; d < Lib.Config.DATA.size(); d++) {
            if (d != p % Lib.Config.DATA.size() && p > 0) {
                continue;                          // every set once, and every colour for the time with Classic
            }
            Application.Properties.setValue("Style", p);
            Application.Properties.setValue("DataColor", d);
            Lib.Config.changedOnPhone();
            view.reloadSettings();
            wallFill(view, dc);
            view.setAwake(false);
            view.onUpdate(dc);
            view.setAwake(true);
            var s = Lib.Config.read(Lib.Numbers.PALETTES.size(), [] as Array<Complications.Type>);
            Test.assertMessage(s[0] == p && s[2] == Lib.Config.DATA[d], "the phone's colours are read");
            var drawn = Lib.Numbers.yours(s[0], s[2]);
            Test.assertMessage(drawn.sun == Lib.Numbers.PALETTES[p][0] && drawn.neutral == Lib.Config.DATA[d], "and drawn");
        }
    }
    Application.Properties.setValue("Style", 0);
    Application.Properties.setValue("DataColor", 0);
    WallHelp.restore(look, source);
    return true;
}

// A change in the phone app (or the watch's settings menu) and one in the
// watch face editor each take, the later winning
(:test)
function testWallPhoneAndEditor(logger as Logger) as Boolean {
    var look = Application.Storage.getValue(Lib.Look.KEY);
    var source = Application.Storage.getValue(Lib.Config.SOURCE);
    Application.Properties.setValue("Style", 3);
    Application.Properties.setValue("DataColor", 2);
    Lib.Config.changedOnPhone();
    var s = Lib.Config.read(Lib.Numbers.PALETTES.size(), [] as Array<Complications.Type>);
    Test.assertMessage(s[0] == 3 && s[2] == Lib.Config.DATA[2], "the phone changed last: Orchard and Sand");
    Lib.Config.changedInEditor();
    s = Lib.Config.read(Lib.Numbers.PALETTES.size(), [] as Array<Complications.Type>);
    Test.assertMessage(s[0] >= 0 && s[0] < Lib.Numbers.PALETTES.size(), "then the editor: one of the sets");
    Test.assertMessage(Lib.Config.DATA.indexOf(s[2]) >= 0, "and one of the time's colours");
    if (Application has :WatchFaceConfig && WatchFaceConfig.getSettings(null) != null) {
        Test.assertEqualMessage(s[0], (WatchFaceConfig.getSettings(null) as WatchFaceConfig.Settings).styleId, "the editor's set");
    }
    Lib.Config.changedOnPhone();
    s = Lib.Config.read(Lib.Numbers.PALETTES.size(), [] as Array<Complications.Type>);
    Test.assertMessage(s[0] == 3 && s[2] == Lib.Config.DATA[2], "and the phone again");
    Application.Properties.setValue("Style", 0);
    Application.Properties.setValue("DataColor", 0);
    WallHelp.restore(look, source);
    return true;
}

// Lib.WatchMenu: the settings on the watch are the phone app's list, the
// look first, and a choice there writes the same property, winning over the
// editor; the muted weeks a switch
(:test)
function testWallWatchMenu(logger as Logger) as Boolean {
    var entries = Choices.entries();
    Test.assertEqualMessage(entries.size(), 4, "the look, the colours, the time's colour and the muted weeks");
    Test.assertMessage(entries[0][1] == null, "the look first");
    for (var i = 0; i < entries.size(); i++) {
        Test.assertEqualMessage(entries[i][2].size(), entries[i][3].size(), "a label for every choice");
    }
    Test.assertEqualMessage(entries[1][3].size(), Lib.Numbers.PALETTES.size(), "every set offered");
    Test.assertEqualMessage(entries[2][3].size(), Lib.Config.DATA.size(), "every colour for the time");
    var look = Application.Storage.getValue(Lib.Look.KEY);
    var source = Application.Storage.getValue(Lib.Config.SOURCE);
    Lib.WatchMenu.choose(entries[1], 4);
    Test.assertEqualMessage(Lib.WatchMenu.current(entries[1]), 4, "the choice is where the setting stands");
    Test.assertMessage(Lib.Config.PHONE.equals(Application.Storage.getValue(Lib.Config.SOURCE)), "a choice on the watch wins over the editor");
    Test.assertEqualMessage(Lib.Config.read(Lib.Numbers.PALETTES.size(), [] as Array<Complications.Type>)[0], 4, "and is the set drawn");
    var muted = entries[3];
    Lib.WatchMenu.choose(muted, 1);
    Test.assertEqualMessage(Application.Properties.getValue("MutedWeeks"), false, "the switch off");
    Test.assertEqualMessage(Lib.WatchMenu.label(muted), muted[2][1], "and shown off");
    Lib.WatchMenu.choose(muted, 0);
    Test.assertEqualMessage(Lib.WatchMenu.current(muted), 0, "and on again");
    Lib.WatchMenu.choose(entries[0], 4);              // the fifth look in the order: low light
    Test.assertEqualMessage(Lib.Look.mode(), Lib.Look.LOW, "the look chosen as a hold chooses it");
    Application.Properties.setValue("Style", 0);
    WallHelp.restore(look, source);
    return true;
}

// Put the look and the settings' source back as they were
(:test)
module WallHelp {

    function restore(look as Application.Storage.ValueType, source as Application.Storage.ValueType) as Void {
        if (look instanceof Number) {
            Application.Storage.setValue(Lib.Look.KEY, look);
        } else {
            Application.Storage.deleteValue(Lib.Look.KEY);
        }
        if (source instanceof String) {
            Application.Storage.setValue(Lib.Config.SOURCE, source);
        } else {
            Application.Storage.deleteValue(Lib.Config.SOURCE);
        }
    }
}
