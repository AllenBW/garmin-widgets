import Toybox.Application.Storage;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;
import Toybox.Time;

// Run No Evil tests for Sun & Moon: scripts/test.sh sunmoon [device].
// Reference times are from the NOAA solar calculator.

(:test)
function testSolarKnownTimes(logger as Logger) as Boolean {
    // New York, 21 June 2024 (local day starts 04:00 UTC): sunrise 05:25, sunset 20:31 EDT
    var nyc = Lib.Solar.crossings(40.7128, -74.0060, 1718942400, Lib.Solar.RISE_SET);
    var rise = nyc[0];
    var set = nyc[1];
    logger.debug("NYC rise " + rise + " set " + set);
    Test.assertMessage(rise != null && (rise - 1718961907).abs() < 180, "NYC sunrise 05:25 EDT");
    Test.assertMessage(set != null && (set - 1719016250).abs() < 180, "NYC sunset 20:31 EDT");
    var golden = Lib.Solar.crossings(40.7128, -74.0060, 1718942400, Lib.Solar.GOLDEN_HIGH);
    var gm = golden[0];
    var ge = golden[1];
    Test.assertMessage(gm != null && (gm - 1718964386).abs() < 180, "NYC sun at +6 at 06:06");
    Test.assertMessage(ge != null && (ge - 1719013771).abs() < 180, "NYC sun at +6 at 19:49");

    // London, 21 December 2024: sunrise 08:04, sunset 15:53 GMT
    var london = Lib.Solar.crossings(51.5074, -0.1278, 1734739200, Lib.Solar.RISE_SET);
    rise = london[0];
    set = london[1];
    logger.debug("London rise " + rise + " set " + set);
    Test.assertMessage(rise != null && (rise - 1734768240).abs() < 180, "London sunrise 08:04");
    Test.assertMessage(set != null && (set - 1734796419).abs() < 180, "London sunset 15:53");

    // Tromso, 21 June 2024: the sun never sets
    var tromso = Lib.Solar.crossings(69.65, 18.96, 1718920800, Lib.Solar.RISE_SET);
    Test.assertMessage(tromso[0] == null && tromso[1] == null, "midnight sun");

    // Elevation: 68.9 degrees at New York's local noon, below the horizon at midnight
    var noon = Lib.Solar.elevation(40.7128, -74.0060, 1718942400 + 43200);
    Test.assertMessage((noon - 68.87).abs() < 0.5, "NYC noon elevation: " + noon);
    Test.assertMessage(Lib.Solar.elevation(40.7128, -74.0060, 1718942400) < -20.0, "NYC midnight elevation");
    return true;
}

(:test)
function testSolarDayOrder(logger as Logger) as Boolean {
    var d = Lib.Solar.day(51.5074, -0.1278, 1734739200);
    var order = [d.blueMorningStart, d.goldenMorningStart, d.rise, d.goldenMorningEnd,
                 d.goldenEveningStart, d.set, d.goldenEveningEnd, d.blueEveningEnd];
    for (var i = 1; i < order.size(); i++) {
        var a = order[i - 1];
        var b = order[i];
        Test.assertMessage(a != null && b != null && a < b, "event " + i + " after event " + (i - 1));
    }
    return true;
}

(:test)
function testModelWindows(logger as Logger) as Boolean {
    var lat = 51.5074;
    var lon = -0.1278;
    var day = 1734739200;   // London, 21 Dec 2024 00:00 UTC
    var morning = SunModel.statusAt(lat, lon, day + 10 * 3600);
    Test.assertMessage(morning.located, "located");
    var next = morning.nextEvent;
    var goldenAt = morning.goldenAt;
    var blueAt = morning.blueAt;
    Test.assertMessage(!morning.nextIsRise && next != null && (next - 1734796419).abs() < 180, "10:00: next is sunset");
    Test.assertMessage(!morning.goldenNow && goldenAt != null && (goldenAt - 1734792716).abs() < 180, "10:00: golden hour at 14:52");
    Test.assertMessage(!morning.blueNow && blueAt != null && (blueAt - 1734797929).abs() < 180, "10:00: blue hour at 16:19");
    logger.debug(SunText.headline(morning) + " / " + SunText.goldenLine(morning, day + 10 * 3600));

    var golden = SunModel.statusAt(lat, lon, day + 15 * 3600);
    goldenAt = golden.goldenAt;
    Test.assertMessage(golden.goldenNow && goldenAt != null && (goldenAt - 1734797929).abs() < 180, "15:00: in golden hour until 16:19");
    Test.assertMessage(SunText.goldenLine(golden, day + 15 * 3600).find("ends in") != null, "golden line says ends");

    var evening = SunModel.statusAt(lat, lon, day + 17 * 3600);
    next = evening.nextEvent;
    goldenAt = evening.goldenAt;
    blueAt = evening.blueAt;
    Test.assertMessage(evening.nextIsRise && next != null && next > day + 86400, "17:00: next is tomorrow's sunrise");
    Test.assertMessage(!evening.goldenNow && goldenAt != null && goldenAt > day + 86400, "17:00: next golden hour is tomorrow morning");
    Test.assertMessage(!evening.blueNow && blueAt != null && blueAt > day + 86400, "17:00: next blue hour is tomorrow morning");

    var none = SunModel.statusAt(69.65, 18.96, 1718920800 + 12 * 3600);   // Tromso in June
    logger.debug("Tromso: " + SunText.headline(none) + " / " + SunText.goldenLine(none, 1718920800 + 12 * 3600));
    Test.assertMessage(none.located, "located even with no sunset");
    return true;
}

(:test)
function testGlanceFmt(logger as Logger) as Boolean {
    Test.assertEqualMessage(Lib.Fmt.countdown(6 * 3600 + 48 * 60), "6h 48m", "hours and minutes");
    Test.assertEqualMessage(Lib.Fmt.countdown(45 * 60), "45m", "minutes");
    Test.assertEqualMessage(Lib.Fmt.countdown(30), "now", "now");
    Test.assertEqualMessage(Lib.Fmt.countdown(25 * 3600), "1d 1h", "days");
    Test.assertEqualMessage(Lib.Fmt.clock(6 * 3600 + 52 * 60), "6:52", "clock");
    Test.assertMessage(Lib.Fmt.localSeconds(Time.now().value()) < 86400, "local seconds");
    return true;
}

(:test)
function testGlanceAndAppDraw(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var w = settings.screenWidth;
    var h = settings.screenHeight;
    var screen = (Graphics.createBufferedBitmap({:width => w, :height => h}).get() as Graphics.BufferedBitmap).getDc();
    var glanceDc = (Graphics.createBufferedBitmap({:width => (w * 0.77).toNumber(), :height => (h * 0.29).toNumber()}).get() as Graphics.BufferedBitmap).getDc();

    var where = Lib.Location.get();
    logger.debug("location: " + where);
    var glance = new SunGlance();
    glance.onLayout(glanceDc);
    glance.onShow();
    glance.onUpdate(glanceDc);
    var view = new SunView();
    view.onLayout(screen);
    view.onShow();
    view.onUpdate(screen);

    var stats = System.getSystemStats();
    logger.debug("memory: " + stats.usedMemory + " of " + stats.totalMemory + " bytes used");
    return true;
}
