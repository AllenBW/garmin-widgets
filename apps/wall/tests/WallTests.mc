import Toybox.Application;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

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
                for (var bits = lit[r]; bits != 0; bits = bits >> 1) {
                    cells += bits & 1;
                }
            }
            Test.assertMessage(cells > 10, "digit " + d + " lights cells");
        }
    }
    return true;
}
