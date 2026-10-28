import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;
import Toybox.Time;

// Run No Evil tests for the Battery Planner: scripts/test.sh battery [device].
// They write to the app's Storage, so each one clears the log afterwards.

// Seven days of samples every 30 min, draining `perDay` percent a day from
// 100 % six midnights ago, with a two-hour charge back to 100 % on the third
// day. Returns the flat log.
(:test)
class BatteryTestData {
    static function syntheticLog(now as Number, perDay as Number) as Array<Number> {
    var today0 = BatteryModel.dayStart(now);
    var start = today0 - 6 * 86400;
    var chargeStart = start + 3 * 86400 + 10 * 3600;
    var chargeEnd = chargeStart + 2 * 3600;
    var log = [] as Array<Number>;
    var level = 100.0;
    var step = 1800;
    for (var t = start; t <= now; t += step) {
        var charging = (t >= chargeStart && t <= chargeEnd);
        if (charging) {
            level = 100.0;
        } else if (t > start) {
            level -= perDay * step / 86400.0;
        }
        log.add(t);
        log.add(level.toNumber());
        log.add(charging ? 1 : 0);
    }
    return log;
    }
}

(:test)
function testModelPace(logger as Logger) as Boolean {
    var now = Time.now().value();
    var log = BatteryTestData.syntheticLog(now, 12);
    var s = BatteryModel.summarize(log, now, 46);
    logger.debug("pace " + s.pace + " over " + s.paceDays + " days, hours left " + s.hoursLeft);
    var pace = s.pace;
    Test.assertMessage(pace != null, "a week of samples gives a pace");
    Test.assertMessage(pace != null && (pace - 12.0).abs() < 1.5, "pace close to 12 %/day: " + pace);
    Test.assertMessage(s.paceDays >= 5 && s.paceDays <= 7, "five to seven complete days: " + s.paceDays);
    var hours = s.hoursLeft;
    Test.assertMessage(hours != null && (hours - 46 * 24.0 / 12.0).abs() < 12.0, "46 % at 12 %/day is about 92 h: " + hours);
    var by = s.chargeBy;
    Test.assertMessage(by != null, "charge-by date");
    if (by != null) {
        var ahead = by.value() - now;
        // (46 - 10) / 12 = 3 days until the reserve
        Test.assertMessage((ahead - 3 * 86400).abs() < 12 * 3600, "reserve reached in about 3 days: " + ahead);
    }
    for (var i = 0; i < 6; i++) {
        var d = s.drains[i];
        Test.assertMessage(d != null && d > 8.0 && d < 16.0, "day " + i + " drained about 12 %: " + d);
    }
    Test.assertMessage(s.labels[6].length() == 1, "one-letter day labels");
    Test.assertMessage(s.levels.size() >= 2 && s.levels.size() <= BatteryModel.SPARK_POINTS + 1, "sparkline points: " + s.levels.size());
    Test.assertMessage(s.levels[0] == 100, "sparkline starts full");
    Test.assertMessage(BatteryModel.heavyDay(s) == null, "an even week has no heavy day");
    return true;
}

(:test)
function testModelHeavyDay(logger as Logger) as Boolean {
    var now = Time.now().value();
    var log = BatteryTestData.syntheticLog(now, 10);
    // Double the drain two days ago: subtract an extra 10 % spread over that day
    var today0 = BatteryModel.dayStart(now);
    var dayStart = today0 - 2 * 86400;
    var extra = 0;
    for (var k = 0; k < log.size() / 3; k++) {
        var t = log[k * 3];
        if (t > dayStart && t <= dayStart + 86400 && (k % 5) == 0) {
            extra += 1;
        }
        log[k * 3 + 1] = log[k * 3 + 1] - extra;
    }
    var s = BatteryModel.summarize(log, now, 50);
    var heavy = BatteryModel.heavyDay(s);
    logger.debug("drains " + s.drains + " heavy " + heavy);
    Test.assertMessage(heavy != null && heavy == 4, "two days ago is the heavy day: " + heavy);
    var line = BatteryText.paceLine(s, heavy, 2.0);
    logger.debug(line);
    Test.assertMessage(line.find("pace -10%/day") == 0, "pace line starts with the pace: " + line);
    Test.assertMessage(line.find("2h activity") != null, "activity hours are mentioned: " + line);
    return true;
}

(:test)
function testModelNoHistory(logger as Logger) as Boolean {
    var now = Time.now().value();
    var s = BatteryModel.summarize([] as Array<Number>, now, 80);
    Test.assertMessage(s.pace == null && s.hoursLeft == null && s.chargeBy == null, "no pace without samples");
    Test.assertEqualMessage(s.levels.size(), 0, "no sparkline");
    for (var i = 0; i < BatteryModel.DAYS; i++) {
        Test.assertMessage(s.drains[i] == null, "no drain for day " + i);
    }
    var headline = BatteryText.headline(s);
    logger.debug("fallback headline: " + headline + " / " + BatteryText.chargeLine(s));
    Test.assertMessage(headline.length() > 0, "fallback headline");

    // Two hours of samples: a rough pace from the span, no complete day
    var log = [now - 7200, 60, 0, now - 3600, 59, 0, now, 58, 0] as Array<Number>;
    s = BatteryModel.summarize(log, now, 58);
    var pace = s.pace;
    Test.assertMessage(pace == null, "two hours is too little for a pace");
    log = [now - 4 * 3600, 60, 0, now - 2 * 3600, 59, 0, now, 58, 0] as Array<Number>;
    s = BatteryModel.summarize(log, now, 58);
    pace = s.pace;
    Test.assertMessage(pace != null && (pace - 12.0).abs() < 0.5, "four hours give a rough 12 %/day: " + pace);
    Test.assertEqualMessage(s.paceDays, 0, "but no complete day");
    return true;
}

(:test)
function testModelHelpers(logger as Logger) as Boolean {
    var now = Time.now().value();
    var today0 = BatteryModel.dayStart(now);
    Test.assertMessage(today0 <= now && now - today0 < 86400, "midnight is within the last day");
    Test.assertEqualMessage(BatteryModel.daysAgo(today0, today0 + 10), 0, "today");
    Test.assertEqualMessage(BatteryModel.daysAgo(today0, today0 - 1), 1, "just before midnight is yesterday");
    Test.assertEqualMessage(BatteryModel.daysAgo(today0, today0 - 86400), 1, "yesterday's midnight is yesterday");
    Test.assertEqualMessage(BatteryModel.daysAgo(today0, today0 - 86401), 2, "two days");
    Test.assertEqualMessage(BatteryModel.median([3.0, 1.0, 2.0] as Array<Float>), 2.0, "odd median");
    Test.assertEqualMessage(BatteryModel.median([4.0, 1.0, 2.0, 3.0] as Array<Float>), 2.5, "even median");
    Test.assertEqualMessage(BatteryModel.median([7.0] as Array<Float>), 7.0, "single");
    var spark = BatteryModel.sparkline([1, 90, 0, 2, 80, 0, 3, 70, 0, 4, 60, 0] as Array<Number>, 2);
    Test.assertMessage(spark.size() == 2 && spark[0] == 90 && spark[1] == 60, "sparkline keeps first and last: " + spark);
    Test.assertMessage(BatteryText.shortDate(new Time.Moment(1706205240)).length() > 5, "short date has day, number and month");
    Test.assertEqualMessage(BatteryText.duration(148.0), "6d 4h", "duration");
    Test.assertEqualMessage(BatteryText.duration(0.5), "30m", "minutes");
    return true;
}

(:test)
function testLogRingBuffer(logger as Logger) as Boolean {
    BatteryLog.clear();
    Test.assertEqualMessage(BatteryLog.count(), 0, "empty after clear");
    var max = BatteryLog.MAX_SAMPLES;
    for (var i = 0; i < max + 10; i++) {
        BatteryLog.record(1000 + i * 1800, 100 - (i % 100), i % 7 == 0);
    }
    Test.assertEqualMessage(BatteryLog.count(), max, "capped at MAX_SAMPLES");
    var log = BatteryLog.samples();
    Test.assertEqualMessage(log[0], 1000 + 10 * 1800, "the oldest ten were dropped");
    Test.assertEqualMessage(log[log.size() - 3], 1000 + (max + 9) * 1800, "the newest is last");
    BatteryLog.clear();
    return true;
}

(:test)
function testSamplerRecords(logger as Logger) as Boolean {
    BatteryLog.clear();
    var sampler = new BatterySampler();
    sampler.onTemporalEvent();   // Background.exit does nothing outside a background process
    Test.assertEqualMessage(BatteryLog.count(), 1, "one sample logged");
    var log = BatteryLog.samples();
    var now = Time.now().value();
    Test.assertMessage((log[0] - now).abs() < 5, "stamped with the current time");
    Test.assertMessage(log[1] >= 0 && log[1] <= 100, "a percentage: " + log[1]);
    logger.debug("sample " + log);
    BatteryLog.clear();
    return true;
}

(:test)
function testGlanceAndAppDraw(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var w = settings.screenWidth;
    var h = settings.screenHeight;
    var screen = (Graphics.createBufferedBitmap({:width => w, :height => h}).get() as Graphics.BufferedBitmap).getDc();
    var glanceDc = (Graphics.createBufferedBitmap({:width => (w * 0.77).toNumber(), :height => (h * 0.29).toNumber()}).get() as Graphics.BufferedBitmap).getDc();

    // With no history, then with a week of it
    BatteryLog.clear();
    var glance = new BatteryGlance();
    glance.onLayout(glanceDc);
    glance.onShow();
    glance.onUpdate(glanceDc);
    var view = new BatteryView();
    view.onLayout(screen);
    view.onShow();
    view.onUpdate(screen);

    var now = Time.now().value();
    Storage.setValue(BatteryLog.KEY, BatteryTestData.syntheticLog(now, 11) as Array<Storage.ValueType>);
    glance.onShow();
    glance.onUpdate(glanceDc);
    view.onShow();
    view.onUpdate(screen);
    new BatteryDelegate(view).onSelect();
    view.onUpdate(screen);
    Test.assertEqualMessage(BatteryLog.count(), BatteryTestData.syntheticLog(now, 11).size() / 3 + 1, "select logged a sample");

    var stats = System.getSystemStats();
    logger.debug("memory: " + stats.usedMemory + " of " + stats.totalMemory + " bytes used");
    BatteryLog.clear();
    return true;
}
