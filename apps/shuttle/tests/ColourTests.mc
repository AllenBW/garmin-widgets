import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

// Shuttle's colours: the palette and the time and date colour, chosen on the
// phone, in the face's menu on the watch or in the watch face editor,
// whichever was changed last (Choices, Lib.Config, Lib.WatchMenu)
module ShuttleColours {

    const KEYS = ["Style", "DataColor", "MutedWeeks", "SlidingDigits"] as Array<String>;

    function dc() as Dc {
        var settings = System.getDeviceSettings();
        return (Graphics.createBufferedBitmap({:width => settings.screenWidth, :height => settings.screenHeight}).get()
                as Graphics.BufferedBitmap).getDc();
    }

    // The settings and the source as they were, to put back
    function save() as Array {
        var was = [] as Array;
        for (var k = 0; k < KEYS.size(); k++) {
            was.add(Application.Properties.getValue(KEYS[k]));
        }
        was.add(Application.Storage.getValue(Lib.Config.SOURCE));
        was.add(Application.Storage.getValue(Lib.Look.KEY));
        return was;
    }

    function restore(was as Array) as Void {
        for (var k = 0; k < KEYS.size(); k++) {
            var v = was[k];
            if (v != null) {
                Application.Properties.setValue(KEYS[k], v as Application.Properties.ValueType);
            }
        }
        var source = was[KEYS.size()];
        if (source != null) {
            Application.Storage.setValue(Lib.Config.SOURCE, source as String);
        } else {
            Application.Storage.deleteValue(Lib.Config.SOURCE);
        }
        var look = was[KEYS.size() + 1];
        if (look != null) {
            Application.Storage.setValue(Lib.Look.KEY, look as Number);
        } else {
            Application.Storage.deleteValue(Lib.Look.KEY);
        }
    }

    function chosen(palette as Number, time as Number) as Void {
        Application.Properties.setValue("Style", palette);
        Application.Properties.setValue("DataColor", time);
        Lib.Config.changedOnPhone();
    }

    // The colours the face draws in the look `m`
    function colors(m as Number) as Lib.Numbers.Colors {
        return new ShuttleView().colors(m);
    }

    // Whether `c` is the palette with the time colour
    function is(c as Lib.Numbers.Colors, palette as Number, time as Number) as Boolean {
        var q = Lib.Numbers.yours(palette, time);
        return c.neutral == q.neutral && c.sun == q.sun && c.weather == q.weather && c.body == q.body
               && c.second == q.second && c.third == q.third && c.fluorescent == q.fluorescent;
    }
}

// The defaults are the face as it always was: Classic and Bone are
// Lib.Numbers' own colours
(:test)
function testShuttleColoursDefault(logger as Logger) as Boolean {
    var was = ShuttleColours.save();
    ShuttleColours.chosen(0, 0);
    var c = ShuttleColours.colors(Lib.Look.YOURS);
    var y = Lib.Numbers.colors(Lib.Look.YOURS);
    Test.assertMessage(c.neutral == y.neutral && c.sun == y.sun && c.weather == y.weather && c.body == y.body
                       && c.second == y.second && c.third == y.third && c.fluorescent == y.fluorescent, "the defaults are the face's own colours");
    // the other looks are Lib.Numbers', whatever the palette
    ShuttleColours.chosen(4, 3);
    for (var m = 1; m < Lib.Look.MODES; m++) {
        var a = ShuttleColours.colors(m);
        var b = Lib.Numbers.colors(m);
        Test.assertMessage(a.neutral == b.neutral && a.sun == b.sun && a.weather == b.weather && a.body == b.body,
                           "look " + m + " keeps its own colours");
    }
    ShuttleColours.restore(was);
    return true;
}

// Every palette and every time and date colour draws, awake and in standby
(:test)
function testShuttleColoursDraw(logger as Logger) as Boolean {
    var was = ShuttleColours.save();
    Application.Storage.setValue(Lib.Look.KEY, Lib.Look.YOURS);
    var dc = ShuttleColours.dc();
    var view = new ShuttleView();
    view.onLayout(dc);
    for (var i = 0; i < Lib.Numbers.PALETTES.size() + Lib.Config.DATA.size(); i++) {
        var palette = (i < Lib.Numbers.PALETTES.size()) ? i : 0;
        var time = (i < Lib.Numbers.PALETTES.size()) ? 0 : i - Lib.Numbers.PALETTES.size();
        ShuttleColours.chosen(palette, time);
        view.reloadSettings();
        Test.assertMessage(ShuttleColours.is(ShuttleColours.colors(Lib.Look.YOURS), palette, Lib.Config.DATA[time]),
                           "palette " + palette + " with time colour " + time);
        view.onUpdate(dc);
        view.setAwake(false);
        view.onUpdate(dc);
        view.setAwake(true);
        view.onUpdate(dc);
    }
    ShuttleColours.restore(was);
    return true;
}

// A change on the phone and one in the editor each take, the later winning
(:test)
function testShuttleColoursLaterWins(logger as Logger) as Boolean {
    var was = ShuttleColours.save();
    ShuttleColours.chosen(4, 3);                      // Dusk with Ice, on the phone
    Test.assertMessage(ShuttleColours.is(ShuttleColours.colors(Lib.Look.YOURS), 4, Lib.Config.DATA[3]), "the phone's choice is drawn");
    Lib.Config.changedInEditor();                     // as the delegate's onWatchFaceConfigEdited
    var c = ShuttleColours.colors(Lib.Look.YOURS);
    var config = (Application has :WatchFaceConfig) ? Application.WatchFaceConfig.getSettings(null) : null;
    if (config != null && config.styleId != null) {
        // the editor's own (the simulator's are its defaults: Classic and Bone)
        var picked = config.complicationColor;
        var time = (picked != null && picked.color != null) ? picked.color as Number : Lib.Config.DATA[3];
        Test.assertMessage(ShuttleColours.is(c, config.styleId as Number, time), "then the editor's");
        logger.debug("editor: palette " + config.styleId + ", time colour " + time.format("%06X"));
    } else {
        Test.assertMessage(ShuttleColours.is(c, 4, Lib.Config.DATA[3]), "no editor: the phone's still");
    }
    ShuttleColours.chosen(7, 1);                      // Slate with Silver, on the phone again
    Test.assertMessage(ShuttleColours.is(ShuttleColours.colors(Lib.Look.YOURS), 7, Lib.Config.DATA[1]), "and the phone's again");
    ShuttleColours.restore(was);
    return true;
}

// The menu on the watch is the phone app's list: the look, the palette, the
// time colour and the two switches; a choice writes the phone's property
(:test)
function testShuttleMenu(logger as Logger) as Boolean {
    var was = ShuttleColours.save();
    var entries = Choices.entries();
    Test.assertEqualMessage(entries.size(), 5, "the look, two colours and two switches, as on the phone");
    Test.assertMessage(entries[0][1] == null, "the look first");
    for (var n = 0; n < Lib.Look.MODES; n++) {
        Test.assertEqualMessage(entries[0][3][n], Lib.Look.ORDER[n], "the looks in Lib.Look's order");
    }
    Test.assertEqualMessage(entries[1][2].size(), Lib.Numbers.PALETTES.size(), "every palette");
    Test.assertEqualMessage(entries[2][2].size(), Lib.Config.DATA.size(), "every time colour");
    for (var i = 0; i < entries.size(); i++) {
        Test.assertEqualMessage(entries[i][2].size(), entries[i][3].size(), "a label for every choice");
    }
    Lib.Config.changedInEditor();
    Lib.WatchMenu.choose(entries[1], 6);              // Smoke
    Test.assertEqualMessage(Lib.WatchMenu.current(entries[1]), 6, "the choice is where the setting stands");
    Test.assertMessage(Lib.Config.PHONE.equals(Application.Storage.getValue(Lib.Config.SOURCE)), "a choice on the watch wins over the editor");
    Test.assertEqualMessage(ShuttleColours.colors(Lib.Look.YOURS).sun, Lib.Numbers.yours(6, 0).sun, "and is drawn");
    // a switch: written as the phone writes it, a boolean
    var muted = entries[3];
    Application.Properties.setValue("MutedWeeks", true);
    Test.assertEqualMessage(Lib.WatchMenu.current(muted), 0, "on shows On");
    Lib.WatchMenu.choose(muted, 1);
    Test.assertEqualMessage(Application.Properties.getValue("MutedWeeks"), false, "Off writes false");
    Test.assertEqualMessage(Lib.WatchMenu.label(muted), muted[2][1], "and shows Off");
    Lib.WatchMenu.choose(muted, 0);
    Test.assertEqualMessage(Application.Properties.getValue("MutedWeeks"), true, "On writes true");
    Lib.WatchMenu.choose(entries[0], 4);              // the fifth look in the order: low light
    Test.assertEqualMessage(Lib.Look.mode(), Lib.Look.LOW, "the look chosen as a hold chooses it");
    ShuttleColours.restore(was);
    return true;
}
