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

    // Whatever the simulator provides: a start's first frame the time alone,
    // the legend from the next
    var started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("awake, the first frame: " + (System.getTimer() - started) + " ms");
    Test.assertMessage(view.timeAt(w / 2, h / 2), "the first frame draws the time");
    Test.assertMessage(view.slotAt((w * 0.075).toNumber(), (h * 0.5).toNumber()) == null, "and no legend yet");
    started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("awake: " + (System.getTimer() - started) + " ms");
    started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("awake again, the widths known: " + (System.getTimer() - started) + " ms");

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
    view.onUpdate(dc);                            // the time alone
    view.onUpdate(dc);

    Test.assertEqualMessage(view.slotAt((w * 0.075).toNumber(), (h * 0.5).toNumber()) as Number, 1, "nine o'clock");
    Test.assertEqualMessage(view.slotAt((w * 0.925).toNumber(), (h * 0.5).toNumber()) as Number, 2, "three o'clock");
    Test.assertEqualMessage(view.slotAt((w * 0.5).toNumber(), (h * 0.925).toNumber()) as Number, 4, "the bottom's middle");
    Test.assertMessage(view.slotAt((w * 0.5).toNumber(), (h * 0.5).toNumber()) == null, "the time is no target");
    Test.assertMessage(view.timeAt((w * 0.5).toNumber(), (h * 0.5).toNumber()), "a hold on the time: the looks");
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
    view.onUpdate(dc);
    Application.Properties.setValue("Style", 0);
    var pridi = new InscriptionView();
    pridi.onLayout(dc);
    pridi.onUpdate(dc);
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


// Every look draws, awake and in standby, the look's name over the date
(:test)
function testInscriptionLooks(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var dc = (Graphics.createBufferedBitmap({:width => settings.screenWidth, :height => settings.screenHeight}).get()
              as Graphics.BufferedBitmap).getDc();
    var view = new InscriptionView();
    view.onLayout(dc);
    Application.Storage.setValue(Lib.Look.KEY, Lib.Look.LOW);
    for (var m = 0; m < Lib.Look.MODES; m++) {
        Test.assertEqualMessage(Lib.Look.next(), Lib.Look.ORDER[(Lib.Look.ORDER.indexOf(Lib.Look.LOW) + m + 1) % Lib.Look.MODES], "the next look");
        view.reloadSettings();
        view.onUpdate(dc);
        view.setAwake(false);
        view.onUpdate(dc);
        view.setAwake(true);
    }
    Application.Storage.deleteValue(Lib.Look.KEY);
    return true;
}

// Lib.WatchMenu: the settings on the watch are the phone app's list, the
// look first, and a choice there writes the same property, winning over the
// editor; the bedside clock a switch
(:test)
function testInscriptionWatchMenu(logger as Logger) as Boolean {
    var entries = Choices.entries();
    Test.assertEqualMessage(entries.size(), 5 + 5, "the look, the typeface, two colours, 5 readings and the bedside clock");
    Test.assertMessage(entries[0][1] == null, "the look first");
    for (var i = 0; i < entries.size(); i++) {
        Test.assertEqualMessage(entries[i][2].size(), entries[i][3].size(), "a label for every choice");
    }
    Test.assertEqualMessage(entries[2][3].size(), Lib.Config.ACCENTS.size(), "every accent offered");
    Test.assertEqualMessage(entries[3][3].size(), Lib.Config.DATA.size(), "every data colour");
    var look = Application.Storage.getValue(Lib.Look.KEY);
    var source = Application.Storage.getValue(Lib.Config.SOURCE);
    Lib.WatchMenu.choose(entries[2], 5);
    Test.assertEqualMessage(Lib.WatchMenu.current(entries[2]), 5, "the choice is where the setting stands");
    Test.assertEqualMessage(Lib.WatchMenu.label(entries[2]), entries[2][2][5], "and its label shows");
    Test.assertMessage(Lib.Config.PHONE.equals(Application.Storage.getValue(Lib.Config.SOURCE)), "a choice on the watch wins over the editor");
    Test.assertEqualMessage(Lib.Config.read(1, [] as Array<Complications.Type>)[1], Lib.Config.lift(Lib.Config.ACCENTS[5]), "and is the accent drawn");
    var reading = entries[4];
    Lib.WatchMenu.choose(reading, 4);
    Test.assertEqualMessage(Application.Properties.getValue("Reading1"), reading[3][4], "a reading written as the phone writes it");
    var bedside = entries[entries.size() - 1];
    Lib.WatchMenu.choose(bedside, 1);
    Test.assertEqualMessage(Application.Properties.getValue("Bedside"), false, "the switch off");
    Test.assertEqualMessage(Lib.WatchMenu.label(bedside), bedside[2][1], "and shown off");
    Lib.WatchMenu.choose(bedside, 0);
    Lib.WatchMenu.choose(entries[0], 4);              // the fifth look in the order: low light
    Test.assertEqualMessage(Lib.Look.mode(), Lib.Look.LOW, "the look chosen as a hold chooses it");
    Application.Properties.setValue("Accent", 0);
    Application.Properties.setValue("Reading1", 8);
    if (look instanceof Number) {
        Application.Storage.setValue(Lib.Look.KEY, look);
    } else {
        Application.Storage.deleteValue(Lib.Look.KEY);
    }
    if (source instanceof String) {
        Application.Storage.setValue(Lib.Config.SOURCE, source);
    } else {
        Application.Storage.deleteValue(Lib.Config.SOURCE);
    }
    return true;
}
