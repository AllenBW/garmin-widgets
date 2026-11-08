import Toybox.Application;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

// Run No Evil tests for Blocks: scripts/test.sh blocks [device]. Lib.Numbers
// is tested here; Wall uses it too.

(:test)
function testBlocksDrawsEveryMode(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var dc = (Graphics.createBufferedBitmap({:width => settings.screenWidth, :height => settings.screenHeight}).get()
              as Graphics.BufferedBitmap).getDc();

    var view = new BlocksView();
    view.onLayout(dc);

    // Whatever the simulator provides
    var started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("awake: " + (System.getTimer() - started) + " ms");

    // Nothing yet, the samples, and the widest of everything
    view.setValues(["1/1", "00", "00", "--:--", "--:--", "--", "--", "--", "--", "--", "--", "--", "--"] as Array<String>);
    view.onUpdate(dc);
    view.setValues(["1/1", "07", "05", "07:12", "0:05", "5°", "9", "-2", "58", "0", "7", "-59", "6"] as Array<String>);
    view.onUpdate(dc);
    view.setValues(["10/31", "21", "05", "07:12", "10:07", "28°", "41", "24", "58", "11382", "47", "1240", "6"] as Array<String>);
    view.onUpdate(dc);
    view.setValues(["11/11", "11", "11", "17:01", "11:11", "-12°", "-4", "-19", "148", "21114", "100", "11240", "31"] as Array<String>);
    view.onUpdate(dc);

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

// A hold on a reading opens it; on the time it steps the look
(:test)
function testBlocksTargets(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var w = settings.screenWidth;
    var dc = (Graphics.createBufferedBitmap({:width => w, :height => settings.screenHeight}).get() as Graphics.BufferedBitmap).getDc();
    var view = new BlocksView();
    view.onLayout(dc);
    view.setValues(["10/31", "14", "38", "19:22", "4:44", "46°", "52", "38", "72", "6214", "82", "1240", "12"] as Array<String>);
    view.onUpdate(dc);
    Test.assertMessage(view.targetAt((w * 0.35).toNumber(), (w * 0.35).toNumber()) == null, "the hours are no target");
    Test.assertMessage(view.targetAt((w * 0.70).toNumber(), (w * 0.65).toNumber()) == null, "the minutes are no target");
    Test.assertMessage(view.targetAt((w * 0.75).toNumber(), (w * 0.33).toNumber()) == Complications.COMPLICATION_TYPE_SUNRISE, "the sun");
    Test.assertMessage(view.targetAt((w * 0.12).toNumber(), (w * 0.555).toNumber()) == Complications.COMPLICATION_TYPE_HEART_RATE, "heart rate");
    Test.assertMessage(view.targetAt((w * 0.40).toNumber(), (w * 0.14).toNumber()) == Complications.COMPLICATION_TYPE_CALENDAR_EVENTS, "the date");
    view.setAwake(false);
    view.onUpdate(dc);
    return true;
}

// Every look draws, awake and in standby, the look's name for a moment
(:test)
function testBlocksLooks(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var dc = (Graphics.createBufferedBitmap({:width => settings.screenWidth, :height => settings.screenHeight}).get()
              as Graphics.BufferedBitmap).getDc();
    var view = new BlocksView();
    view.onLayout(dc);
    Application.Storage.setValue(Lib.Look.KEY, Lib.Look.LOW);
    for (var m = 0; m < Lib.Look.MODES; m++) {
        Test.assertEqualMessage(Lib.Look.next(), Lib.Look.ORDER[(Lib.Look.ORDER.indexOf(Lib.Look.LOW) + m + 1) % Lib.Look.MODES], "the next look");
        view.reloadSettings();
        view.onUpdate(dc);
        view.setAwake(false);
        view.onUpdate(dc);
        view.setAwake(true);
    }
    Application.Storage.deleteValue(Lib.Look.KEY);
    return true;
}

(:test)
function testNumbersText(logger as Logger) as Boolean {
    Test.assertEqual(Lib.Numbers.dateText(10, 31), "10/31");
    Test.assertEqual(Lib.Numbers.dateText(3, 5), "3/5");
    Test.assertEqual(Lib.Numbers.countdown(14 * 3600 + 38 * 60, 19 * 3600 + 22 * 60), "4:44");
    Test.assertEqualMessage(Lib.Numbers.countdown(21 * 3600 + 5 * 60, 7 * 3600 + 12 * 60), "10:07", "past midnight");
    Test.assertEqualMessage(Lib.Numbers.countdown(7 * 3600, 7 * 3600), "0:00", "now");
    var values = ["10/31", "14", "38", "19:22", "4:44", "46°", "52", "38", "72", "6214", "82", "1240", "12"] as Array<String>;
    var stream = Lib.Numbers.stream(values);
    Test.assertEqualMessage(stream.slice(0, 8).toString(), [1, 4, 3, 8, 1, 9, 2, 2].toString(), "the time, then the sun");
    Test.assertEqualMessage(stream.size(), 29, "only digits");
    return true;
}

(:test)
function testNumbersFit(logger as Logger) as Boolean {
    // Zeros, whatever the digits; a degree sign and a minus take their room
    var bold = Lib.Ink.BIONIC_BOLD;
    Test.assertEqualMessage(Lib.Numbers.ratio("14", bold), Lib.Numbers.ratio("38", bold), "tabular");
    Test.assertMessage(Lib.Numbers.ratio("46°", bold) > Lib.Numbers.ratio("46", bold), "the degree sign");
    Test.assertMessage(Lib.Numbers.ratio("-4", bold) > Lib.Numbers.ratio("4", bold), "the minus");
    Test.assertEqualMessage(Lib.Numbers.ratio("--", bold), Lib.Numbers.ratio("00", bold), "dashes stand for digits");

    // A chord row from the middle, and from further out: the row touches the bezel
    var margin = 0.02;
    var h = Lib.Numbers.fit(3.0, 0.0, 0.0, null, margin);
    Test.assertMessage((3.0 * h - 2.0 * Lib.Numbers.half(0.5 - h, margin)).abs() < 0.001, "across the chord");
    h = Lib.Numbers.fit(3.0, 0.02, -0.2, null, margin);
    Test.assertMessage((3.0 * h + 0.02 - 2.0 * Lib.Numbers.half(0.3 - h, margin)).abs() < 0.001, "with a gap, further out");
    // From a fixed edge to the bezel
    h = Lib.Numbers.fit(2.0, 0.0, -0.05, 0.1, margin);
    Test.assertMessage((0.5 + Lib.Numbers.half(0.45 - h, margin) - 0.6 - 2.0 * h).abs() < 0.001, "to the bezel");
    Test.assertEqualMessage(Lib.Numbers.fit(1.0, 0.0, -0.49, null, margin), 0.0, "past the bezel, no row");
    return true;
}

// A low reading takes the room of a usual one; a long one takes its own
(:test)
function testNumbersRoom(logger as Logger) as Boolean {
    var values = ["3/5", "07", "05", "07:12", "0:05", "5°", "9", "-2", "58", "0", "7", "-59", "6"] as Array<String>;
    var bold = Lib.Ink.BIONIC_BOLD;
    Test.assertEqual(Lib.Numbers.reading(values, Lib.Numbers.STEPS, bold, 0, null).room, "0000");
    Test.assertEqual(Lib.Numbers.reading(values, Lib.Numbers.ALTITUDE, bold, 0, null).room, "0000");
    Test.assertEqual(Lib.Numbers.reading(values, Lib.Numbers.DATE, bold, 0, null).room, "00/00");
    Test.assertEqual(Lib.Numbers.reading(values, Lib.Numbers.TEMP, bold, 0, null).room, "00°");
    values[Lib.Numbers.STEPS] = "21114";
    Test.assertEqual(Lib.Numbers.reading(values, Lib.Numbers.STEPS, bold, 0, null).room, "21114");
    Test.assertEqualMessage(Lib.Numbers.LEAST.size(), Lib.Numbers.VALUES, "a least room per reading");
    return true;
}

(:test)
function testNumbersColors(logger as Logger) as Boolean {
    Test.assertEqual(Lib.Numbers.colors(Lib.Look.YOURS).sun, 0xFFB020);
    Test.assertEqual(Lib.Numbers.colors(Lib.Look.BRIGHT_BLUE).sun, Lib.Look.ARC);
    Test.assertMessage(Lib.Numbers.colors(Lib.Look.BRIGHT).fluorescent, "high visibility");
    Test.assertMessage(!Lib.Numbers.colors(Lib.Look.LOW).fluorescent, "low light");
    Test.assertEqualMessage(Lib.Numbers.PERSONAS.size(), Lib.Numbers.NAMES.size(), "a name per persona");
    Test.assertEqualMessage(Lib.Numbers.scale(0xFF8040, 0.5), 0x7F4020, "half");
    return true;
}

// Every face these faces draw with is a vector font on this watch: a missing
// one (Bionic Medium on the Venu 4) gives way to its sibling, never to the
// watch's own number font
(:test)
function testInkUsable(logger as Logger) as Boolean {
    var faces = [Lib.Ink.BIONIC_BOLD, Lib.Ink.BIONIC_MEDIUM, Lib.Ink.CONDENSED_BOLD, Lib.Ink.CONDENSED_REGULAR] as Array<Number>;
    for (var i = 0; i < faces.size(); i++) {
        var face = Lib.Ink.usable(faces[i]);
        logger.debug(Lib.Ink.NAMES[faces[i]] + " -> " + Lib.Ink.NAMES[face]);
        Test.assertMessage(face == faces[i] || face == Lib.Ink.SUBSTITUTE[faces[i]], "itself or its sibling");
        Test.assertMessage(Lib.Ink.font(face, 60.0, Graphics.FONT_XTINY) instanceof Graphics.VectorFont, Lib.Ink.NAMES[face] + " is a vector font");
    }
    Test.assertEqualMessage(Lib.Ink.usable(Lib.Ink.BIONIC_BOLD), Lib.Ink.BIONIC_BOLD, "Bionic Bold has no stand-in");
    return true;
}
