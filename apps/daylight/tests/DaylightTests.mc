import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

// Run No Evil tests for Daylight: scripts/test.sh daylight [device].

(:test)
function testLightText(logger as Logger) as Boolean {
    var day = 1734739200;
    var rise = 8 * 3600 + 4 * 60;
    var set = 15 * 3600 + 53 * 60;
    var tomorrowRise = day + 86400 + rise;
    Test.assertEqualMessage(DaylightText.light(6 * 3600, rise, set, tomorrowRise, day, true, false), "sunrise in 2h 04m", "before sunrise");
    Test.assertEqualMessage(DaylightText.light(10 * 3600 + 8 * 60, rise, set, tomorrowRise, day, true, false), "5h 45m of light left", "daytime");
    Test.assertEqualMessage(DaylightText.light(20 * 3600, rise, set, tomorrowRise, day, true, false), "sunrise in 12h 04m", "after sunset");
    Test.assertEqualMessage(DaylightText.light(12 * 3600, null, null, null, day, true, false), "no sunrise today", "polar night");
    Test.assertEqualMessage(DaylightText.light(12 * 3600, null, null, null, day, true, true), "no sunset today", "midnight sun");
    Test.assertEqualMessage(DaylightText.light(12 * 3600, null, null, null, day, false, false), "no location yet", "never located");
    return true;
}

(:test)
function testDialPlacement(logger as Logger) as Boolean {
    // Noon at the top, sunrise on the left half, sunset on the right half
    Test.assertEqualMessage(Lib.Sun.dialDegrees(12 * 3600), 0.0, "noon at the top");
    var rise = Lib.Sun.dialDegrees(6 * 3600 + 52 * 60);
    var set = Lib.Sun.dialDegrees(17 * 3600 + 41 * 60);
    Test.assertMessage(rise > 180.0 && rise < 360.0, "sunrise on the left: " + rise);
    Test.assertMessage(set > 0.0 && set < 180.0, "sunset on the right: " + set);
    return true;
}

(:test)
function testFaceDrawsBothModes(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var w = settings.screenWidth;
    var h = settings.screenHeight;
    var dc = (Graphics.createBufferedBitmap({:width => w, :height => h}).get() as Graphics.BufferedBitmap).getDc();
    var view = new DaylightView();
    view.onLayout(dc);
    view.onUpdate(dc);
    view.onEnterSleep();
    view.onUpdate(dc);
    view.onExitSleep();
    view.onUpdate(dc);
    // a wake reads the altitude and pressure afresh, but the three hours'
    // history only every ten minutes
    Test.assertEqualMessage(view.trendReads, 1, "the pressure history read once, not again on the wake");
    logger.debug("location: " + Lib.Location.get());
    var stats = System.getSystemStats();
    logger.debug("memory: " + stats.usedMemory + " of " + stats.totalMemory + " bytes used");
    return true;
}

// ------------------------------------------------------------ the settings

module DaylightTesting {

    function screen() as Graphics.Dc {
        var s = System.getDeviceSettings();
        return (Graphics.createBufferedBitmap({:width => s.screenWidth, :height => s.screenHeight}).get() as Graphics.BufferedBitmap).getDc();
    }

    // Lit, then in standby, then lit again
    function both(view as DaylightView, dc as Graphics.Dc) as Void {
        view.onUpdate(dc);
        view.setAwake(false);
        view.onUpdate(dc);
        view.setAwake(true);
    }

    function joined(a as Array<Number>) as String {
        var s = "";
        for (var i = 0; i < a.size(); i++) {
            s += ((i > 0) ? " " : "") + a[i];
        }
        return s;
    }
}

// The defaults (the first sky, the first time colour, your own look) are
// the face exactly as it was before it had settings
(:test)
function testDaylightDefaults(logger as Logger) as Boolean {
    var c = Skies.palette(Lib.Look.YOURS, [0, 0] as [Number, Number], 0);
    Test.assertEqualMessage(c[Skies.NIGHT], 0x1A2A4A, "night as it was");
    Test.assertEqualMessage(c[Skies.DAY], 0xFFB020, "day as it was");
    Test.assertEqualMessage(c[Skies.GOLDEN], 0xFF7A3D, "golden as it was");
    Test.assertEqualMessage(c[Skies.TICK], 0x8A8A8A, "tick as it was");
    Test.assertEqualMessage(c[Skies.LABEL], 0x5A5A5A, "label as it was");
    Test.assertEqualMessage(c[Skies.TEXT], 0x8A8A8A, "text as it was");
    Test.assertEqualMessage(c[Skies.QUIET], 0x5A5A5A, "quiet as it was");
    Test.assertEqualMessage(c[Skies.FAINT], 0x5A5A5A, "faint as it was");
    Test.assertEqualMessage(c[Skies.TIME], 0xF2F2F2, "time as it was");
    Test.assertEqualMessage(Skies.standby(0xF2F2F2), 0x8A8A8A, "the time in standby as it was");
    Test.assertEqualMessage(Skies.SETS[0].size(), Skies.TIME + 1, "a colour for every place");
    return true;
}

// Every look draws, lit with its name for a moment and in standby; then
// every sky with every time colour, and the daily look's every sky
(:test)
function testDaylightLooksAndSkies(logger as Logger) as Boolean {
    var dc = DaylightTesting.screen();
    var view = new DaylightView();
    view.onLayout(dc);
    var was = Application.Storage.getValue(Lib.Look.KEY);
    var phone = Application.Properties.getValue(Lib.Look.KEY);
    var seen = Application.Storage.getValue(Lib.Look.SEEN);
    Application.Storage.setValue(Lib.Look.KEY, Lib.Look.DAILY);
    var titles = [] as Array<String>;
    for (var m = 0; m < Lib.Look.MODES; m++) {
        var look = Lib.Look.next();
        Test.assertEqualMessage(look, Lib.Look.ORDER[m], "the looks in order from your own");
        view.reloadSettings();
        Test.assertMessage(Lib.Look.shown(), "its name shows for a moment");
        titles.add(Skies.title(look));
        DaylightTesting.both(view, dc);
    }
    Test.assertEqualMessage(titles[0], "YOUR LOOK", "your own look's name");
    Test.assertEqualMessage(titles[1], "HI-VIS ORANGE", "high visibility's");
    Lib.Look.changedAt = null;
    for (var s = 0; s < Skies.SETS.size(); s++) {
        for (var t = 0; t < Skies.TIMES.size(); t++) {
            var c = Skies.palette(Lib.Look.YOURS, [s, t] as [Number, Number], 0);
            Test.assertEqualMessage(c[Skies.TIME], Skies.TIMES[t], "the time colour chosen");
            view.setColors(c);
            DaylightTesting.both(view, dc);
        }
        var daily = Skies.palette(Lib.Look.DAILY, [0, 0] as [Number, Number], s);
        Test.assertEqualMessage(DaylightTesting.joined(daily), DaylightTesting.joined(Skies.SETS[s]), "the daily look: a sky a day");
        Test.assertMessage(Skies.standby(daily[Skies.TIME]) != 0, "the time is lit in standby");
    }
    var palettes = [Skies.BRIGHT, Skies.BRIGHT_BLUE, Skies.BRIGHT_GREEN, Skies.LOW] as Array<Array<Number>>;
    for (var i = 0; i < palettes.size(); i++) {
        Test.assertEqualMessage(palettes[i].size(), Skies.SETS[0].size(), "a look colours every place");
        for (var k = 0; k < palettes[i].size(); k++) {
            Test.assertMessage(palettes[i][k] != 0, "nothing drawn in black");
        }
    }
    restoreLook(was, phone, seen);
    return true;
}

// The sky and the time colour chosen in the phone app or the watch face
// editor, whichever was changed last; the editor offers only the face's
// colours, and anything else snaps to the nearest
(:test)
function testDaylightChosen(logger as Logger) as Boolean {
    for (var i = 0; i < Skies.TIMES.size(); i++) {
        Test.assertEqualMessage(Skies.nearest(Skies.TIMES[i]), i, "a time colour is itself");
    }
    Test.assertEqualMessage(Skies.nearest(0xFFFFFF), 0, "white snaps to the face's white");
    var theme = Application.Properties.getValue("Theme");
    var time = Application.Properties.getValue("TimeColor");
    var source = Application.Storage.getValue(Skies.SOURCE);
    Application.Properties.setValue("Theme", 2);
    Application.Properties.setValue("TimeColor", 3);
    Skies.changedOnPhone();
    Test.assertMessage(Skies.PHONE.equals(Application.Storage.getValue(Skies.SOURCE)), "the phone changed last");
    var c = Skies.chosen();
    Test.assertMessage(c[0] == 2 && c[1] == 3, "so the phone's sky and time colour are drawn");
    Test.assertEqualMessage(Skies.colors(Lib.Look.YOURS)[Skies.TIME], Skies.TIMES[3], "in your own look");
    Skies.changedInEditor();
    Test.assertMessage(Skies.EDITOR.equals(Application.Storage.getValue(Skies.SOURCE)), "then the editor");
    c = Skies.chosen();
    Test.assertMessage(c[0] >= 0 && c[0] < Skies.SETS.size() && c[1] >= 0 && c[1] < Skies.TIMES.size(), "the editor's choice is the face's own");
    if (!(Application has :WatchFaceConfig)) {
        Test.assertMessage(c[0] == 2 && c[1] == 3, "with no editor, the phone's stand");
    }
    Skies.changedOnPhone();
    c = Skies.chosen();
    Test.assertMessage(c[0] == 2 && c[1] == 3, "and the phone again, later, wins");
    Application.Properties.setValue("Theme", (theme instanceof Number) ? theme as Number : 0);
    Application.Properties.setValue("TimeColor", (time instanceof Number) ? time as Number : 0);
    if (source instanceof String) {
        Application.Storage.setValue(Skies.SOURCE, source as String);
    } else {
        Application.Storage.deleteValue(Skies.SOURCE);
    }
    return true;
}

// Lib.WatchMenu: the settings on the watch are the phone app's list, and a
// choice there writes the same property, winning over the editor
(:test)
function testDaylightWatchMenu(logger as Logger) as Boolean {
    var entries = Choices.entries();
    Test.assertEqualMessage(entries.size(), 3, "the look, the sky and the time colour, as on the phone");
    Test.assertMessage(entries[0][1] == null, "the look first");
    Test.assertEqualMessage(DaylightTesting.joined(entries[0][3] as Array<Number>), DaylightTesting.joined(Lib.Look.ORDER), "the looks in Lib.Look's order");
    Test.assertEqualMessage(entries[1][2].size(), Skies.SETS.size(), "every sky offered");
    Test.assertEqualMessage(entries[2][2].size(), Skies.TIMES.size(), "every time colour offered");
    for (var i = 0; i < entries.size(); i++) {
        Test.assertEqualMessage(entries[i][2].size(), entries[i][3].size(), "a label for every choice");
    }
    var sky = entries[1];
    var was = Application.Properties.getValue("Theme");
    var source = Application.Storage.getValue(Skies.SOURCE);
    Skies.changedInEditor();
    Lib.WatchMenu.choose(sky, 1);
    Test.assertEqualMessage(Lib.WatchMenu.current(sky), 1, "the choice is where the setting stands");
    Test.assertEqualMessage(Lib.WatchMenu.label(sky), sky[2][1], "and its label shows");
    Test.assertMessage(Skies.PHONE.equals(Application.Storage.getValue(Skies.SOURCE)), "a choice on the watch wins over the editor");
    Test.assertEqualMessage(Skies.chosen()[0], 1, "and is the sky drawn");
    var look = Application.Storage.getValue(Lib.Look.KEY);
    var phone = Application.Properties.getValue(Lib.Look.KEY);
    var seen = Application.Storage.getValue(Lib.Look.SEEN);
    Lib.WatchMenu.choose(entries[0], 4);              // the fifth look in the order: low light
    Test.assertEqualMessage(Lib.Look.mode(), Lib.Look.LOW, "the look chosen as a hold chooses it");
    Test.assertEqualMessage(Skies.colors(Lib.Look.mode())[Skies.TIME], Skies.LOW[Skies.TIME], "and draws low light");
    restoreLook(look, phone, seen);
    Application.Properties.setValue("Theme", (was instanceof Number) ? was as Number : 0);
    if (source instanceof String) {
        Application.Storage.setValue(Skies.SOURCE, source as String);
    } else {
        Application.Storage.deleteValue(Skies.SOURCE);
    }
    return true;
}

// The look as it was before a test: in storage, the phone's setting and the
// phone's last seen (a test's holds and choices move all three)
function restoreLook(stored as Object?, phone as Object?, seen as Object?) as Void {
    if (stored instanceof Number) {
        Application.Storage.setValue(Lib.Look.KEY, stored as Number);
    } else {
        Application.Storage.deleteValue(Lib.Look.KEY);
    }
    Application.Properties.setValue(Lib.Look.KEY, (phone instanceof Number) ? phone as Number : Lib.Look.YOURS);
    if (seen instanceof Number) {
        Application.Storage.setValue(Lib.Look.SEEN, seen as Number);
    } else {
        Application.Storage.deleteValue(Lib.Look.SEEN);
    }
    Lib.Look.changedAt = null;
}
