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
    Test.assertEqualMessage(BatteryText.paceLine(s), "pace -10%/day", "the pace line");
    var line = BatteryText.heavyLine(s, heavy, 2.0);
    logger.debug(line);
    Test.assertMessage(line.find(" -19%") != null, "the heavy day's drain: " + line);
    Test.assertMessage(line.find("2h activity") != null, "activity hours are mentioned: " + line);
    Test.assertEqualMessage(BatteryText.heavyLine(s, null, 0.0), "", "no heavy day, no line");
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
    Test.assertMessage(Lib.Fmt.shortDate(new Time.Moment(1706205240)).length() > 5, "short date has day, number and month");
    Test.assertEqualMessage(Lib.Fmt.duration(148.0), "6d 4h", "duration");
    Test.assertEqualMessage(Lib.Fmt.duration(0.5), "30m", "minutes");
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
function testChargeLearning(logger as Logger) as Boolean {
    var bands = BatteryCharge.blank();
    Test.assertMessage(BatteryCharge.secondsTo(bands, 20.0, 100.0) == null, "nothing learnt, no estimate");
    Test.assertMessage(BatteryCharge.perHour(bands, 20.0) == null, "nor a speed");

    // 20 % to 30 % in ten minutes: 60 s a percent in that band, and every
    // other band borrows it
    bands = BatteryCharge.learn(bands, 20.0, 30.0, 600);
    Test.assertEqualMessage(bands[2], 60.0, "the band charged through");
    Test.assertEqualMessage(bands[1], 0.0, "the band below is untouched");
    Test.assertEqualMessage(bands[3], 0.0, "the band above is untouched");
    Test.assertMessage(BatteryCharge.secondsTo(bands, 25.0, 100.0) == 75 * 60, "75 % at the one known speed");
    Test.assertMessage(BatteryCharge.perHour(bands, 64.0) == 60.0, "60 % an hour");
    Test.assertMessage(BatteryCharge.secondsTo(bands, 100.0, 100.0) == 0, "full already");

    // The top band is slower: the estimate uses each band's own speed, and
    // the bands between take the nearer one's
    bands = BatteryCharge.learn(bands, 90.0, 100.0, 1800);
    Test.assertEqualMessage(bands[9], 180.0, "the last tenth");
    Test.assertMessage(BatteryCharge.secondsTo(bands, 85.0, 100.0) == 5 * 180 + 10 * 180, "85 % borrows from the band above");
    Test.assertMessage(BatteryCharge.secondsTo(bands, 35.0, 40.0) == 5 * 60, "35 % borrows from the band below");

    // A pair across two bands is shared between them, and a band seen again
    // moves part of the way: 5 % of each at 120 s a percent
    bands = BatteryCharge.learn(BatteryCharge.learn(BatteryCharge.blank(), 20.0, 40.0, 1200), 25.0, 35.0, 1200);
    Test.assertEqualMessage(bands[2], 60.0 + 60.0 * BatteryCharge.WEIGHT * 0.5, "half a band moves it a quarter of the way");
    Test.assertEqualMessage(bands[3], bands[2], "both bands alike");

    // Nonsense teaches nothing: a fall, no time, a clock change
    var before = bands[2];
    bands = BatteryCharge.learn(bands, 28.0, 22.0, 600);
    bands = BatteryCharge.learn(bands, 22.0, 28.0, 0);
    bands = BatteryCharge.learn(bands, 22.0, 28.0, 3);
    Test.assertEqualMessage(bands[2], before, "unchanged");
    return true;
}

(:test)
function testChargeObserved(logger as Logger) as Boolean {
    BatteryCharge.clear();
    var t = 1000000;
    BatteryCharge.observe(t, 40.0, true);
    Test.assertMessage(BatteryCharge.secondsTo(BatteryCharge.profile(), 40.0, 100.0) == null, "one reading is not a speed");
    BatteryCharge.observe(t + 30, 40.4, true);     // too small a gain: keep measuring from the first
    BatteryCharge.observe(t + 120, 42.0, true);    // 2 % in 120 s
    var bands = BatteryCharge.profile();
    Test.assertEqualMessage(bands[4], 60.0, "60 s a percent from the first reading to the third");
    BatteryCharge.observe(t + 3600, 80.0, true);   // too long a gap: not measured across
    Test.assertEqualMessage(BatteryCharge.profile()[7], 0.0, "nothing learnt across the gap");
    BatteryCharge.observe(t + 3900, 85.0, true);
    Test.assertEqualMessage(BatteryCharge.profile()[8], 60.0, "measuring again after it");
    BatteryCharge.observe(t + 4000, 85.0, false);  // unplugged
    BatteryCharge.observe(t + 4100, 90.0, true);   // and back: a new start
    Test.assertEqualMessage(BatteryCharge.profile()[8], 60.0, "nothing learnt across the unplugging");

    // On the charger the summary counts down to full
    var s = BatteryModel.summarize([] as Array<Number>, t, 85);
    BatteryModel.plugIn(s, t, 85.0, true, BatteryCharge.profile());
    Test.assertMessage(s.charging && !s.full, "charging");
    Test.assertMessage(s.toFull == 15 * 60, "15 % at 60 s each");
    Test.assertMessage(s.fullAt == t + 15 * 60, "and when");
    Test.assertEqualMessage(BatteryText.headline(s), "15m to full", "the headline");
    Test.assertEqualMessage(BatteryText.title(s, "BATTERY"), "CHARGING 85%", "the title");
    Test.assertEqualMessage(BatteryText.speedLine(s), "+60% an hour", "the speed");
    s = BatteryModel.summarize([] as Array<Number>, t, 100);
    BatteryModel.plugIn(s, t, 100.0, true, BatteryCharge.profile());
    Test.assertMessage(s.full && s.toFull == null, "full");
    Test.assertEqualMessage(BatteryText.headline(s), "Full", "the headline when full");
    s = BatteryModel.summarize([] as Array<Number>, t, 85);
    BatteryModel.plugIn(s, t, 85.0, true, BatteryCharge.blank());
    Test.assertEqualMessage(BatteryText.headline(s), "Charging", "no speed yet");
    BatteryModel.plugIn(s, t, 85.0, false, BatteryCharge.profile());
    Test.assertEqualMessage(BatteryText.title(s, "BATTERY"), "BATTERY", "off the charger");

    BatteryCharge.observe(t + 5000, 90.0, false);  // back to the half-hourly samples
    BatteryCharge.clear();
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

    // On the charger: timing it, counting down, full; with and without a pace
    var logs = [BatteryTestData.syntheticLog(now, 11), [] as Array<Number>];
    var levels = [64.0, 64.0, 100.0];
    var speeds = [BatteryCharge.blank(), BatteryCharge.learn(BatteryCharge.blank(), 0.0, 100.0, 5400), BatteryCharge.blank()];
    for (var i = 0; i < logs.size(); i++) {
        for (var j = 0; j < levels.size(); j++) {
            var s = BatteryModel.summarize(logs[i], now, levels[j].toNumber());
            BatteryModel.plugIn(s, now, levels[j], true, speeds[j]);
            glance.show(s);
            glance.onUpdate(glanceDc);
            view.show(s);
            view.onUpdate(screen);
        }
    }
    view.onHide();

    var stats = System.getSystemStats();
    logger.debug("memory: " + stats.usedMemory + " of " + stats.totalMemory + " bytes used");
    BatteryLog.clear();
    return true;
}
