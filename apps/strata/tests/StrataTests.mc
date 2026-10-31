import Toybox.Application;
import Toybox.Application.WatchFaceConfig;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;
import Toybox.WatchUi;

// Run No Evil tests for Strata: scripts/test.sh strata [device].

(:test)
function testLayers(logger as Logger) as Boolean {
    var started = System.getTimer();
    var layers = new Layers(454, 454);
    logger.debug("scale: " + (System.getTimer() - started) + " ms, " + layers.lines.size() + " layers, " + layers.pebbles.size() + " pebbles");
    Test.assertEqualMessage(layers.step, 8.0, "eight pixels between samples at 454");
    Test.assertMessage(layers.lines.size() >= 30 && layers.lines.size() <= 120, "a dense field of layers, some in pieces: " + layers.lines.size());
    var r2 = 224.5 * 224.5;   // the generator's disc, and the samples' rounding to tenths
    var accents = 0;
    var top = 999.0;
    var bottom = 0.0;
    for (var k = 0; k < layers.lines.size(); k++) {
        var ys = layers.lines[k];
        Test.assertMessage(ys.size() >= 2, "a layer has at least one segment");
        if (layers.isAccent(k)) {
            accents++;
        }
        for (var i = 0; i < ys.size(); i++) {
            var x = layers.starts[k] + i * layers.step;
            var y = ys[i];
            if (y < top) {
                top = y;
            }
            if (y > bottom) {
                bottom = y;
            }
            if (i > 0 && i < ys.size() - 1) {
                // Only a layer's two end samples lie past the rim, so it reaches the edge
                Test.assertMessage((x - 227.0) * (x - 227.0) + (y - 227.0) * (y - 227.0) < r2, "every inner sample is inside the disc: line " + k + " " + x + "," + y);
            }
        }
    }
    Test.assertMessage(top < 40.0 && bottom > 414.0, "the layers cover the whole face: " + top + " to " + bottom);
    Test.assertMessage(accents >= 5 && accents * 3 <= layers.lines.size(), "about every fourth layer is the accent: " + accents);
    Test.assertMessage(layers.aodLines.size() >= 5 && layers.aodLines.size() <= 15, "always-on has a few layers of its own: " + layers.aodLines.size());
    var aodSamples = 0;
    for (var k = 0; k < layers.aodLines.size(); k++) {
        aodSamples += layers.aodLines[k].size();
    }
    Test.assertMessage(aodSamples < 800, "always-on draws few enough segments for one frame: " + aodSamples);
    Test.assertMessage(layers.pebbles.size() > 0 && layers.pebbles.size() <= 48, "some pebbles, at most 48");
    for (var i = 0; i < layers.pebbles.size(); i++) {
        var p = layers.pebbles[i];
        Test.assertMessage(p[1] < 454 * 0.36 || p[1] > 454 * 0.65, "no pebble where the time is, nor in a row under it: " + p);
        var reach = 227.0 - p[2];
        Test.assertMessage((p[0] - 227.0) * (p[0] - 227.0) + (p[1] - 227.0) * (p[1] - 227.0) < reach * reach, "pebble inside the disc: " + p);
        Test.assertMessage(p[2] >= p[3] && p[3] >= 1, "a pebble is a flat ellipse: " + p);
    }

    // The 416 px screen gets the same field, scaled
    var small = new Layers(416, 416);
    Test.assertEqualMessage(small.lines.size(), layers.lines.size(), "same layers at 416");
    Test.assertMessage((small.lines[3][2] - layers.lines[3][2] * 416.0 / 454.0).abs() < 0.01, "scaled to 416");
    return true;
}

(:test)
function testPalette(logger as Logger) as Boolean {
    Test.assertEqualMessage(Palette.temperature(null), Palette.GRAY, "no temperature: grey");
    Test.assertEqualMessage(Palette.temperature(-10.0), 0x8FB8C8, "well below freezing: glacial slate");
    Test.assertEqualMessage(Palette.temperature(40.0), 0xB84A3A, "104 F: red clay");
    Test.assertEqualMessage(Palette.temperature(22.22), 0xD2A24C, "72 F: ochre");
    Test.assertEqualMessage(Palette.blend(0x000000, 0xFFFFFF, 0.5), 0x808080, "half way between black and white");
    Test.assertEqualMessage(Palette.blend(0xFF0000, 0x0000FF, 0.0), 0xFF0000, "t = 0 is the first colour");
    Test.assertEqualMessage(Palette.scale(0xC8703E, 0.5), 0x64381F, "half as bright");
    // Hotter air, earthier accent: the green channel never rises from 60 F to 100 F
    var lastGreen = 999;
    for (var f = 60.0; f <= 100.0; f += 2.5) {
        var color = Palette.temperature((f - 32.0) * 5.0 / 9.0);
        var green = (color >> 8) & 0xFF;
        Test.assertMessage(green <= lastGreen, "green falls with the heat at " + f + " F: " + green + " after " + lastGreen);
        lastGreen = green;
    }
    return true;
}

(:test)
function testPaletteChoices(logger as Logger) as Boolean {
    Test.assertEqualMessage(Palette.strata(0, false), 0x5C4A2E, "Soil by day: brown");
    Test.assertEqualMessage(Palette.strata(0, true), 0x3E4556, "Soil by night: graphite");
    Test.assertEqualMessage(Palette.strata(9, false), Palette.strata(0, false), "an unknown strata setting falls back to Soil");
    for (var i = 0; i < Palette.STRATA_DAY.size(); i++) {
        // About as bright as each other, and dim enough to sit behind the readings
        var c = Palette.STRATA_DAY[i];
        var sum = ((c >> 16) & 0xFF) + ((c >> 8) & 0xFF) + (c & 0xFF);
        Test.assertMessage(sum >= 170 && sum <= 360, "strata " + i + " is a dim earth tone: " + sum);
    }
    var earth = Palette.strata(0, false);
    var temp = Palette.temperature(7.8);
    Test.assertEqualMessage(Palette.layerAccent(Palette.ACCENT_TEMPERATURE, 7.8, earth, false), Palette.scale(temp, 0.65), "the temperature's layers at 65 %");
    var nightEarth = Palette.strata(0, true);
    Test.assertEqualMessage(Palette.layerAccent(Palette.ACCENT_TEMPERATURE, 7.8, nightEarth, true), Palette.blend(nightEarth, Palette.MOONLIGHT, 0.5), "at night the temperature's layers go moonlit");
    Test.assertEqualMessage(Palette.layerAccent(2, 7.8, earth, false), Palette.scale(0xE0B050, 0.8), "Ochre at 80 % by day");
    Test.assertEqualMessage(Palette.layerAccent(2, 7.8, earth, true), Palette.scale(0xE0B050, 0.7), "and dimmer at night");
    var tone = Palette.layerAccent(Palette.ACCENT_TONE, 7.8, earth, false);
    Test.assertMessage(tone != earth && ((tone >> 16) & 0xFF) > ((earth >> 16) & 0xFF), "tone on tone is a paler strata: " + tone);
    Test.assertEqualMessage(Palette.time(0, Palette.ACCENT_TEMPERATURE, 7.8, earth), 0xF2ECE2, "Bone");
    Test.assertEqualMessage(Palette.time(Palette.TIME_ACCENT, Palette.ACCENT_TEMPERATURE, 7.8, earth), temp, "the time in the temperature's colour");
    Test.assertEqualMessage(Palette.time(Palette.TIME_ACCENT, 4, 7.8, earth), 0xC8703E, "the time in Ember");
    Test.assertEqualMessage(Palette.time(2, 0, 7.8, earth), 0xD9B98C, "Sandstone");
    return true;
}

(:test)
function testReadings(logger as Logger) as Boolean {
    var seen = "";
    for (var kind = 0; kind < Readings.COUNT; kind++) {
        var reading = Readings.read(kind, 7.8);
        Test.assertMessage(reading[0].length() > 0 && reading[0].length() <= 5, "kind " + kind + " fits its column: " + reading[0]);
        Test.assertMessage(reading[1].length() <= 4, "kind " + kind + " has a short unit: " + reading[1]);
        Readings.complication(kind);
        seen += kind + "=" + reading[0] + reading[1] + " ";
    }
    logger.debug(seen);
    Test.assertEqualMessage(Readings.read(Readings.TEMPERATURE, 7.8)[0], "46", "7.8 C is 46 F");
    Test.assertEqualMessage(Readings.read(Readings.TEMPERATURE, null)[0], "--", "no weather yet");
    Test.assertEqualMessage(Readings.kind(null, 1), Readings.RAIN, "unset: the slot's default");
    Test.assertEqualMessage(Readings.kind(42, 3), Readings.DISTANCE, "out of range: the slot's default");
    Test.assertEqualMessage(Readings.kind(Readings.WIND, 0), Readings.WIND, "a kind it knows");
    Test.assertEqualMessage(Readings.complication(Readings.BODY_BATTERY), Complications.COMPLICATION_TYPE_BODY_BATTERY, "Body Battery opens its widget");
    return true;
}

(:test)
function testEditorChoices(logger as Logger) as Boolean {
    // The fēnix 8 watch face editor's choices (resources/configs/watchface.xml)
    Test.assertMessage(Readings.fromComplication(Complications.COMPLICATION_TYPE_CURRENT_WEATHER) == Readings.RAIN, "weather shows the chance of rain");
    Test.assertMessage(Readings.fromComplication(Complications.COMPLICATION_TYPE_STEPS) == Readings.DISTANCE, "steps show the miles walked");
    Test.assertMessage(Readings.fromComplication(Complications.COMPLICATION_TYPE_ALTITUDE) == Readings.ELEVATION, "altitude");
    Test.assertMessage(Readings.fromComplication(Complications.COMPLICATION_TYPE_STRESS) == null, "a complication Strata doesn't offer");
    for (var i = 0; i < Palette.STRATA_DAY.size(); i++) {
        Test.assertEqualMessage(Palette.strataFromColor(Palette.STRATA_DAY[i]), i, "accent colour " + i + " picks its strata");
    }
    Test.assertEqualMessage(Palette.strataFromColor(0x123456), 0, "any other colour: Soil");

    // A tap on a reading picks its slot
    var view = new StrataView();
    var w = System.getDeviceSettings().screenWidth;
    var h = System.getDeviceSettings().screenHeight;
    Test.assertMessage(view.slotAt((w * 0.186).toNumber(), (h * 0.70).toNumber()) == 1, "the first reading");
    Test.assertMessage(view.slotAt((w * 0.801).toNumber(), (h * 0.70).toNumber()) == 4, "the fourth reading");
    Test.assertMessage(view.slotAt(w / 2, h / 2) == null, "the time is no slot");
    var config = WatchFaceConfig.getSettings(null);
    logger.debug("the simulator's editor config: " + ((config != null) ? "style " + config.styleId : "none"));
    return true;
}

(:test)
function testHeartRateTrace(logger as Logger) as Boolean {
    var trace = Lib.Daily.heartRateTrace(40, 6 * 3600);
    Test.assertEqualMessage(trace.size(), 40, "one value per bin");
    var filled = 0;
    for (var b = 0; b < trace.size(); b++) {
        var v = trace[b];
        if (v != null) {
            filled++;
            Test.assertMessage(v >= 20 && v <= 250, "a plausible heart rate: " + v);
        }
    }
    logger.debug("trace: " + filled + " of 40 bins filled, newest " + trace[39]);
    return true;
}

(:test)
function testStrataDrawsBothModes(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var w = settings.screenWidth;
    var h = settings.screenHeight;
    var dc = (Graphics.createBufferedBitmap({:width => w, :height => h}).get() as Graphics.BufferedBitmap).getDc();

    var view = new StrataView();
    var started = System.getTimer();
    view.onLayout(dc);
    logger.debug("layout: " + (System.getTimer() - started) + " ms");

    // The first frames fill the layers in; then the face is one blit and the readings
    for (var f = 0; f < 8; f++) {
        started = System.getTimer();
        view.onUpdate(dc);
        logger.debug("awake frame " + f + ": " + (System.getTimer() - started) + " ms");
    }
    Test.assertMessage(view.fieldReady(), "the layers are in after a few frames");
    logger.debug(view.pebblesShown() + " stones shown");

    var hr = view.targetAt((w * 0.57).toNumber(), (h * 0.69).toNumber());
    Test.assertMessage(hr != null && hr == Complications.COMPLICATION_TYPE_HEART_RATE, "the heart and its number open the heart rate");
    var temp = view.targetAt((w * 0.16).toNumber(), (h * 0.73).toNumber());
    Test.assertMessage(temp != null && temp == Complications.COMPLICATION_TYPE_CURRENT_TEMPERATURE, "the temperature opens the weather");
    var dist = view.targetAt((w * 0.775).toNumber(), (h * 0.66).toNumber());
    var rain = view.targetAt((w * 0.365).toNumber(), (h * 0.69).toNumber());
    Test.assertMessage(rain != null && rain == Complications.COMPLICATION_TYPE_CURRENT_WEATHER, "the chance of rain opens the weather");
    Test.assertMessage(dist != null && dist == Complications.COMPLICATION_TYPE_STEPS, "the footprints open steps");
    var date = view.targetAt(w / 2, (h * 0.252).toNumber());
    Test.assertMessage(date != null && date == Complications.COMPLICATION_TYPE_CALENDAR_EVENTS, "the date opens the calendar");
    Test.assertMessage(view.targetAt(w / 2, (h * 0.47).toNumber()) == null, "the time is not a target");

    // The sun line with alarms set, both ways round
    view.drawSunLine(dc, w / 2, (h * 0.15).toNumber(), w, true, "07:12", 0xE9B04F, 0xE6DCCB, 2);
    view.drawSunLine(dc, w / 2, (h * 0.15).toNumber(), w, false, "19:22", 0xE8854A, 0xE6DCCB, 1);

    // Every strata colour, every accent and every time colour, with the switches off
    var configs = [[1, 1, 1, false, false], [2, 2, 2, true, true], [3, 3, 0, true, false], [4, 4, 1, false, true], [0, 0, 0, true, true]] as Array<Array>;
    for (var c = 0; c < configs.size(); c++) {
        var config = configs[c];
        Application.Properties.setValue("Strata", config[0] as Number);
        Application.Properties.setValue("Accent", config[1] as Number);
        Application.Properties.setValue("TimeColor", config[2] as Number);
        Application.Properties.setValue("DayNight", config[3] as Boolean);
        Application.Properties.setValue("Stones", config[4] as Boolean);
        Application.Properties.setValue("TimeStyle", c % 2);
        // Every reading kind in some slot, two configs over
        for (var n = 0; n < 4; n++) {
            Application.Properties.setValue("Slot" + (n + 1), (c * 4 + n) % Readings.COUNT);
        }
        view.reloadSettings();
        for (var f = 0; f < 7; f++) {
            view.onUpdate(dc);
        }
        Test.assertMessage(view.fieldReady(), "the layers are redrawn in the new colours: " + config);
    }

    for (var n = 0; n < 4; n++) {
        Application.Properties.setValue("Slot" + (n + 1), Readings.DEFAULTS[n]);
    }
    Application.Properties.setValue("TimeStyle", 0);
    view.reloadSettings();

    view.onEnterSleep();
    started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("always-on: " + (System.getTimer() - started) + " ms");
    Test.assertMessage(view.targetAt(w / 2, (h * 0.70).toNumber()) == null, "no targets always-on");
    view.onExitSleep();
    view.onUpdate(dc);

    var stats = System.getSystemStats();
    logger.debug("memory: " + stats.usedMemory + " of " + stats.totalMemory + " bytes used, " + stats.freeMemory + " free");
    return true;
}
