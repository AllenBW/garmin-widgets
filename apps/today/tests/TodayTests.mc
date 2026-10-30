import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

// Run No Evil tests for Today: scripts/test.sh today [device].
// Lib.Fmt.clock24, the distance parts and Lib.Moon.name are tested with
// the rest of Lib in apps/field/tests/LibTests.mc; Lib.Daily is tested here.

(:test)
function testTodayDrawsBothModes(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var w = settings.screenWidth;
    var h = settings.screenHeight;
    var dc = (Graphics.createBufferedBitmap({:width => w, :height => h}).get() as Graphics.BufferedBitmap).getDc();

    var view = new TodayView();
    view.onLayout(dc);

    var started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("awake: " + (System.getTimer() - started) + " ms");

    // Press targets: the three columns and the sun line, not the time
    var columnY = (h * 0.695).toNumber();
    var hr = view.targetAt((w * 0.24).toNumber(), columnY);
    Test.assertMessage(hr != null && hr == Complications.COMPLICATION_TYPE_HEART_RATE, "left column is the heart rate");
    var temp = view.targetAt(w / 2, columnY);
    Test.assertMessage(temp != null && temp == Complications.COMPLICATION_TYPE_CURRENT_TEMPERATURE, "middle column is the temperature");
    var dist = view.targetAt((w * 0.76).toNumber(), columnY);
    Test.assertMessage(dist != null && dist == Complications.COMPLICATION_TYPE_STEPS, "right column opens steps");
    Test.assertMessage(view.targetAt(w / 2, h / 2) == null, "the time is not a target");
    var sun = view.targetAt(w / 2, (h * 0.17).toNumber());
    Test.assertMessage(sun == null || sun == Complications.COMPLICATION_TYPE_SUNRISE || sun == Complications.COMPLICATION_TYPE_SUNSET,
        "the sun line opens sunrise or sunset");

    // The alarm mark, which the simulator never shows on its own
    view.drawAlarms(dc, w / 2, (h * 0.085).toNumber(), w, 1, 0x8A8A8A);
    view.drawAlarms(dc, w / 2, (h * 0.085).toNumber(), w, 12, 0x8A8A8A);

    // Always-on
    view.onEnterSleep();
    started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("always-on: " + (System.getTimer() - started) + " ms");
    Test.assertMessage(view.targetAt(w / 2, columnY) == null, "no targets always-on");
    view.onExitSleep();
    view.onUpdate(dc);

    logger.debug("hr " + Lib.Daily.heartRate() + ", outside " + Lib.Daily.temperature() + ", "
        + Lib.Daily.distance() + " " + Lib.Daily.distanceLabel() + ", alarms " + Lib.Daily.alarms() + ", " + Lib.Daily.date());
    var stats = System.getSystemStats();
    logger.debug("memory: " + stats.usedMemory + " of " + stats.totalMemory + " bytes used, " + stats.freeMemory + " free");
    return true;
}

(:test)
function testDailyReadings(logger as Logger) as Boolean {
    var date = Lib.Daily.date();
    Test.assertMessage(date.length() >= 8 && date.length() <= 10, "weekday, month and day: " + date);
    Test.assertEqualMessage(date, date.toUpper(), "date is upper case");
    var label = Lib.Daily.distanceLabel();
    Test.assertMessage(label.equals("MILES") || label.equals("KM"), "distance label follows the unit setting");
    Test.assertMessage(Lib.Daily.alarms() >= 0, "alarm count");
    var hr = Lib.Daily.heartRate();
    var bpm = hr.toNumber();
    Test.assertMessage(hr.equals("--") || (bpm != null && bpm > 0), "heart rate is a number or --: " + hr);
    var distance = Lib.Daily.distance();
    var walked = distance.toFloat();
    Test.assertMessage(distance.equals("--") || (walked != null && walked >= 0.0), "distance is a number or --: " + distance);
    var rain = Lib.Daily.rainChance();
    Test.assertMessage(rain == null || (rain >= 0 && rain <= 100), "chance of rain is a percentage: " + rain);
    var humidity = Lib.Daily.humidity();
    Test.assertMessage(humidity == null || (humidity >= 0 && humidity <= 100), "humidity is a percentage: " + humidity);
    var wind = Lib.Daily.wind();
    Test.assertMessage(wind[1].equals("mph") || wind[1].equals("km/h"), "wind in the distance unit: " + wind[1]);
    Test.assertMessage(wind[0].equals("--") || wind[0].toNumber() != null, "wind is a number or --: " + wind[0]);
    var steps = Lib.Daily.steps();
    Test.assertMessage(steps == null || steps >= 0, "steps: " + steps);
    var battery = Lib.Daily.watchBattery();
    Test.assertMessage(battery >= 0 && battery <= 100, "the watch's battery: " + battery);
    logger.debug("rain " + rain + "%, humidity " + humidity + "%, wind " + wind + ", steps " + steps + ", battery " + battery + "%");
    return true;
}
