import Toybox.Application;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

// Run No Evil tests for Rings: scripts/test.sh rings [device].

(:test)
function testGoals(logger as Logger) as Boolean {
    Test.assertEqualMessage(Goals.fraction(null, 10000), 0.0, "no value");
    Test.assertEqualMessage(Goals.fraction(2500, null), 0.0, "no goal");
    Test.assertEqualMessage(Goals.fraction(2500, 0), 0.0, "zero goal");
    Test.assertEqualMessage(Goals.fraction(2500, 10000), 0.25, "a quarter");
    Test.assertEqualMessage(Goals.fraction(12000, 10000), 1.0, "capped at the goal");
    var steps = Goals.steps();
    logger.debug("steps " + steps[0] + " of " + steps[1] + ", floors " + Goals.floors()[0] + " of " + Goals.floors()[1] + ", body " + Goals.bodyBattery());
    var body = Goals.bodyBattery();
    Test.assertMessage(body == null || (body >= 0 && body <= 100), "Body Battery in range");
    return true;
}

(:test)
function testRingsDrawsEveryState(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var w = settings.screenWidth;
    var h = settings.screenHeight;
    var dc = (Graphics.createBufferedBitmap({:width => w, :height => h}).get() as Graphics.BufferedBitmap).getDc();

    var view = new RingsView();
    view.onLayout(dc);

    // Whatever the simulator provides
    var started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("awake: " + (System.getTimer() - started) + " ms");

    // Nothing yet, part way, the goals met (the star), a segment goal, no goals
    view.setGoals(null, null, null, null, null);
    view.onUpdate(dc);
    view.setGoals(2477, 10000, 3, 10, 61);
    view.onUpdate(dc);
    view.setGoals(12000, 10000, 12, 10, 100);
    view.onUpdate(dc);
    view.setGoals(500, 10000, 1, 1, 0);
    view.onUpdate(dc);
    view.setGoals(500, 10000, 5, 60, 50);   // too many floors for segments: a plain ring
    view.onUpdate(dc);

    // Every theme draws
    for (var theme = 0; theme < 3; theme++) {
        Application.Properties.setValue("Theme", theme);
        view.reloadSettings();
        view.onUpdate(dc);
    }
    Application.Properties.setValue("Theme", 0);
    view.reloadSettings();
    view.onUpdate(dc);

    // The rings: lower ends line up left of six o'clock, upper ends stagger
    Test.assertMessage(view.lowerAngle(0) > 180.0 && view.lowerAngle(0) < view.lowerAngle(1) && view.lowerAngle(1) < view.lowerAngle(2), "lower ends just left of six");
    Test.assertMessage(view.span(0) > view.span(1) && view.span(1) > view.span(2), "the outer ring reaches furthest");

    // Press targets: the rings by radius and angle, the rows on the right
    var cx = w / 2;
    var cy = h / 2;
    var outer = view.targetAt(cx - (w * 0.455).toNumber(), cy);
    Test.assertMessage(outer != null && outer == Complications.COMPLICATION_TYPE_STEPS, "outer ring is the steps");
    var middle = view.targetAt(cx - (w * 0.375).toNumber(), cy);
    Test.assertMessage(middle != null && middle == Complications.COMPLICATION_TYPE_FLOORS_CLIMBED, "middle ring is the floors");
    var inner = view.targetAt(cx - (w * 0.295).toNumber(), cy);
    Test.assertMessage(inner != null && inner == Complications.COMPLICATION_TYPE_BODY_BATTERY, "inner ring is Body Battery");
    Test.assertMessage(view.targetAt(cx + (w * 0.455).toNumber(), cy) == null, "the rings are open on the right");
    var hr = view.targetAt((w * 0.74).toNumber(), (h * 0.285).toNumber());
    Test.assertMessage(hr != null && hr == Complications.COMPLICATION_TYPE_HEART_RATE, "the heart rate row");
    var temp = view.targetAt((w * 0.74).toNumber(), (h * 0.725).toNumber());
    Test.assertMessage(temp != null && temp == Complications.COMPLICATION_TYPE_CURRENT_TEMPERATURE, "the temperature row");
    Test.assertMessage(view.targetAt((w * 0.62).toNumber(), (h * 0.5).toNumber()) == null, "the time is not a target");

    view.onEnterSleep();
    started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("always-on: " + (System.getTimer() - started) + " ms");
    Test.assertMessage(view.targetAt(cx - (w * 0.455).toNumber(), cy) == null, "no targets always-on");
    view.onExitSleep();
    view.onUpdate(dc);

    var stats = System.getSystemStats();
    logger.debug("memory: " + stats.usedMemory + " of " + stats.totalMemory + " bytes used");
    return true;
}

(:test)
function testThemes(logger as Logger) as Boolean {
    for (var theme = 0; theme < 3; theme++) {
        Test.assertEqualMessage(Themes.colors(theme).size(), 4, "three rings and the time");
    }
    Test.assertEqualMessage(Themes.colors(99)[0], Themes.colors(Themes.SUNSET)[0], "an unknown theme falls back to Sunset");
    Test.assertEqualMessage(Themes.shade(0xFFFFFF, 0.5), 0x7F7F7F, "half brightness");
    Test.assertEqualMessage(Themes.shade(0xFF8A50, 0.0), 0, "no brightness is black");
    return true;
}
