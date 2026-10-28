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
