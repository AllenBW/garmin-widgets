import Toybox.Application;
import Toybox.Application.WatchFaceConfig;
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
    view.setStill();
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
    view.setStill();
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

// A start lights at once: its first frame draws the
// leaves flat, each frame after makes one half, then the lamp's pool goes
// in over a few frames
(:test)
function testClackLightsFirst(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var dc = (Graphics.createBufferedBitmap({:width => settings.screenWidth, :height => settings.screenHeight}).get()
              as Graphics.BufferedBitmap).getDc();
    var view = new ClackView();
    view.setStill();
    view.setGradual();
    view.onLayout(dc);
    view.setState(21, 5, true, true);
    var started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("first frame, flat: " + (System.getTimer() - started) + " ms");
    Test.assertEqualMessage(view.halvesMade(), 0, "the first frame makes no half");
    Test.assertMessage(!view.lit(), "and the face is not yet lit through");
    for (var n = 1; n <= 8; n++) {
        view.onUpdate(dc);
        Test.assertEqualMessage(view.halvesMade(), n, "one half a frame");
    }
    var frames = 0;
    while (!view.lit() && frames < 10) {
        view.onUpdate(dc);
        frames++;
    }
    logger.debug("the lamp's pool in " + frames + " frames");
    Test.assertMessage(view.lit() && frames >= 2 && frames <= 5, "the lamp's pool over a few frames");
    // by day the face is lit once the halves are made; a flip makes the rest at once
    view.setState(14, 38, false, true);
    view.onUpdate(dc);
    Test.assertEqualMessage(view.halvesMade(), 1, "remade a half a frame");
    view.setFlip(3, "9", 30);
    Test.assertEqualMessage(view.halvesMade(), 8, "a flip makes every half first");
    view.onUpdate(dc);
    Test.assertMessage(view.lit(), "lit by day with the halves made");
    view.release();
    return true;
}

// The helpers of the looks' and colours' tests
(:test)
module ClackHelp {

    // A look or a colour drawn every way: by day, under the lamp, mid-flip,
    // the 12-hour flag, and in standby by day and night
    function states(view as ClackView, dc as Dc) as Void {
        view.setState(21, 5, true, true);
        view.onUpdate(dc);
        view.setState(14, 38, false, true);
        view.onUpdate(dc);
        view.setFlip(3, "9", 60);
        view.setFlip(1, "5", 120);
        view.onUpdate(dc);
        view.setState(12, 59, true, false);
        view.onUpdate(dc);
        view.setState(8, 8, false, true);
        view.setAwake(false);
        view.onUpdate(dc);
        view.setState(8, 8, true, true);
        view.onUpdate(dc);
        view.setAwake(true);
        view.release();
    }

    function restore(look as Application.Storage.ValueType, source as Application.Storage.ValueType) as Void {
        Application.Properties.setValue("Style", 1);
        Application.Properties.setValue("Accent", 0);
        Application.Properties.setValue("DataColor", 0);
        Application.Properties.setValue(Lib.Look.KEY, Lib.Look.YOURS);   // a hold moves the phone's setting too
        Application.Storage.deleteValue(Lib.Look.SEEN);
        Lib.Look.changedAt = null;
        if (look instanceof Number) {
            Application.Storage.setValue(Lib.Look.KEY, look);
        } else {
            Application.Storage.deleteValue(Lib.Look.KEY);
        }
        if (source instanceof String) {
            Application.Storage.setValue(ClackSettings.SOURCE, source);
        } else {
            Application.Storage.deleteValue(ClackSettings.SOURCE);
        }
    }

    function joined(s as [Number, Number, Number]) as String {
        return s[0] + " " + s[1] + " " + s[2];
    }
}

// Every look in the original and a zoomed view, and every plastic and ink;
// the defaults are the face as it was (DAY and NIGHT)
(:test)
function testClackLooksAndColors(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var dc = (Graphics.createBufferedBitmap({:width => settings.screenWidth, :height => settings.screenHeight}).get()
              as Graphics.BufferedBitmap).getDc();
    var look = Application.Storage.getValue(Lib.Look.KEY);
    var source = Application.Storage.getValue(ClackSettings.SOURCE);
    Application.Storage.setValue(Lib.Look.KEY, Lib.Look.YOURS);
    Application.Properties.setValue("Accent", 0);
    Application.Properties.setValue("DataColor", 0);
    ClackSettings.changedOnPhone();
    var view = new ClackView();
    view.setStill();
    view.onLayout(dc);
    view.setState(14, 38, false, true);
    var c = view.colors();
    Test.assertEqualMessage(ClackTesting.joinedNumbers(c),
                            ClackTesting.joinedNumbers([0x2C2C2C, 0x1A1A1A, 0x0E0E0E, 0x202020, 0x4E4E4E, 0x3C3C3C, 0x787878, 0x282828,
                                                        0xE8E8E8, 0xE8E8E8, 0xAAAAAA, 0xE8E8E8, 0x808080] as Array<Number>),
                            "by day, black leaves and white digits as they were");
    view.setState(21, 5, true, true);
    c = view.colors();
    Test.assertEqualMessage(ClackTesting.joinedNumbers(c),
                            ClackTesting.joinedNumbers([0x1A0F07, 0x0E0804, 0x060302, 0x120A05, 0x78461C, 0x3C240E, 0xAA6E32, 0x2C1A0A,
                                                        0x966030, 0xFFDAA0, 0xD69654, 0x966030, 0x966836] as Array<Number>),
                            "and under the lamp");

    var styles = [0, 1] as Array<Number>;
    for (var v = 0; v < styles.size(); v++) {
        Application.Properties.setValue("Style", styles[v]);
        for (var m = 0; m < Lib.Look.MODES; m++) {
            Application.Storage.setValue(Lib.Look.KEY, m);
            ClackSettings.changedOnPhone();
            view.reloadSettings();
            ClackHelp.states(view, dc);
        }
    }
    // high visibility: the hours fluorescent, the minutes white, no lamp after sunset
    Application.Storage.setValue(Lib.Look.KEY, Lib.Look.BRIGHT_GREEN);
    view.reloadSettings();
    view.setState(21, 5, true, true);
    c = view.colors();
    Test.assertMessage(c[11] == Lib.Look.VOLT && c[8] == 0xFFFFFF && c[0] == 0x2C2C2C, "high visibility: green hours, white minutes, no lamp");
    // low light: the lamp on by day
    Application.Storage.setValue(Lib.Look.KEY, Lib.Look.LOW);
    view.reloadSettings();
    view.setState(14, 38, false, true);
    Test.assertEqualMessage(view.colors()[0], 0x1A0F07, "low light: the lamp on all day");
    // every plastic and ink
    Application.Storage.setValue(Lib.Look.KEY, Lib.Look.YOURS);
    for (var k = 0; k < Choices.LEAVES.size(); k++) {
        Application.Properties.setValue("Accent", k);
        Application.Properties.setValue("DataColor", k % Choices.DIGITS.size());
        ClackSettings.changedOnPhone();
        view.reloadSettings();
        view.setState(14, 38, false, true);
        c = view.colors();
        Test.assertEqualMessage(c[0], (Choices.LEAVES[k] >> 1) & 0x7F7F7F, "the plastic, at its own shade");
        Test.assertEqualMessage(c[8], Choices.DIGITS[k % Choices.DIGITS.size()], "the ink");
        ClackHelp.states(view, dc);
    }
    Test.assertEqualMessage(Choices.PERSONAS.size(), Choices.NAMES.size(), "a name for every persona");
    ClackHelp.restore(look, source);
    return true;
}

// A change in the phone app (or the watch's settings menu) and one in the
// watch face editor each take, the later winning; the editor's colours are
// snapped to the lists
(:test)
function testClackPhoneAndEditor(logger as Logger) as Boolean {
    var look = Application.Storage.getValue(Lib.Look.KEY);
    var source = Application.Storage.getValue(ClackSettings.SOURCE);
    Test.assertEqualMessage(ClackSettings.nearest(0x384C80, Choices.LEAVES), 1, "the editor's navy is navy");
    Test.assertEqualMessage(ClackSettings.nearest(0xFFB431, Choices.DIGITS), 2, "and near amber is amber");
    Application.Properties.setValue("Style", 3);
    Application.Properties.setValue("Accent", 2);
    Application.Properties.setValue("DataColor", 3);
    ClackSettings.changedOnPhone();
    var s = ClackSettings.read();
    Test.assertEqualMessage(ClackHelp.joined(s), "3 2 3", "the phone changed last: Bebas, oxblood, lemon");
    ClackSettings.changedInEditor();
    s = ClackSettings.read();
    Test.assertMessage(s[0] >= 0 && s[0] < Layout.STYLES && s[1] >= 0 && s[1] < Choices.LEAVES.size()
                       && s[2] >= 0 && s[2] < Choices.DIGITS.size(), "then the editor: a view, a plastic and an ink");
    if (Application has :WatchFaceConfig && WatchFaceConfig.getSettings(null) != null) {
        Test.assertEqualMessage(s[0], (WatchFaceConfig.getSettings(null) as WatchFaceConfig.Settings).styleId, "the editor's view");
    }
    ClackSettings.changedOnPhone();
    Test.assertEqualMessage(ClackHelp.joined(ClackSettings.read()), "3 2 3", "and the phone again");
    ClackHelp.restore(look, source);
    return true;
}

// The hold steps to the next look, its name standing in for the date for a
// moment, in both views; Lib.WatchMenu offers the phone app's list
(:test)
function testClackHoldAndMenu(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var dc = (Graphics.createBufferedBitmap({:width => settings.screenWidth, :height => settings.screenHeight}).get()
              as Graphics.BufferedBitmap).getDc();
    var look = Application.Storage.getValue(Lib.Look.KEY);
    var source = Application.Storage.getValue(ClackSettings.SOURCE);
    Application.Storage.setValue(Lib.Look.KEY, Lib.Look.YOURS);
    var view = new ClackView();
    view.setStill();
    view.onLayout(dc);
    for (var style = 0; style <= 1; style++) {
        Application.Properties.setValue("Style", style);
        ClackSettings.changedOnPhone();
        view.reloadSettings();
        view.setState(14, 38, false, true);
        view.onUpdate(dc);
        var before = Lib.Look.mode();
        var next = Lib.Look.next();
        view.reloadSettings();
        Test.assertEqualMessage(next, Lib.Look.ORDER[(Lib.Look.ORDER.indexOf(before) + 1) % Lib.Look.MODES], "the hold: the next look");
        Test.assertMessage(Lib.Look.shown(), "its name showing");
        view.onUpdate(dc);
        Lib.Look.changedAt = null;                 // the moment over: the date back
        view.onUpdate(dc);
    }

    var entries = Choices.entries();
    Test.assertEqualMessage(entries.size(), 5, "the look, the view, the leaves, the digits and the date");
    Test.assertMessage(entries[0][1] == null, "the look first");
    for (var i = 0; i < entries.size(); i++) {
        Test.assertEqualMessage(entries[i][2].size(), entries[i][3].size(), "a label for every choice");
    }
    Test.assertEqualMessage(entries[1][3].size(), Layout.STYLES, "every view");
    Test.assertEqualMessage(entries[2][3].size(), Choices.LEAVES.size(), "every plastic");
    Test.assertEqualMessage(entries[3][3].size(), Choices.DIGITS.size(), "every ink");
    Lib.WatchMenu.choose(entries[2], 3);
    Test.assertMessage(ClackSettings.PHONE.equals(Application.Storage.getValue(ClackSettings.SOURCE)), "a choice on the watch wins over the editor");
    Test.assertEqualMessage(ClackSettings.read()[1], 3, "and is the plastic drawn");
    Lib.WatchMenu.choose(entries[4], 1);
    Test.assertEqualMessage(Application.Properties.getValue("Date"), false, "the date switched off");
    Lib.WatchMenu.choose(entries[4], 0);
    Lib.WatchMenu.choose(entries[0], 4);              // the fifth look in the order: low light
    Test.assertEqualMessage(Lib.Look.mode(), Lib.Look.LOW, "the look chosen as a hold chooses it");
    ClackHelp.restore(look, source);
    return true;
}
