import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

// Run No Evil tests for Forage: scripts/test.sh forage [device].

// One hour of weather at `hour` o'clock today
function fh(hour as Number, celsius as Numeric?, rain as Number, wind as Numeric, cloud as Number) as ForageHour {
    return new ForageHour(hour * 3600, celsius, rain, wind, cloud, null);
}

(:test)
function testKinds(logger as Logger) as Boolean {
    Test.assertEqualMessage(ForageModel.kind(fh(12, 20, 0, 2, 10), true, 12, true), BEES_OPEN, "warm calm noon: open");
    Test.assertEqualMessage(ForageModel.kind(fh(9, 20, 0, 2, 10), true, 9, true), BEES_FLY, "09:00 is too early to open");
    Test.assertEqualMessage(ForageModel.kind(fh(16, 20, 0, 2, 10), true, 16, true), BEES_FLY, "16:00 is too late to open");
    Test.assertEqualMessage(ForageModel.kind(fh(12, 16, 0, 2, 10), true, 12, true), BEES_FLY, "61 °F: flying, not open");
    Test.assertEqualMessage(ForageModel.kind(fh(12, 20, 0, 6, 10), true, 12, true), BEES_FLY, "13 mph: flying, not open");
    Test.assertEqualMessage(ForageModel.kind(fh(12, 20, 30, 2, 10), true, 12, true), BEES_FLY, "30 % rain: flying, not open");
    Test.assertEqualMessage(ForageModel.kind(fh(12, 20, 0, 2, 90), true, 12, true), BEES_FLY, "overcast: flying, not open");
    Test.assertEqualMessage(ForageModel.kind(fh(12, 20, 50, 2, 10), true, 12, true), BEES_RAIN, "50 % rain");
    Test.assertEqualMessage(ForageModel.kind(fh(22, 20, 50, 2, 10), false, 22, true), BEES_RAIN, "rain shows at night too");
    Test.assertEqualMessage(ForageModel.kind(fh(22, 20, 0, 2, 10), false, 22, true), BEES_NIGHT, "dark");
    Test.assertEqualMessage(ForageModel.kind(fh(12, 20, 0, 10, 10), true, 12, true), BEES_WIND, "22 mph");
    Test.assertEqualMessage(ForageModel.kind(fh(12, 11, 0, 2, 10), true, 12, true), BEES_CLEANSE, "52 °F and sunny");
    Test.assertEqualMessage(ForageModel.kind(fh(12, 11, 0, 2, 80), true, 12, true), BEES_COLD, "52 °F and grey");
    Test.assertEqualMessage(ForageModel.kind(fh(12, 11, 0, 2, 10), true, 12, false), BEES_COLD, "52 °F and sunny in May: just cold");
    Test.assertEqualMessage(ForageModel.kind(fh(12, 37, 0, 2, 10), true, 12, false), BEES_FLY, "99 °F: flying, too hot to open");
    Test.assertEqualMessage(ForageModel.kind(fh(12, 5, 0, 2, 10), true, 12, true), BEES_COLD, "41 °F");
    Test.assertEqualMessage(ForageModel.kind(fh(12, null, 0, 2, 10), true, 12, true), BEES_UNKNOWN, "no temperature");

    // The condition stands in for the numbers it can
    var clearSky = new ForageHour(12 * 3600, 20, 0, 2, null, 0);           // CONDITION_CLEAR, no cloud cover
    Test.assertEqualMessage(ForageModel.kind(clearSky, true, 12, true), BEES_OPEN, "clear with no cloud figure");
    var drizzle = new ForageHour(12 * 3600, 20, 10, 2, 50, 31);            // CONDITION_DRIZZLE at 10 %
    Test.assertEqualMessage(ForageModel.kind(drizzle, true, 12, true), BEES_RAIN, "drizzle");
    var bare = new ForageHour(12 * 3600, 20, null, null, null, null);
    Test.assertEqualMessage(ForageModel.kind(bare, true, 12, true), BEES_FLY, "temperature only: flying, never open");
    return true;
}

(:test)
function testOutlook(logger as Logger) as Boolean {
    // The mockup's day: 10:20, flying at 10, open 11 to 14, rain 14 and 15,
    // flying 16 and 17, sunset 18:12
    var rise = 7 * 3600 + 30 * 60;
    var set = 18 * 3600 + 12 * 60;
    var hours = [] as Array<ForageHour>;
    for (var k = 0; k < 13; k++) {
        var hour = 10 + k;
        var celsius = (hour == 10) ? 16 : ((hour < 14) ? 19 : 17);
        var rain = (hour == 14 || hour == 15) ? 60 : 5;
        hours.add(fh(hour, celsius, rain, 2, 20));
    }
    var o = ForageModel.build(10 * 3600 + 20 * 60, null, hours, rise, set, rise + 86400, false);
    Test.assertMessage(o.windowKnown, "the opening hours have weather");
    Test.assertEqualMessage(o.hourStart, 10 * 3600, "current hour");
    var expect = [BEES_FLY, BEES_OPEN, BEES_OPEN, BEES_OPEN, BEES_RAIN, BEES_RAIN,
                  BEES_FLY, BEES_FLY, BEES_NIGHT, BEES_NIGHT, BEES_NIGHT, BEES_NIGHT] as Array<Number>;
    for (var k = 0; k < 12; k++) {
        Test.assertEqualMessage(o.kinds[k], expect[k], "slot " + k);
    }
    Test.assertEqualMessage(ForageModel.windowText(o), "open the hive 11:00-14:00", "window");
    logger.debug(ForageModel.windowText(o));

    // Inside the window
    var inside = ForageModel.build(12 * 3600 + 5 * 60, null, hours, rise, set, rise + 86400, false);
    Test.assertEqualMessage(ForageModel.windowText(inside), "open the hive now, until 14:00", "inside");

    // Evening: the outlook runs past midnight into tomorrow's dark
    var evening = ForageModel.build(17 * 3600, null, hours, rise, set, rise + 86400, false);
    Test.assertEqualMessage(ForageModel.windowText(evening), "", "evening: no opening hours in view, no claim");
    Test.assertEqualMessage(evening.kinds[0], BEES_FLY, "17:00 flying");
    Test.assertEqualMessage(evening.kinds[6], BEES_UNKNOWN, "23:00 is past the forecast");

    // The forecast starts at the next hour: the current conditions fill this one
    var later = [fh(11, 19, 5, 2, 20), fh(12, 19, 5, 2, 20)] as Array<ForageHour>;
    var now = new ForageHour(10 * 3600 + 20 * 60, 16, 5, 2, 20, null);
    var filled = ForageModel.build(10 * 3600 + 20 * 60, now, later, rise, set, rise + 86400, false);
    Test.assertEqualMessage(filled.kinds[0], BEES_FLY, "now from the current conditions");
    Test.assertEqualMessage(filled.now, BEES_FLY, "the verdict is the first cell");
    Test.assertEqualMessage(filled.kinds[1], BEES_OPEN, "11:00 from the forecast");
    Test.assertEqualMessage(ForageModel.windowText(filled), "open the hive 11:00-13:00", "a short forecast still finds a window");

    // Raining now while the forecast's first hour said dry: the cell follows the rain
    var wet = new ForageHour(10 * 3600 + 20 * 60, 19, 80, 2, 90, null);
    var dry = [fh(10, 19, 5, 2, 20), fh(11, 19, 5, 2, 20)] as Array<ForageHour>;
    var raining = ForageModel.build(10 * 3600 + 20 * 60, wet, dry, rise, set, rise + 86400, false);
    Test.assertEqualMessage(raining.kinds[0], BEES_RAIN, "the current conditions win the first cell");
    Test.assertEqualMessage(raining.now, BEES_RAIN, "and the verdict");

    // Two forecast hours and no window among them: too little to say there is none
    var shortDay = ForageModel.build(10 * 3600, null, [fh(10, 11, 0, 2, 90), fh(11, 11, 0, 2, 90)] as Array<ForageHour>,
        rise, set, rise + 86400, false);
    Test.assertEqualMessage(ForageModel.windowText(shortDay), "", "no claim past the forecast");

    var none = ForageModel.build(10 * 3600, null, [] as Array<ForageHour>, rise, set, null, false);
    Test.assertMessage(!none.windowKnown, "no forecast");
    Test.assertEqualMessage(none.now, BEES_UNKNOWN, "no conditions, no verdict");
    Test.assertEqualMessage(ForageModel.windowText(none), "", "no forecast, no window line");
    Test.assertEqualMessage(ForageModel.verdict(BEES_UNKNOWN), "NO WEATHER YET", "verdict without weather");

    // Day and night across midnight
    Test.assertMessage(!ForageModel.isDay(86400 + 6 * 3600, rise, set, rise + 86400), "06:00 tomorrow is dark");
    Test.assertMessage(ForageModel.isDay(86400 + 9 * 3600, rise, set, rise + 86400), "09:00 tomorrow is light");
    Test.assertMessage(ForageModel.isDay(12 * 3600, null, null, null), "no sun times: noon is day");
    Test.assertEqualMessage(ForageModel.clock24(86400 + 7 * 3600 + 5 * 60), "07:05", "clock wraps");
    Test.assertMessage(ForageModel.snow(16) && !ForageModel.snow(3), "light snow is snow, rain is not");
    Test.assertMessage(ForageModel.winter(12) && ForageModel.winter(3) && !ForageModel.winter(4) && !ForageModel.winter(10), "winter is November to March");
    return true;
}

(:test)
function testYear(logger as Logger) as Boolean {
    Test.assertEqualMessage(ForageModel.dayOfYear(1, 1), 1, "1 Jan");
    Test.assertEqualMessage(ForageModel.dayOfYear(10, 31), 304, "31 Oct");
    Test.assertEqualMessage(ForageModel.dayOfYear(12, 31), 365, "31 Dec");
    Test.assertEqualMessage(ForageModel.season(ForageModel.dayOfYear(1, 10)), "WINTER CLUSTER", "January");
    Test.assertEqualMessage(ForageModel.season(ForageModel.dayOfYear(3, 1)), "MAPLE AND WILLOW", "March");
    Test.assertEqualMessage(ForageModel.season(ForageModel.dayOfYear(5, 20)), "MAIN FLOW", "May");
    Test.assertEqualMessage(ForageModel.season(ForageModel.dayOfYear(8, 1)), "SUMMER DEARTH", "August");
    Test.assertEqualMessage(ForageModel.season(ForageModel.dayOfYear(9, 15)), "FALL FLOW", "September");
    Test.assertEqualMessage(ForageModel.season(ForageModel.dayOfYear(10, 31)), "WINTER PREP", "Halloween");
    Test.assertEqualMessage(ForageModel.season(ForageModel.dayOfYear(12, 25)), "WINTER CLUSTER", "December");
    return true;
}

(:test)
function testFaceDrawsBothModes(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var w = settings.screenWidth;
    var h = settings.screenHeight;
    var dc = (Graphics.createBufferedBitmap({:width => w, :height => h}).get() as Graphics.BufferedBitmap).getDc();
    var view = new ForageView();
    view.onLayout(dc);
    view.onUpdate(dc);
    view.onEnterSleep();
    view.onUpdate(dc);
    view.onExitSleep();
    view.onUpdate(dc);
    Test.assertMessage(view.targetAt(w / 2, (h * 0.7).toNumber()) != null, "hold on the comb opens the weather");
    Test.assertMessage(view.targetAt(w / 2, (h * 0.3).toNumber()) == null, "hold on the time does nothing");
    var stats = System.getSystemStats();
    logger.debug("memory: " + stats.usedMemory + " of " + stats.totalMemory + " bytes used");
    return true;
}
