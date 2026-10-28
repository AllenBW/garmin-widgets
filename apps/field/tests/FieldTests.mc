import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

// Draws the Field face into an off-screen bitmap in every ring, footer and
// slot configuration, awake and in always-on mode, so a runtime error in any
// branch fails the test instead of waiting for that mode on the wrist. Also
// prints the memory the app uses against the device's budget.

(:test)
function testFieldDrawsEveryMode(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var w = settings.screenWidth;
    var h = settings.screenHeight;
    var ref = Graphics.createBufferedBitmap({:width => w, :height => h});
    var bitmap = ref.get();
    Test.assertMessage(bitmap instanceof Graphics.BufferedBitmap, "off-screen bitmap allocated");
    var dc = (bitmap as Graphics.BufferedBitmap).getDc();
    Test.assertEqualMessage(dc.getWidth(), w, "bitmap is screen-sized");

    var view = new FieldView();
    view.onLayout(dc);

    var rings = [3, 0, 1, 2];
    var footers = [0, 1, 2];
    for (var r = 0; r < rings.size(); r++) {
        for (var f = 0; f < footers.size(); f++) {
            Application.Properties.setValue("Ring", rings[r]);
            Application.Properties.setValue("Footer", footers[f]);
            view.reloadSettings();
            view.onUpdate(dc);
            view.onEnterSleep();
            view.onUpdate(dc);
            view.onExitSleep();
        }
    }
    for (var kind = Slots.HEART_RATE; kind <= Slots.HIGH_LOW; kind++) {
        Test.assertMessage(Slots.label(kind).length() > 0, "slot " + kind + " has a label");
        Application.Properties.setValue("Slot2", kind);
        view.reloadSettings();
        view.onUpdate(dc);
        logger.debug(Slots.label(kind) + " = " + Slots.value(kind));
    }
    Application.Properties.setValue("Signals", false);
    view.reloadSettings();
    view.onUpdate(dc);

    // Back to the defaults, then check the press targets
    Application.Properties.setValue("Ring", 3);
    Application.Properties.setValue("Footer", 0);
    Application.Properties.setValue("Signals", true);
    Application.Properties.setValue("Slot2", Slots.STEPS);
    view.reloadSettings();
    view.onUpdate(dc);
    var middle = view.slotAt(w / 2, (h * 0.695).toNumber());
    Test.assertMessage(middle != null && middle == Slots.STEPS, "middle slot");
    var left = view.slotAt((w * 0.24).toNumber(), (h * 0.695).toNumber());
    Test.assertMessage(left != null && left == Slots.HEART_RATE, "left slot");
    Test.assertMessage(view.slotAt(w / 2, h / 2) == null, "the time is not a slot");
    Test.assertMessage(view.slotAt(w / 2, (h * 0.9).toNumber()) == null, "the footer is not a slot");

    var stats = System.getSystemStats();
    logger.debug("memory: " + stats.usedMemory + " of " + stats.totalMemory + " bytes used, " + stats.freeMemory + " free");
    return true;
}

(:test)
function testMoonDrawsEveryPhase(logger as Logger) as Boolean {
    var ref = Graphics.createBufferedBitmap({:width => 40, :height => 40});
    var dc = (ref.get() as Graphics.BufferedBitmap).getDc();
    var phases = [0.0, 0.05, 0.25, 0.45, 0.5, 0.55, 0.75, 0.95];
    for (var i = 0; i < phases.size(); i++) {
        Lib.Moon.draw(dc, 20, 20, 10, phases[i], 0x8A8A8A, 0x5A5A5A);
    }
    return true;
}

(:test)
function testWeatherText(logger as Logger) as Boolean {
    Test.assertEqualMessage(WeatherText.describe(Toybox.Weather.CONDITION_CLEAR), "Clear", "clear");
    Test.assertEqualMessage(WeatherText.describe(Toybox.Weather.CONDITION_PARTLY_CLOUDY), "Partly cloudy", "partly cloudy");
    Test.assertEqualMessage(WeatherText.describe(Toybox.Weather.CONDITION_THUNDERSTORMS), "Storm", "storm");
    Test.assertEqualMessage(WeatherText.describe(null), "", "unknown");
    return true;
}
