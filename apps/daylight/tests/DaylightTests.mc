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
    logger.debug("location: " + Lib.Location.get());
    var stats = System.getSystemStats();
    logger.debug("memory: " + stats.usedMemory + " of " + stats.totalMemory + " bytes used");
    return true;
}
