import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

// Run No Evil tests for Clack: scripts/test.sh clack [device].

// Arrays compare by reference, so the leaves' digits are compared as one string
(:test)
module ClackTesting {
    function joined(a as Array<String>) as String {
        var s = "";
        for (var i = 0; i < a.size(); i++) {
            s += a[i];
        }
        return s;
    }

    function joinedNumbers(a as Array<Number>) as String {
        var s = "";
        for (var i = 0; i < a.size(); i++) {
            s += ((i > 0) ? " " : "") + a[i];
        }
        return s;
    }
}

// The roll's arithmetic: digits, steps on a wake, the push and the drop
(:test)
function testRollArithmetic(logger as Logger) as Boolean {
    Test.assertEqualMessage(ClackTesting.joined(Roll.digits(21 * 60 + 5, true)), "2105", "21:05");
    Test.assertEqualMessage(ClackTesting.joined(Roll.digits(0, true)), "0000", "midnight");
    Test.assertEqualMessage(ClackTesting.joined(Roll.digits(9 * 60 + 5, false)), "905", "9:05, a blank hour tens leaf");
    Test.assertEqualMessage(ClackTesting.joined(Roll.digits(12 * 60 + 59, false)), "1259", "12:59 PM");
    Test.assertEqualMessage(ClackTesting.joined(Roll.digits(13 * 60, false)), "100", "1:00 PM");
    Test.assertEqualMessage(Roll.flag(12 * 60 + 59, false), "PM", "noon on is PM");
    Test.assertEqualMessage(Roll.flag(5, false), "AM", "after midnight is AM");
    Test.assertEqualMessage(Roll.flag(5, true), "", "no flag in 24-hour mode");

    Test.assertEqualMessage(Roll.steps(100, 100).size(), 0, "nothing passed");
    Test.assertEqualMessage(ClackTesting.joinedNumbers(Roll.steps(100, 101)), "101", "one minute");
    Test.assertEqualMessage(ClackTesting.joinedNumbers(Roll.steps(478, 481)), "479 480 481", "three missed minutes, each rolled");
    Test.assertEqualMessage(Roll.steps(100, 104).size(), 4, "four is the most");
    Test.assertEqualMessage(ClackTesting.joinedNumbers(Roll.steps(100, 105)), "105", "five missed: straight to now");
    Test.assertEqualMessage(ClackTesting.joinedNumbers(Roll.steps(1439, 1)), "0 1", "across midnight");
    Test.assertEqualMessage(ClackTesting.joinedNumbers(Roll.steps(1439, 300)), "300", "a long sleep across midnight");

    Test.assertEqualMessage(Roll.pushFrames(1.0), 20, "a one-second push is twenty frames");
    Test.assertEqualMessage(Roll.pushFrames(0.01), 1, "one frame at least");
    var table = Drops.TABLES[0];
    var p = Roll.profile(0.5, table);
    Test.assertEqualMessage(p.size(), 10 + table.size() - 1, "the push's frames then the drop's");
    Test.assertMessage(p[0] > 0.0 && p[0] < table[0], "the push starts small");
    Test.assertMessage((p[9] - table[0]).abs() < 0.01, "and ends at the release angle");
    for (var i = 1; i < 10; i++) {
        Test.assertMessage(p[i] > p[i - 1], "the push only rises");
    }
    Test.assertMessage((p[p.size() - 1] - 180.0).abs() < 0.01, "every drop ends flat");
    for (var n = 0; n < Drops.COUNT; n++) {
        var t = Drops.TABLES[n];
        Test.assertMessage(t[0] >= 12.0 && t[0] <= 30.0, "release between 12 and 30 degrees");
        Test.assertMessage(t.size() >= 6 && t.size() <= 40, "a drop of six to forty frames");
        Test.assertMessage((t[t.size() - 1] - 180.0).abs() < 0.01, "at rest at 180");
    }
    for (var k = 0; k < 20; k++) {
        var v = Roll.between(0.6, 1.4);
        Test.assertMessage(v >= 0.6 && v <= 1.4, "a push in range");
        Test.assertMessage(Roll.table().size() > 0, "a table every time");
    }
    return true;
}

// Every style, awake by day and under the lamp, mid-flip, and in standby
(:test)
function testClackDrawsEveryMode(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var w = settings.screenWidth;
    var h = settings.screenHeight;
    var dc = (Graphics.createBufferedBitmap({:width => w, :height => h}).get() as Graphics.BufferedBitmap).getDc();

    var view = new ClackView();
    view.onLayout(dc);
    view.onUpdate(dc);                            // whatever the simulator's clock says

    for (var style = 0; style < Layout.STYLES; style++) {
        Application.Properties.setValue("Style", style);
        ClackSettings.changedOnPhone();
        view.reloadSettings();
        var started = System.getTimer();
        view.setState(21, 5, true, true);
        view.onUpdate(dc);
        logger.debug("style " + style + " night, first frame: " + (System.getTimer() - started) + " ms");
        view.setState(14, 38, false, true);
        started = System.getTimer();
        view.onUpdate(dc);
        logger.debug("style " + style + " day: " + (System.getTimer() - started) + " ms");
        view.setState(12, 59, true, false);       // 12-hour, the widest, the flag
        view.onUpdate(dc);
        view.setState(9, 5, false, false);        // a blank hour tens leaf
        view.onUpdate(dc);
        // the units leaf through its fall, the tens leaf and an hour leaf with it
        view.setState(21, 8, true, true);
        var angles = [5, 30, 60, 89, 90, 91, 120, 160, 179] as Array<Number>;
        for (var a = 0; a < angles.size(); a++) {
            view.setFlip(3, "9", angles[a]);
            view.setFlip(2, "1", 180 - angles[a]);
            view.setFlip(1, "2", angles[a]);
            started = System.getTimer();
            view.onUpdate(dc);
            if (a == 2) {
                logger.debug("style " + style + " mid-flip frame: " + (System.getTimer() - started) + " ms");
            }
        }
        // standby, day and night
        view.setState(8, 8, false, true);
        view.setAwake(false);
        started = System.getTimer();
        view.onUpdate(dc);
        logger.debug("style " + style + " standby: " + (System.getTimer() - started) + " ms");
        view.setState(8, 8, true, true);
        view.onUpdate(dc);
        view.setState(12, 59, false, false);
        view.onUpdate(dc);
        view.setAwake(true);
        view.release();
    }
    Application.Properties.setValue("Style", 1);
    Application.Storage.deleteValue(ClackSettings.SOURCE);

    var stats = System.getSystemStats();
    logger.debug("memory: " + stats.usedMemory + " of " + stats.totalMemory + " bytes used");
    return true;
}

// A wake: the leaves roll through the missed minutes and show now
(:test)
function testClackRollsOnWake(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var w = settings.screenWidth;
    var h = settings.screenHeight;
    var dc = (Graphics.createBufferedBitmap({:width => w, :height => h}).get() as Graphics.BufferedBitmap).getDc();
    var view = new ClackView();
    view.onLayout(dc);
    view.setState(7, 58, true, true);
    view.onUpdate(dc);
    var frames = view.rollTo(8 * 60 + 1);
    logger.debug("07:58 to 08:01 in " + frames + " frames");
    Test.assertMessage(frames > 20 && frames < 400, "three minutes rolled in a few seconds of frames");
    Test.assertEqualMessage(ClackTesting.joined(view.shows()), "0801", "the leaves show 08:01");
    view.onUpdate(dc);
    frames = view.rollTo(23 * 60 + 59);
    Test.assertEqualMessage(ClackTesting.joined(view.shows()), "2359", "a long sleep: straight to 23:59");
    frames = view.rollTo(0);
    Test.assertEqualMessage(ClackTesting.joined(view.shows()), "0000", "midnight: all four leaves");
    Test.assertMessage(frames > 10, "and they fell, a beat apart");
    view.setState(12, 59, false, false);
    view.rollTo(13 * 60);
    Test.assertEqualMessage(ClackTesting.joined(view.shows()), "100", "1:00 PM: the hour tens leaf to a blank");
    view.onUpdate(dc);
    view.release();
    return true;
}
