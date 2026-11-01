import Toybox.Application;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

// Run No Evil tests for Overlap: scripts/test.sh overlap [device]. The Lib
// modules it shares (Slots, Config, Ink) are tested with Vessel.

(:test)
function testOverlapDrawsEveryMode(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var w = settings.screenWidth;
    var h = settings.screenHeight;
    var dc = (Graphics.createBufferedBitmap({:width => w, :height => h}).get() as Graphics.BufferedBitmap).getDc();

    var view = new OverlapView();
    view.onLayout(dc);

    // Whatever the simulator provides
    var started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("awake: " + (System.getTimer() - started) + " ms");

    // Nothing yet; long values with units; labels; a one-digit hour; night
    var empty = [["--", "", null, null, 0], ["--", "", null, null, 0]] as Array<Lib.Slots.Reading>;
    view.setState("00", "00", empty, 0, false, false);
    view.onUpdate(dc);
    var wide = [["5280", "FT", null, null, 0], ["1013", "HPA", null, null, 0]] as Array<Lib.Slots.Reading>;
    view.setState("23", "59", wide, 2, false, false);
    view.onUpdate(dc);
    var odd = [["112", "", 0.45, "GLU", 0], ["Mostly", "", null, "?", 0]] as Array<Lib.Slots.Reading>;
    view.setState("8", "05", odd, 1, true, false);
    view.onUpdate(dc);

    // Standby, then the bedside clock with and without an alarm
    view.setAwake(false);
    started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("standby: " + (System.getTimer() - started) + " ms");
    view.setState("23", "59", odd, 1, true, true);
    view.onUpdate(dc);
    view.setState("3", "10", wide, 0, false, true);
    view.onUpdate(dc);
    view.setAwake(true);
    view.onUpdate(dc);

    var stats = System.getSystemStats();
    logger.debug("memory: " + stats.usedMemory + " of " + stats.totalMemory + " bytes used");
    return true;
}

(:test)
function testOverlapTargets(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var w = settings.screenWidth;
    var h = settings.screenHeight;
    var dc = (Graphics.createBufferedBitmap({:width => w, :height => h}).get() as Graphics.BufferedBitmap).getDc();

    // The readings open their complications, the date the calendar, the time nothing
    var view = new OverlapView();
    view.onLayout(dc);
    var day = [["72", "", 0.32, null, 0], ["8412", "", 0.84, null, 0]] as Array<Lib.Slots.Reading>;
    view.setState("14", "38", day, 0, false, false);
    view.onUpdate(dc);
    Test.assertEqualMessage(view.slotAt((w * 0.25).toNumber(), (h * 0.855).toNumber()) as Number, 1, "the first reading");
    Test.assertEqualMessage(view.slotAt((w * 0.40).toNumber(), (h * 0.855).toNumber()) as Number, 2, "the second reading");
    Test.assertMessage(view.slotAt((w * 0.25).toNumber(), (h * 0.790).toNumber()) == null, "the date is no slot");
    Test.assertMessage(view.slotAt((w * 0.50).toNumber(), (h * 0.40).toNumber()) == null, "the time is no target");
    var id = view.targetAt((w * 0.25).toNumber(), (h * 0.790).toNumber());
    Test.assertMessage(id != null && id.getType() == Complications.COMPLICATION_TYPE_CALENDAR_EVENTS, "the date opens the calendar");
    id = view.targetAt((w * 0.25).toNumber(), (h * 0.855).toNumber());
    Test.assertMessage(id != null && id.getType() == Complications.COMPLICATION_TYPE_SUNRISE, "the sun by default");

    // No targets in standby
    view.setAwake(false);
    view.onUpdate(dc);
    Test.assertMessage(view.slotAt((w * 0.25).toNumber(), (h * 0.855).toNumber()) == null, "no targets in standby");
    return true;
}

(:test)
function testOverlapPhoneSettings(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var w = settings.screenWidth;
    var h = settings.screenHeight;
    var dc = (Graphics.createBufferedBitmap({:width => w, :height => h}).get() as Graphics.BufferedBitmap).getDc();

    // Changed in the phone app last: its reading wins
    Application.Properties.setValue("Reading1", Complications.COMPLICATION_TYPE_STRESS as Number);
    Application.Properties.setValue("Style", 2);
    Lib.Config.changedOnPhone();
    var view = new OverlapView();
    view.onLayout(dc);
    view.onUpdate(dc);
    var id = view.targetAt((w * 0.25).toNumber(), (h * 0.855).toNumber());
    var phone = id != null && id.getType() == Complications.COMPLICATION_TYPE_STRESS;
    var s = Lib.Config.read(3, [Complications.COMPLICATION_TYPE_SUNRISE, Complications.COMPLICATION_TYPE_CURRENT_WEATHER]
                                as Array<Complications.Type>);

    Application.Properties.setValue("Reading1", Complications.COMPLICATION_TYPE_SUNRISE as Number);
    Application.Properties.setValue("Style", 0);
    Application.Storage.deleteValue(Lib.Config.SOURCE);
    Test.assertMessage(phone, "the phone app's first reading");
    Test.assertEqualMessage(s[0], 2, "the phone's typeface");
    Test.assertEqualMessage((s[3][1] as Complications.Id).getType(), Complications.COMPLICATION_TYPE_CURRENT_WEATHER, "the second at its default");
    return true;
}
