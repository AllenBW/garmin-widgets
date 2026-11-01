import Toybox.Application;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Test;

// Run No Evil tests for Inscription: scripts/test.sh inscription [device].
// The Lib modules it shares (Slots, Config, Ink) are tested in Vessel's.

(:test)
function testInscriptionDrawsEveryMode(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var w = settings.screenWidth;
    var h = settings.screenHeight;
    var dc = (Graphics.createBufferedBitmap({:width => w, :height => h}).get() as Graphics.BufferedBitmap).getDc();

    var view = new InscriptionView();
    view.onLayout(dc);

    // Whatever the simulator provides
    var started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("awake: " + (System.getTimer() - started) + " ms");

    // Nothing yet; long readings with labels; a one-digit hour; night
    var empty = [["--", "", null, null, 0], ["--", "", null, null, 0], ["--", "", null, null, 0],
                 ["--", "", null, null, 0], ["--", "", null, null, 0]] as Array<Lib.Slots.Reading>;
    view.setState("00", "00", empty, 0, false, false);
    view.onUpdate(dc);
    var odd = [["Mostly", "", null, "?", 0], ["1013", "HPA", null, null, 0], ["112", "", 0.45, "GLU", 0],
               ["18888", "", 1.0, null, 0], ["7:12", "", 0.3, null, 1]] as Array<Lib.Slots.Reading>;
    view.setState("8", "05", odd, 2, true, false);
    view.onUpdate(dc);
    view.setState("23", "59", day(), 1, false, false);
    view.onUpdate(dc);
    // Long words along the bottom step down until they fit (Lib.Slots.word's long and short forms)
    var long = [["46°", "", 0.55, null, 0], ["100", "%", 1.0, null, 0], ["18", "H", null, null, 0],
                ["1250", "", 0.9, null, 0], ["100", "%", 1.0, null, 0]] as Array<Lib.Slots.Reading>;
    view.setState("10", "10", long, 0, false, false);
    view.onUpdate(dc);

    // Standby, then the bedside clock with and without an alarm
    view.setAwake(false);
    started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("standby: " + (System.getTimer() - started) + " ms");
    Test.assertMessage(view.slotAt((w * 0.075).toNumber(), (h * 0.5).toNumber()) == null, "no targets in standby");
    view.setState("23", "59", odd, 1, true, true);
    view.onUpdate(dc);
    view.setState("3", "10", day(), 0, false, true);
    view.onUpdate(dc);
    view.setAwake(true);
    view.onUpdate(dc);

    var stats = System.getSystemStats();
    logger.debug("memory: " + stats.usedMemory + " of " + stats.totalMemory + " bytes used");
    return true;
}

(:test)
function testInscriptionTargets(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var w = settings.screenWidth;
    var h = settings.screenHeight;
    var dc = (Graphics.createBufferedBitmap({:width => w, :height => h}).get() as Graphics.BufferedBitmap).getDc();
    var view = new InscriptionView();
    view.onLayout(dc);
    view.setState("14", "38", day(), 1, false, false);
    view.onUpdate(dc);

    Test.assertEqualMessage(view.slotAt((w * 0.075).toNumber(), (h * 0.5).toNumber()) as Number, 1, "nine o'clock");
    Test.assertEqualMessage(view.slotAt((w * 0.925).toNumber(), (h * 0.5).toNumber()) as Number, 2, "three o'clock");
    Test.assertEqualMessage(view.slotAt((w * 0.5).toNumber(), (h * 0.925).toNumber()) as Number, 4, "the bottom's middle");
    Test.assertMessage(view.slotAt((w * 0.5).toNumber(), (h * 0.5).toNumber()) == null, "the time is no target");
    var id = view.targetAt((w * 0.5).toNumber(), (h * 0.075).toNumber());
    Test.assertMessage(id != null && id.getType() == Complications.COMPLICATION_TYPE_CALENDAR_EVENTS, "the date opens the calendar");
    id = view.targetAt((w * 0.075).toNumber(), (h * 0.5).toNumber());
    Test.assertMessage(id != null && id.getType() == Complications.COMPLICATION_TYPE_CURRENT_WEATHER, "the weather by default");
    id = view.targetAt((w * 0.925).toNumber(), (h * 0.5).toNumber());
    Test.assertMessage(id != null && id.getType() == Complications.COMPLICATION_TYPE_SEA_LEVEL_PRESSURE, "the barometer by default");

    // Along the bottom, left to right: slots 3, 4, 5 in that order
    var seen = [] as Array<Number>;
    for (var deg = 240; deg >= 120; deg -= 2) {
        var a = Math.toRadians(deg);
        var slot = view.slotAt((w / 2 + w * 0.425 * Math.sin(a)).toNumber(), (h / 2 - w * 0.425 * Math.cos(a)).toNumber());
        if (slot != null && (seen.size() == 0 || seen[seen.size() - 1] != slot)) {
            seen.add(slot);
        }
    }
    logger.debug("along the bottom: " + seen);
    Test.assertMessage(seen.size() == 3 && seen[0] == 3 && seen[1] == 4 && seen[2] == 5, "the bottom readings in order");
    return true;
}

(:test)
function testInscriptionPhoneSettings(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var w = settings.screenWidth;
    var h = settings.screenHeight;
    var dc = (Graphics.createBufferedBitmap({:width => w, :height => h}).get() as Graphics.BufferedBitmap).getDc();

    // Changed in the phone app last: its reading at nine o'clock wins; the
    // typefaces are 0 Pridi (the legend in Pridi too) to 3 Rajdhani
    Application.Properties.setValue("Reading1", Complications.COMPLICATION_TYPE_STRESS as Number);
    Application.Properties.setValue("Style", 3);
    Lib.Config.changedOnPhone();
    var s = Lib.Config.read(4, [Complications.COMPLICATION_TYPE_CURRENT_WEATHER] as Array<Complications.Type>);
    var view = new InscriptionView();
    view.onLayout(dc);
    view.onUpdate(dc);
    Application.Properties.setValue("Style", 0);
    var pridi = new InscriptionView();
    pridi.onLayout(dc);
    pridi.onUpdate(dc);
    var id = view.targetAt((w * 0.075).toNumber(), (h * 0.5).toNumber());
    var phone = id != null && id.getType() == Complications.COMPLICATION_TYPE_STRESS;
    id = view.targetAt((w * 0.925).toNumber(), (h * 0.5).toNumber());
    var kept = id != null && id.getType() == Complications.COMPLICATION_TYPE_SEA_LEVEL_PRESSURE;

    Application.Properties.setValue("Reading1", Complications.COMPLICATION_TYPE_CURRENT_WEATHER as Number);
    Application.Properties.setValue("Style", 0);
    Application.Storage.deleteValue(Lib.Config.SOURCE);
    Test.assertEqualMessage(s[0], 3, "Rajdhani from the phone");
    Test.assertMessage(phone, "the phone app's reading at nine o'clock");
    Test.assertMessage(kept, "the other slots at their defaults");
    return true;
}

function day() as Array<Lib.Slots.Reading> {
    return [["46°", "", 0.55, null, 0], ["81", "%", 0.81, null, 0], ["72", "", 0.32, null, 0],
            ["8412", "", 0.84, null, 0], ["64", "", 0.64, null, 0]] as Array<Lib.Slots.Reading>;
}

