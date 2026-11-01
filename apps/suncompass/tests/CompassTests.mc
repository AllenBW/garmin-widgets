import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Test;
import Toybox.Time;
import Toybox.Time.Gregorian;

// Run No Evil tests for Sun Compass: scripts/test.sh suncompass [device].
// Reference positions are from the NOAA solar calculator equations, cross-
// checked against an independent (Schlyter) model; they agree to 0.02 degrees.

(:test)
function testSolarAltAz(logger as Logger) as Boolean {
    // New York, 21 June 2024
    var p = Lib.Solar.altAz(40.7128, -74.0060, 1718971200);   // 08:00 EDT
    logger.debug("NYC 08:00 alt " + p[0] + " az " + p[1]);
    Test.assertMessage((p[0] - 26.45).abs() < 0.3 && (p[1] - 80.91).abs() < 0.3, "NYC 08:00: 26 up, east");
    p = Lib.Solar.altAz(40.7128, -74.0060, 1718985600);       // 12:00 EDT, before solar noon
    Test.assertMessage((p[0] - 68.87).abs() < 0.3 && (p[1] - 140.43).abs() < 0.3, "NYC 12:00: 69 up, south-east");
    p = Lib.Solar.altAz(40.7128, -74.0060, 1719003600);       // 17:00 EDT
    Test.assertMessage((p[0] - 37.01).abs() < 0.3 && (p[1] - 270.48).abs() < 0.3, "NYC 17:00: 37 up, west");
    p = Lib.Solar.altAz(40.7128, -74.0060, 1718961907);       // sunrise
    Test.assertMessage((p[0] + 0.83).abs() < 0.3 && (p[1] - 57.5).abs() < 0.3, "NYC sunrise at 57");

    // London, 21 December 2024
    p = Lib.Solar.altAz(51.5074, -0.1278, 1734782400);        // 12:00 GMT
    Test.assertMessage((p[0] - 15.05).abs() < 0.3 && (p[1] - 180.28).abs() < 0.3, "London noon: 15 up, south");
    p = Lib.Solar.altAz(51.5074, -0.1278, 1734739200);        // midnight
    Test.assertMessage((p[0] + 61.93).abs() < 0.3 && (p[1] < 1.0 || p[1] > 359.0), "London midnight: deep below, north");
    return true;
}

(:test)
function testModelPath(logger as Logger) as Boolean {
    var lat = 51.5074;
    var lon = -0.1278;
    var day = 1734739200;   // London, 21 Dec 2024 00:00 UTC

    var morning = CompassModel.statusAt(lat, lon, day + 10 * 3600);
    Test.assertMessage(morning.located && morning.up, "10:00: sun up");
    var next = morning.nextEvent;
    var riseAz = morning.riseAz;
    var setAz = morning.setAz;
    Test.assertMessage(!morning.nextIsRise && next != null && (next - 1734796419).abs() < 180, "10:00: next is sunset");
    Test.assertMessage(riseAz != null && (riseAz - 128.4).abs() < 0.5, "sunrise bearing 128");
    Test.assertMessage(setAz != null && (setAz - 231.6).abs() < 0.5, "sunset bearing 232");
    Test.assertEqualMessage(morning.hours.size(), 7, "the sun is up at seven full hours, 09:00 to 15:00");
    // The dots are at the watch's local full hours, so their labels follow the simulator's time zone
    var noonLocal = Gregorian.info(new Time.Moment(day + 12 * 3600), Time.FORMAT_SHORT).hour;
    var noon = morning.hours[3];
    Test.assertMessage(noon[0] == noonLocal && (noon[1] - 15.05).abs() < 0.3 && (noon[2] - 180.28).abs() < 0.3, "the fourth dot is noon: " + noon);
    Test.assertMessage(morning.hours[0][0] == (noonLocal + 21) % 24 && morning.hours[6][0] == (noonLocal + 3) % 24, "dots from 09:00 to 15:00 GMT");
    logger.debug(CompassText.headline(morning) + " / " + CompassText.detail(morning));
    Test.assertEqualMessage(CompassText.headline(morning), "Sun 152° SE", "headline");
    var line = CompassText.nextLine(morning);
    Test.assertMessage(line.find("sets ") == 0 && line.find(":53 at 232°") != null, "next line: " + line);
    var detail = CompassText.detail(morning);
    Test.assertMessage(detail.find("sets ") == 0 && detail.find(" · 232°") != null, "glance detail: " + detail);

    var evening = CompassModel.statusAt(lat, lon, day + 17 * 3600);
    next = evening.nextEvent;
    Test.assertMessage(!evening.up, "17:00: sun down");
    Test.assertMessage(evening.nextIsRise && next != null && next > day + 86400, "17:00: next is tomorrow's sunrise");
    Test.assertEqualMessage(evening.hours.size(), 7, "tomorrow's path has seven dots too");
    Test.assertEqualMessage(CompassText.headline(evening), "Sun below horizon", "night headline");
    var night = CompassText.nextLine(evening);   // the clock follows the simulator's time zone
    Test.assertMessage(night.find("rises ") == 0 && night.find(" at 128°") != null, "night next line: " + night);

    // New York in June: fifteen daylight hours on the dial
    var summer = CompassModel.statusAt(40.7128, -74.0060, 1718985600);
    Test.assertEqualMessage(summer.hours.size(), 15, "NYC June: 06:00 to 20:00");

    // Tromso in June: no events, up all day
    var polar = CompassModel.statusAt(69.65, 18.96, 1718920800 + 12 * 3600);
    Test.assertMessage(polar.located && polar.up && polar.nextEvent == null, "midnight sun");
    Test.assertEqualMessage(polar.hours.size(), 24, "all 24 dots");
    Test.assertEqualMessage(CompassText.nextLine(polar), "up all day", "polar text");

    var nowhere = new SunSky();
    Test.assertEqualMessage(CompassText.headline(nowhere), "No location yet", "no location");
    return true;
}

(:test)
function testBearings(logger as Logger) as Boolean {
    Test.assertEqualMessage(CompassModel.cardinal(0.0), "N", "north");
    Test.assertEqualMessage(CompassModel.cardinal(22.4), "N", "just short of NE");
    Test.assertEqualMessage(CompassModel.cardinal(22.6), "NE", "just past");
    Test.assertEqualMessage(CompassModel.cardinal(213.0), "SW", "south-west");
    Test.assertEqualMessage(CompassModel.cardinal(337.5), "N", "wraps to north");
    Test.assertEqualMessage(CompassModel.cardinal(359.9), "N", "north again");
    Test.assertEqualMessage(CompassModel.cardinal(-90.0), "W", "negative bearings");

    Test.assertMessage((CompassModel.headingDegrees(Math.toRadians(-90.0).toFloat()) - 270.0).abs() < 0.01, "-pi/2 is 270");
    Test.assertMessage((CompassModel.headingDegrees(0.0) - 0.0).abs() < 0.01, "0 is 0");

    Test.assertMessage((CompassModel.angleDiff(350.0, 10.0) - 20.0).abs() < 0.01, "350 to 10 is +20");
    Test.assertMessage((CompassModel.angleDiff(10.0, 350.0) + 20.0).abs() < 0.01, "10 to 350 is -20");
    Test.assertMessage((CompassModel.smooth(350.0, 10.0, 0.5) - 0.0).abs() < 0.01, "halfway across north");
    Test.assertMessage((CompassModel.smooth(10.0, 350.0, 0.5) - 0.0).abs() < 0.01, "and back");
    Test.assertMessage((CompassModel.smooth(100.0, 120.0, 0.25) - 105.0).abs() < 0.01, "a quarter of the way");

    Test.assertEqualMessage(CompassText.degrees(359.7), "0°", "rounds to 0");
    Test.assertEqualMessage(CompassText.degrees(148.4), "148°", "rounds down");
    Test.assertEqualMessage(CompassText.degrees(-0.83), "-1°", "negative");

    var label = CompassText.hourLabel(15);   // "15", or "3" on a 12-hour watch
    Test.assertMessage(label.equals("15") || label.equals("3"), "hour label: " + label);
    label = CompassText.hourLabel(0);
    Test.assertMessage(label.equals("0") || label.equals("12"), "midnight label: " + label);
    Test.assertEqualMessage(CompassText.hourLabel(12), "12", "noon label");
    return true;
}

(:test)
function testGlanceAndAppDraw(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var w = settings.screenWidth;
    var h = settings.screenHeight;
    var screen = (Graphics.createBufferedBitmap({:width => w, :height => h}).get() as Graphics.BufferedBitmap).getDc();
    var glanceDc = (Graphics.createBufferedBitmap({:width => (w * 0.77).toNumber(), :height => (h * 0.29).toNumber()}).get() as Graphics.BufferedBitmap).getDc();

    logger.debug("location: " + Lib.Location.get());
    var glance = new CompassGlance();
    glance.onLayout(glanceDc);
    glance.onShow();
    glance.onUpdate(glanceDc);

    var view = new CompassView();
    view.onLayout(screen);
    Test.assertMessage(view.setHeading(Math.toRadians(213.0).toFloat()), "first reading is a change");
    Test.assertMessage(!view.setHeading(Math.toRadians(213.1).toFloat()), "a tenth of a degree is not");
    Test.assertMessage(view.setHeading(Math.toRadians(300.0).toFloat()), "a turn is");
    var p = view.project(90.0, 0.0, 0.0, 100, 100, 50);
    Test.assertMessage(p[0] == 100 && p[1] == 100, "straight up is the centre");
    p = view.project(0.0, 90.0, 0.0, 100, 100, 50);
    Test.assertMessage(p[0] == 150 && p[1] == 100, "east on the horizon is the right of the ring");
    p = view.project(0.0, 90.0, 90.0, 100, 100, 50);
    Test.assertMessage(p[0] == 100 && p[1] == 50, "facing east, east is at the top");
    p = view.project(45.0, 180.0, 0.0, 100, 100, 50);
    Test.assertMessage(p[0] == 100 && p[1] == 125, "south, halfway up");

    for (var i = 0; i < 3; i++) {
        var started = System.getTimer();
        view.onUpdate(screen);
        logger.debug("draw " + i + ": " + (System.getTimer() - started) + " ms");
    }
    view.setHeading(null);
    view.onUpdate(screen);

    var stats = System.getSystemStats();
    logger.debug("memory: " + stats.usedMemory + " of " + stats.totalMemory + " bytes used");
    return true;
}
