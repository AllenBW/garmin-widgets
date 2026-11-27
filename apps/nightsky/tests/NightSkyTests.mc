import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;
import Toybox.Time;

// Run No Evil tests for Night Sky: scripts/test.sh nightsky [device].

(:test)
function testSkyKnownPositions(logger as Logger) as Boolean {
    // Greenwich mean sidereal time at J2000.0 (2000-01-01 12:00 UTC): 18h 41m 50s
    Test.assertMessage((Lib.Sky.gmst(946728000) - 280.461).abs() < 0.01, "GMST at J2000");

    // The Sun at the June solstice 2024, 12:00 UTC: RA 90, Dec +23.4
    var sun = Lib.Sky.sun(1718971200);
    logger.debug("sun " + sun);
    Test.assertMessage((sun[0] - 90.0).abs() < 1.5 && (sun[1] - 23.44).abs() < 0.3, "solstice sun");

    // Full moon 2024-01-25 17:54 UTC: opposite the Sun
    var moon = Lib.Sky.moon(1706205240);
    var sunThen = Lib.Sky.sun(1706205240);
    var apart = moon[0] - sunThen[0];
    while (apart < 0) { apart += 360.0; }
    logger.debug("full moon " + moon + " sun " + sunThen);
    Test.assertMessage((apart - 180.0).abs() < 4.0, "full moon opposite the sun: " + apart);

    // Jupiter in Aries and Saturn in Aquarius on 2024-01-25 (JPL, about a degree)
    var jupiter = Lib.Sky.planet(Lib.Sky.JUPITER, 1706205240);
    var saturn = Lib.Sky.planet(Lib.Sky.SATURN, 1706205240);
    logger.debug("jupiter " + jupiter + " saturn " + saturn);
    Test.assertMessage((jupiter[0] - 34.0).abs() < 3.0 && (jupiter[1] - 12.5).abs() < 2.0, "Jupiter");
    Test.assertMessage((saturn[0] - 338.5).abs() < 3.0 && (saturn[1] + 10.0).abs() < 2.0, "Saturn");
    var venus = Lib.Sky.planet(Lib.Sky.VENUS, 1706205240);
    Test.assertMessage(venus[0] > 260.0 && venus[0] < 285.0, "Venus a morning star west of the Sun: " + venus);
    return true;
}

(:test)
function testAltAz(logger as Logger) as Boolean {
    // Polaris from London: altitude about the latitude, due north
    var lst = Lib.Sky.lst(1719874800, -0.13);   // 2024-07-01 23:00 UTC
    var polaris = Lib.Sky.altAz(37.95, 89.26, 51.5, lst);
    Test.assertMessage((polaris[0] - 51.5).abs() < 1.0, "Polaris altitude: " + polaris);
    Test.assertMessage(polaris[1] < 2.0 || polaris[1] > 358.0, "Polaris azimuth: " + polaris);
    // A point on the meridian at the latitude's declination is straight up
    var zenith = Lib.Sky.altAz(lst, 51.5, 51.5, lst);
    Test.assertMessage(zenith[0] > 89.9, "zenith: " + zenith);
    // Vega high in the summer sky from London
    var vega = Lib.Sky.altAz(279.23, 38.78, 51.5, lst);
    Test.assertMessage(vega[0] > 60.0, "Vega up: " + vega);
    return true;
}

(:test)
function testCatalogue(logger as Logger) as Boolean {
    Test.assertEqualMessage(Stars.RA.size(), Stars.COUNT, "RA size");
    Test.assertEqualMessage(Stars.DEC.size(), Stars.COUNT, "DEC size");
    Test.assertEqualMessage(Stars.MAG.size(), Stars.COUNT, "MAG size");
    Test.assertMessage(Stars.LINES.size() % 2 == 0, "line pairs");
    for (var k = 0; k < Stars.LINES.size(); k++) {
        Test.assertMessage(Stars.LINES[k] >= 0 && Stars.LINES[k] < Stars.COUNT, "line index in range");
    }
    for (var i = 1; i < Stars.COUNT; i++) {
        Test.assertMessage(Stars.MAG[i] >= Stars.MAG[i - 1], "brightest first");
        Test.assertMessage(Stars.RA[i] >= 0 && Stars.RA[i] < 3600 && Stars.DEC[i] >= -900 && Stars.DEC[i] <= 900, "coordinates in range");
    }
    Test.assertMessage(Stars.MAG[0] < -10, "Sirius first");
    return true;
}

(:test)
function testProjection(logger as Logger) as Boolean {
    var view = new NightSkyView();
    var top = view.project(90.0, 0.0, 227, 227, 213.0);
    Test.assertMessage(top[0] == 227 && top[1] == 227, "zenith at the centre: " + top);
    var north = view.project(0.0, 0.0, 227, 227, 213.0);
    Test.assertMessage(north[0] == 227 && north[1] == 14, "north on the horizon at the top: " + north);
    var east = view.project(0.0, 90.0, 227, 227, 213.0);
    Test.assertMessage(east[0] == 14 && (east[1] - 227).abs() <= 1, "east on the left: " + east);
    var halfway = view.project(45.0, 180.0, 227, 227, 213.0);
    Test.assertMessage(halfway[0] == 227 && (halfway[1] - 333).abs() <= 1, "45 degrees up in the south: " + halfway);
    return true;
}

(:test)
function testFaceDrawsBothModes(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var w = settings.screenWidth;
    var h = settings.screenHeight;
    var dc = (Graphics.createBufferedBitmap({:width => w, :height => h}).get() as Graphics.BufferedBitmap).getDc();
    var view = new NightSkyView();
    view.onLayout(dc);
    var before = System.getTimer();
    view.refresh(w, h, true);
    logger.debug("placing the sky " + (System.getTimer() - before) + " ms, location " + Lib.Location.get());
    before = System.getTimer();
    view.onUpdate(dc);
    logger.debug("first draw " + (System.getTimer() - before) + " ms");
    view.onEnterSleep();
    before = System.getTimer();
    view.onUpdate(dc);
    logger.debug("always-on draw " + (System.getTimer() - before) + " ms");
    view.onExitSleep();
    before = System.getTimer();
    view.onUpdate(dc);
    logger.debug("second active draw " + (System.getTimer() - before) + " ms");
    var stats = System.getSystemStats();
    logger.debug("memory: " + stats.usedMemory + " of " + stats.totalMemory + " bytes used");
    return true;
}

// ------------------------------------------------------------ the settings

module NightSkyTesting {

    function screen() as Graphics.Dc {
        var s = System.getDeviceSettings();
        return (Graphics.createBufferedBitmap({:width => s.screenWidth, :height => s.screenHeight}).get() as Graphics.BufferedBitmap).getDc();
    }

    // Lit, then in standby, then lit again
    function both(view as NightSkyView, dc as Graphics.Dc) as Void {
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
function testNightSkyDefaults(logger as Logger) as Boolean {
    var c = Skies.palette(Lib.Look.YOURS, [0, 0] as [Number, Number], 0);
    Test.assertEqualMessage(c[Skies.STAR1], 0xF2F2F2, "star1 as it was");
    Test.assertEqualMessage(c[Skies.STAR2], 0xC8C8C8, "star2 as it was");
    Test.assertEqualMessage(c[Skies.STAR3], 0x8A8A8A, "star3 as it was");
    Test.assertEqualMessage(c[Skies.STAR4], 0x5A5A5A, "star4 as it was");
    Test.assertEqualMessage(c[Skies.LINE], 0x161E33, "line as it was");
    Test.assertEqualMessage(c[Skies.VENUS], 0xFFFFFF, "venus as it was");
    Test.assertEqualMessage(c[Skies.MARS], 0xFF6B4A, "mars as it was");
    Test.assertEqualMessage(c[Skies.JUPITER], 0xF2E6C8, "jupiter as it was");
    Test.assertEqualMessage(c[Skies.SATURN], 0xE8D8A0, "saturn as it was");
    Test.assertEqualMessage(c[Skies.MOON], 0xF2F2F2, "moon as it was");
    Test.assertEqualMessage(c[Skies.SUN], 0xFFB020, "sun as it was");
    Test.assertEqualMessage(c[Skies.HORIZON], 0x5A5A5A, "horizon as it was");
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
function testNightSkyLooksAndSkies(logger as Logger) as Boolean {
    var dc = NightSkyTesting.screen();
    var view = new NightSkyView();
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
        NightSkyTesting.both(view, dc);
    }
    Test.assertEqualMessage(titles[0], "YOUR LOOK", "your own look's name");
    Test.assertEqualMessage(titles[1], "HI-VIS ORANGE", "high visibility's");
    Lib.Look.changedAt = null;
    for (var s = 0; s < Skies.SETS.size(); s++) {
        for (var t = 0; t < Skies.TIMES.size(); t++) {
            var c = Skies.palette(Lib.Look.YOURS, [s, t] as [Number, Number], 0);
            Test.assertEqualMessage(c[Skies.TIME], Skies.TIMES[t], "the time colour chosen");
            view.setColors(c);
            NightSkyTesting.both(view, dc);
        }
        var daily = Skies.palette(Lib.Look.DAILY, [0, 0] as [Number, Number], s);
        Test.assertEqualMessage(NightSkyTesting.joined(daily), NightSkyTesting.joined(Skies.SETS[s]), "the daily look: a sky a day");
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
function testNightSkyChosen(logger as Logger) as Boolean {
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
function testNightSkyWatchMenu(logger as Logger) as Boolean {
    var entries = Choices.entries();
    Test.assertEqualMessage(entries.size(), 3, "the look, the sky and the time colour, as on the phone");
    Test.assertMessage(entries[0][1] == null, "the look first");
    Test.assertEqualMessage(NightSkyTesting.joined(entries[0][3] as Array<Number>), NightSkyTesting.joined(Lib.Look.ORDER), "the looks in Lib.Look's order");
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
