import Toybox.Application;
import Toybox.Application.WatchFaceConfig;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;
import Toybox.Time;

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

// A start: the time alone first, then everything, drawn into the bitmap once
// the frame after. A wake within the minute draws nothing again.
(:test)
function testBlocksLights(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var dc = (Graphics.createBufferedBitmap({:width => settings.screenWidth, :height => settings.screenHeight}).get()
              as Graphics.BufferedBitmap).getDc();
    var view = new BlocksView();
    view.onLayout(dc);
    var minute = Time.now().value() / 60;
    view.onUpdate(dc);
    Test.assertMessage(!view.settled() && view.composed == 0, "the first frame: the time alone");
    view.onUpdate(dc);
    Test.assertMessage(view.settled() && view.composed == 0, "the second: everything, straight to the screen");
    view.onUpdate(dc);
    var composed = view.composed;
    view.onUpdate(dc);
    view.onEnterSleep();
    view.onUpdate(dc);
    view.onExitSleep();
    view.onUpdate(dc);
    Test.assertMessage(view.settled(), "settled again in the wake's first frame");
    if (Time.now().value() / 60 == minute) {    // (the minute didn't turn while the test ran)
        Test.assertEqualMessage(composed, 1, "drawn once on a start");
        Test.assertEqualMessage(view.composed, composed, "nothing drawn again, awake or on a wake within the minute");
    }
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
    view.onUpdate(dc);           // the readings come the frame after the time
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
    Test.assertEqualMessage(Lib.Numbers.MUTED.size(), Lib.Numbers.PERSONAS.size(), "a muted persona for each day");
    Test.assertEqualMessage(Lib.Numbers.MUTED_NAMES.size(), Lib.Numbers.MUTED.size(), "a name per muted persona");
    Test.assertEqualMessage(Lib.Numbers.MUTED_NAMES[Lib.Look.dayOf(20773, 7)], "LOW LIGHT", "a muted week opens on Low light");
    Test.assertMessage(Lib.Numbers.mutedOn(20766, true), "Monday 9 November 2026: muted");
    Test.assertMessage(Lib.Numbers.mutedOn(20772, true), "Sunday 15 November: still muted");
    Test.assertMessage(!Lib.Numbers.mutedOn(20773, true), "Monday 16 November: bright again");
    Test.assertMessage(Lib.Numbers.mutedOn(20780, true), "Monday 23 November: muted");
    Test.assertMessage(!Lib.Numbers.mutedOn(20766, false), "the setting off: never muted");
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
        var drawn = Lib.Ink.resolve(face);   // the face Lib.Numbers draws with: this one, or on a watch with no Bionic the nearest it has
        Test.assertMessage(Lib.Ink.font(drawn, 60.0, Graphics.FONT_XTINY) instanceof Graphics.VectorFont, Lib.Ink.NAMES[drawn] + " is a vector font");
        Test.assertMessage(Lib.Numbers.ADVANCE[drawn][0] > 0, "its digit advance is known");
    }
    Test.assertEqualMessage(Lib.Ink.usable(Lib.Ink.BIONIC_BOLD), Lib.Ink.BIONIC_BOLD, "Bionic Bold has no stand-in");
    return true;
}

// Your look in every set of the families' colours and every colour for the
// time, awake and in standby; the defaults are the face's own colours
(:test)
function testBlocksColors(logger as Logger) as Boolean {
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
    var view = new BlocksView();
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
            view.onUpdate(dc);
            view.onUpdate(dc);
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
    BlocksHelp.restore(look, source);
    return true;
}

// A change in the phone app (or the watch's settings menu) and one in the
// watch face editor each take, the later winning
(:test)
function testBlocksPhoneAndEditor(logger as Logger) as Boolean {
    Test.assertMessage(Lib.Config.value("Accent") == null, "a setting the face doesn't have reads as none");
    Test.assertMessage(Lib.Config.read(1, [] as Array<Complications.Type>)[4], "and its default is taken (the bedside clock)");
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
    BlocksHelp.restore(look, source);
    return true;
}

// Lib.WatchMenu: the settings on the watch are the phone app's list, the
// look first, and a choice there writes the same property, winning over the
// editor; the muted weeks a switch
(:test)
function testBlocksWatchMenu(logger as Logger) as Boolean {
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
    BlocksHelp.restore(look, source);
    return true;
}

// Put the look and the settings' source back as they were
(:test)
module BlocksHelp {

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
