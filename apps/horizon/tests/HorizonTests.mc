import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

// Run No Evil tests for Horizon: scripts/test.sh horizon [device].

(:test)
function testOutlook(logger as Logger) as Boolean {
    var now = 10 * 3600 + 8 * 60;      // 10:08
    var hours = [] as Array<[Number, Number]>;
    for (var k = 0; k < 13; k++) {
        var chance = (k == 5) ? 70 : ((k == 6) ? 45 : ((k == 7) ? 25 : 5));   // rain from 15:00
        hours.add([10 * 3600 + k * 3600, chance]);
    }
    var rise = 6 * 3600 + 52 * 60;
    var set = 17 * 3600 + 41 * 60;
    var o = HorizonModel.build(now, hours, rise, set, rise + 86400 + 60, "16:00");
    Test.assertEqualMessage(o.hourStart, 10 * 3600, "current hour");
    Test.assertMessage(o.hasForecast, "has forecast");
    Test.assertEqualMessage(o.rain[0], 5, "slot 0 is 10:00");
    Test.assertEqualMessage(o.rain[5], 70, "15:00 is 70 %");
    var from = o.rainFrom;
    Test.assertMessage(from != null && from == 5, "rain from slot 5");
    Test.assertEqualMessage(HorizonModel.rainText(o), "rain from " + Lib.Fmt.clock(15 * 3600) + ", 70%", "rain line");
    Test.assertMessage(!o.night[0] && !o.night[7], "10:00 and 17:00 are day");
    Test.assertMessage(o.night[8] && o.night[11], "18:00 and 21:00 are night");
    var sun = o.sunSecs;
    Test.assertMessage(sun != null && sun == set && !o.sunIsRise, "next sun event is sunset");
    var cal = o.calendarSecs;
    Test.assertMessage(cal != null && cal == 16 * 3600, "event at 16:00");
    logger.debug(HorizonModel.rainText(o));

    // Evening: the window wraps past midnight, sunrise tomorrow inside it
    var evening = HorizonModel.build(20 * 3600, [] as Array<[Number, Number]>, rise, set, rise + 86400, "7:30 am");
    Test.assertEqualMessage(HorizonModel.rainText(evening), "no forecast", "no forecast");
    Test.assertMessage(evening.night[0] && evening.night[3], "20:00 and 23:00 are night");
    Test.assertMessage(evening.night[4] && evening.night[10], "00:00 and 06:00 are night");
    Test.assertMessage(!evening.night[11], "07:00 is day (sunrise 06:52)");
    sun = evening.sunSecs;
    Test.assertMessage(sun != null && sun == rise + 86400 && evening.sunIsRise, "next sun event is tomorrow's sunrise");
    cal = evening.calendarSecs;
    Test.assertMessage(cal != null && cal == 86400 + 7 * 3600 + 30 * 60, "7:30 am is tomorrow");

    // Rain now
    var wet = HorizonModel.build(now, [[10 * 3600, 80]] as Array<[Number, Number]>, rise, set, null, null);
    Test.assertEqualMessage(HorizonModel.rainText(wet), "rain now, 80%", "rain now");
    var dryHours = [] as Array<[Number, Number]>;
    for (var k = 0; k < 12; k++) {
        dryHours.add([10 * 3600 + k * 3600, 10]);
    }
    var dry = HorizonModel.build(now, dryHours, rise, set, null, null);
    Test.assertEqualMessage(HorizonModel.rainText(dry), "no rain in the next 12 h", "dry");
    var short = HorizonModel.build(now, [[10 * 3600, 10], [11 * 3600, 10]] as Array<[Number, Number]>, rise, set, null, null);
    Test.assertEqualMessage(HorizonModel.rainText(short), "no rain until " + Lib.Fmt.clock(12 * 3600), "a short forecast says how far it reaches");
    var stale = HorizonModel.build(now, [[3 * 3600, 10], [4 * 3600, 10]] as Array<[Number, Number]>, rise, set, null, null);
    Test.assertEqualMessage(HorizonModel.rainText(stale), "no forecast", "an old forecast is no forecast");
    var raining = HorizonModel.build(now, [[now, 90], [11 * 3600, 10]] as Array<[Number, Number]>, rise, set, null, null);
    Test.assertEqualMessage(HorizonModel.rainText(raining), "rain now, 90%", "the conditions now fill this hour");
    Test.assertMessage(dry.sunSecs != null, "sunset within 12 h of 10:08");
    var late = HorizonModel.build(5 * 3600, [] as Array<[Number, Number]>, rise, set, null, null);
    Test.assertMessage(late.sunSecs != null && late.sunIsRise, "sunrise next at 05:00");
    return true;
}

(:test)
function testParseClock(logger as Logger) as Boolean {
    var cases = [["16:05", 16 * 3600 + 5 * 60], ["4:05 pm", 16 * 3600 + 5 * 60], ["12:00 AM", 0],
                 ["12:30 PM", 12 * 3600 + 30 * 60], ["9 am", 9 * 3600]] as Array<[String, Number]>;
    for (var i = 0; i < cases.size(); i++) {
        var parsed = HorizonModel.parseClock(cases[i][0]);
        Test.assertMessage(parsed != null && parsed == cases[i][1], cases[i][0] + " -> " + parsed);
    }
    Test.assertMessage(HorizonModel.parseClock(null) == null, "null");
    Test.assertMessage(HorizonModel.parseClock("none") == null, "no digits");
    Test.assertMessage(HorizonModel.parseClock("25:00") == null, "out of range");
    Test.assertMessage(HorizonModel.parseClock("11/3") == null, "a date is not a time");
    Test.assertMessage(HorizonModel.parseClock("Room 2") == null, "a bare number is not a time");
    var at = HorizonModel.parseClock("Team at 4:05 pm");
    Test.assertMessage(at != null && at == 16 * 3600 + 5 * 60, "the 'a' in 'at' is not am: " + at);
    var tomorrow = HorizonModel.parseClock("Tomorrow 9:00");
    Test.assertMessage(tomorrow != null && tomorrow == 9 * 3600, "words before the time");
    Test.assertMessage(HorizonModel.parseClock("123:45") == null, "three digits");
    return true;
}

(:test)
function testDial(logger as Logger) as Boolean {
    Test.assertEqualMessage(HorizonModel.dialDegrees(0), 0.0, "midnight at 12");
    Test.assertEqualMessage(HorizonModel.dialDegrees(3 * 3600), 90.0, "3:00 at 3");
    Test.assertEqualMessage(HorizonModel.dialDegrees(15 * 3600), 90.0, "15:00 at 3");
    Test.assertEqualMessage(HorizonModel.dialDegrees(18 * 3600 + 30 * 60), 195.0, "18:30");
    return true;
}

(:test)
function testFaceDrawsBothModes(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var w = settings.screenWidth;
    var h = settings.screenHeight;
    var dc = (Graphics.createBufferedBitmap({:width => w, :height => h}).get() as Graphics.BufferedBitmap).getDc();
    var view = new HorizonView();
    view.onLayout(dc);
    view.onUpdate(dc);
    view.onEnterSleep();
    view.onUpdate(dc);
    view.onExitSleep();
    view.onUpdate(dc);
    var stats = System.getSystemStats();
    logger.debug("memory: " + stats.usedMemory + " of " + stats.totalMemory + " bytes used");
    return true;
}

// ------------------------------------------------------------ the settings

module HorizonTesting {

    function screen() as Graphics.Dc {
        var s = System.getDeviceSettings();
        return (Graphics.createBufferedBitmap({:width => s.screenWidth, :height => s.screenHeight}).get() as Graphics.BufferedBitmap).getDc();
    }

    // Lit, then in standby, then lit again
    function both(view as HorizonView, dc as Graphics.Dc) as Void {
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
function testHorizonDefaults(logger as Logger) as Boolean {
    var c = Skies.palette(Lib.Look.YOURS, [0, 0] as [Number, Number], 0);
    Test.assertEqualMessage(c[Skies.TRACK], 0x262626, "track as it was");
    Test.assertEqualMessage(c[Skies.NIGHT], 0x1A2A4A, "night as it was");
    Test.assertEqualMessage(c[Skies.RAIN_LOW], 0x1C5A6B, "rain_low as it was");
    Test.assertEqualMessage(c[Skies.RAIN_MID], 0x2A8CA3, "rain_mid as it was");
    Test.assertEqualMessage(c[Skies.RAIN], 0x3EC6E0, "rain as it was");
    Test.assertEqualMessage(c[Skies.RISE], 0xFFB020, "rise as it was");
    Test.assertEqualMessage(c[Skies.SET], 0xFF7A3D, "set as it was");
    Test.assertEqualMessage(c[Skies.TEXT], 0x8A8A8A, "text as it was");
    Test.assertEqualMessage(c[Skies.FAINT], 0x5A5A5A, "faint as it was");
    Test.assertEqualMessage(c[Skies.TIME], 0xF2F2F2, "time as it was");
    Test.assertEqualMessage(Skies.standby(0xF2F2F2), 0x8A8A8A, "the time in standby as it was");
    Test.assertEqualMessage(Skies.SETS[0].size(), Skies.TIME + 1, "a colour for every place");
    return true;
}

// Every look draws, lit with its name for a moment and in standby; then
// every sky with every time colour, and the daily look's every sky
(:test)
function testHorizonLooksAndSkies(logger as Logger) as Boolean {
    var dc = HorizonTesting.screen();
    var view = new HorizonView();
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
        HorizonTesting.both(view, dc);
    }
    Test.assertEqualMessage(titles[0], "YOUR LOOK", "your own look's name");
    Test.assertEqualMessage(titles[1], "HI-VIS ORANGE", "high visibility's");
    Lib.Look.changedAt = null;
    for (var s = 0; s < Skies.SETS.size(); s++) {
        for (var t = 0; t < Skies.TIMES.size(); t++) {
            var c = Skies.palette(Lib.Look.YOURS, [s, t] as [Number, Number], 0);
            Test.assertEqualMessage(c[Skies.TIME], Skies.TIMES[t], "the time colour chosen");
            view.setColors(c);
            HorizonTesting.both(view, dc);
        }
        var daily = Skies.palette(Lib.Look.DAILY, [0, 0] as [Number, Number], s);
        Test.assertEqualMessage(HorizonTesting.joined(daily), HorizonTesting.joined(Skies.SETS[s]), "the daily look: a sky a day");
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
function testHorizonChosen(logger as Logger) as Boolean {
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
function testHorizonWatchMenu(logger as Logger) as Boolean {
    var entries = Choices.entries();
    Test.assertEqualMessage(entries.size(), 3, "the look, the sky and the time colour, as on the phone");
    Test.assertMessage(entries[0][1] == null, "the look first");
    Test.assertEqualMessage(HorizonTesting.joined(entries[0][3] as Array<Number>), HorizonTesting.joined(Lib.Look.ORDER), "the looks in Lib.Look's order");
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
