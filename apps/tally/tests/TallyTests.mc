import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;
import Toybox.Time;
import Toybox.WatchUi;

// Run No Evil tests for Tally: scripts/test.sh tally [device]. The log runs
// on the test app's own object store, emptied first.

(:test)
module TallyTestKit {
function clearLog() as Void {
    var n = TallyLog.count();
    for (var c = 0; c <= n / TallyLog.CHUNK; c++) {
        Storage.deleteValue("c" + c);
    }
    Storage.deleteValue(TallyLog.COUNT);
    Storage.deleteValue(TallyLog.SENT);
    Storage.deleteValue(TallyLog.NAMES);
    Storage.deleteValue(TallyLog.LAST);
    Storage.deleteValue(TallyLog.EDITS);
}
}

(:test)
function testStats(logger as Logger) as Boolean {
    var h = 3600;
    // a cluster at 19:30-20:10, and one stray at 3:00
    var secs = [19 * h + 1800, 20 * h + 600, 19 * h + 2700, 3 * h, 19 * h + 3000] as Array<Number>;
    var u = TallyStats.usual(secs) as [Number, Number, Number];
    Test.assertEqualMessage(u[1], 4, "four in the busiest two hours");
    Test.assertEqualMessage(u[2], 19 * h + 1800, "the window starts at the first of them");
    Test.assertEqualMessage(u[0], (19 * h + 1800 + 20 * h + 600 + 19 * h + 2700 + 19 * h + 3000) / 4, "their average");
    // across midnight: 23:30, 00:20, 23:50 -> about 23:53
    var late = [23 * h + 1800, 1200, 23 * h + 3000] as Array<Number>;
    var v = TallyStats.usual(late) as [Number, Number, Number];
    Test.assertEqualMessage(v[1], 3, "the window wraps past midnight");
    Test.assertEqualMessage(v[0], (23 * h + 1800 + 23 * h + 3000 + 86400 + 1200) / 3 % 86400, "and so does the average");
    Test.assertMessage(TallyStats.usual([5] as Array<Number>) == null, "one entry has no usual time");

    var days = [0, 1, 1, 2, 4] as Array<Number>;
    Test.assertEqualMessage(TallyStats.streak(days), 3, "today, yesterday, the day before");
    Test.assertEqualMessage(TallyStats.streak([3, 4, 6] as Array<Number>), 2, "counted from the newest day");
    Test.assertEqualMessage(TallyStats.streak([] as Array<Number>), 0, "none");
    Test.assertEqualMessage(TallyStats.distinct(days), 4, "distinct days");
    Test.assertEqualMessage(TallyStats.daysWithin(days, [19 * h, 19 * h, 2 * h, 20 * h, 21 * h] as Array<Number>, 19 * h, 7200), 3, "days 0, 1 and 2 inside 19-21");
    Test.assertEqualMessage(TallyStats.stripStart(20 * h, 0), 14, "six hours before the usual time");
    Test.assertEqualMessage(TallyStats.stripStart(2 * h, 0), 20, "wrapping back past midnight");
    Test.assertEqualMessage(TallyStats.stripStart(null, 10 * h), 2, "or back from now");
    return true;
}

// Milk 45 minutes before most evenings' event; dinner every day, so it
// came before the event and before the control moments alike
(:test)
function testBefore(logger as Logger) as Boolean {
    var h = 3600;
    var bDays = [0, 1, 2, 4] as Array<Number>;
    var bSecs = [20 * h, 20 * h, 20 * h, 20 * h] as Array<Number>;
    var milkDays = [0, 1, 2, 3] as Array<Number>;
    var milkSecs = [19 * h + 900, 19 * h + 900, 19 * h + 900, 19 * h] as Array<Number>;
    var dinnerDays = [0, 1, 2, 3, 4, 5] as Array<Number>;
    var dinnerSecs = [17 * h, 17 * h, 17 * h, 17 * h, 17 * h, 17 * h] as Array<Number>;
    var controls = TallyStats.without([0, 1, 2, 3, 4, 5, 5] as Array<Number>, bDays);
    Test.assertEqualMessage(controls.size(), 2, "days 3 and 5 had entries but no event");
    var milk = TallyStats.before(bDays, bSecs, milkDays, milkSecs, controls, 20 * h);
    Test.assertMessage(milk[0] == 3 && milk[1] == 4, "milk before 3 of 4");
    Test.assertEqualMessage(milk[2], 2700, "usually 45 minutes before");
    Test.assertMessage(milk[3] == 1 && milk[4] == 2, "and on 1 of 2 days without");
    var dinner = TallyStats.before(bDays, bSecs, dinnerDays, dinnerSecs, controls, 20 * h);
    Test.assertMessage(dinner[0] == 4 && dinner[3] == 2, "dinner before every event and every control");
    // across midnight: an entry at 23:30 comes 1 h before 00:30 the next day
    Test.assertEqualMessage(TallyStats.gapBefore(1800, [1] as Array<Number>, [23 * h + 1800] as Array<Number>) as Number, 3600, "across midnight");
    Test.assertMessage(TallyStats.gapBefore(20 * h, [0] as Array<Number>, [13 * h] as Array<Number>) == null, "more than six hours is not before");
    Test.assertMessage(TallyStats.gapBefore(20 * h, [0] as Array<Number>, [21 * h] as Array<Number>) == null, "after is not before");
    return true;
}

(:test)
function testButtons(logger as Logger) as Boolean {
    var evening = new TallyButton("Bed", 0, 18, 24, 1);
    Test.assertMessage(evening.shownAt(18) && evening.shownAt(23) && !evening.shownAt(17) && !evening.shownAt(0), "18 until midnight");
    var night = new TallyButton("Wake", 0, 22, 6, 1);
    Test.assertMessage(night.shownAt(23) && night.shownAt(2) && !night.shownAt(6) && !night.shownAt(12), "a window past midnight");
    var always = new TallyButton("Note", 0, TallyButtons.ALWAYS, 24, 1);
    Test.assertMessage(always.shownAt(0) && always.shownAt(13), "always");

    var b = TallyButtons.parse({"name" => "  Milk ", "colour" => 4, "from" => 16, "until" => 21}) as TallyButton;
    Test.assertEqualMessage(b.name, "Milk", "trimmed");
    Test.assertEqualMessage(b.colour, TallyButtons.COLOURS[4], "colour from the list");
    Test.assertMessage(TallyButtons.parse({"name" => "   "}) == null, "a blank name is no button");
    var c = TallyButtons.parse({"name" => "X", "colour" => 99}) as TallyButton;
    Test.assertMessage(c.colour == TallyButtons.COLOURS[0] && c.from == TallyButtons.ALWAYS, "defaults for missing fields");

    // ten always-on buttons, one large: the ring's eight places keep the
    // most used around now, in the phone's order
    var many = [] as Array<TallyButton>;
    for (var i = 0; i < 10; i++) {
        many.add(new TallyButton("B" + i, 0, TallyButtons.ALWAYS, 24, (i == 4) ? 2 : 1));
    }
    var shown = TallyButtons.onScreen(many, 12, [5, 0, 3, 3, 9, 1, 2, 4, 6, 7] as Array<Number>);
    var names = "";
    for (var i = 0; i < shown.size(); i++) {
        names += shown[i].name;
    }
    Test.assertEqualMessage(names, "B0B2B3B4B7B8B9", "seven buttons, one large, in eight places");
    Test.assertEqualMessage(TallyButtons.starts(shown)[1], TallyButtons.PLACES, "eight places used");
    // the wedges: B0 centred at the top over 45 degrees, B4 taking 90
    Test.assertEqualMessage(TallyButtons.wedgeAt(shown, 0.0), 0, "the top");
    Test.assertEqualMessage(TallyButtons.wedgeAt(shown, -20.0), 0, "just left of the top");
    Test.assertEqualMessage(TallyButtons.wedgeAt(shown, 30.0), 1, "the next clockwise");
    Test.assertEqualMessage(TallyButtons.wedgeAt(shown, 160.0), 3, "the large one starts at 112.5");
    Test.assertEqualMessage(TallyButtons.wedgeAt(shown, 200.0), 3, "and runs to 202.5");
    Test.assertEqualMessage(TallyButtons.wedgeAt(shown, 210.0), 4, "then the next");
    Test.assertEqualMessage(TallyButtons.wedgeAt(shown, 337.0), 6, "the last, left of the top");
    var big = TallyButtons.parse({"name" => "X", "size" => 2}) as TallyButton;
    Test.assertMessage(big.size == 2 && (TallyButtons.parse({"name" => "Y", "size" => 7}) as TallyButton).size == 1, "sizes");
    Test.assertEqualMessage(TallyButtons.onScreen([evening, night] as Array<TallyButton>, 12, [0, 0] as Array<Number>).size(), 0, "none at noon");
    Test.assertEqualMessage(TallyButtons.colourOf("Nope", many), TallyButtons.OTHER, "an unknown name is grey");
    return true;
}

(:test)
function testEdit(logger as Logger) as Boolean {
    // the buttons changed on the watch, in the phone's own slots; put back after
    var fields = ["Name", "Colour", "From", "Until", "Size"] as Array<String>;
    var saved = [] as Array<Properties.ValueType>;
    for (var i = 1; i <= TallyButtons.SLOTS; i++) {
        for (var f = 0; f < fields.size(); f++) {
            saved.add(Properties.getValue("B" + i + fields[f]));
        }
    }
    for (var i = 1; i <= TallyButtons.SLOTS; i++) {
        TallyEdit.set(i, "Name", "");
    }
    TallyEdit.set(2, "Name", "Feed");
    TallyEdit.set(2, "Colour", 0);
    TallyEdit.set(2, "From", 22);
    TallyEdit.set(2, "Until", 6);
    TallyEdit.set(2, "Size", 2);
    var b = TallyButtons.slot(2) as TallyButton;
    Test.assertMessage(b.name.equals("Feed") && b.from == 22 && b.until == 6 && b.size == 2, "written to slot 2");
    Test.assertMessage(TallyButtons.slot(1) == null, "slot 1 empty");
    Test.assertEqualMessage(TallyEdit.colourName(b.colour), "Coral", "colour name");
    Test.assertMessage(TallyEdit.describe(b).find("large") != null && !TallyEdit.hours(b).equals("always"), "describe");
    Test.assertEqualMessage(TallyEdit.freeColour(), 1, "the first colour no button has");
    var menu = new WatchUi.Menu2({:title => "Buttons"});
    TallyEdit.fill(menu);
    Test.assertMessage((menu.getItem(0) as WatchUi.MenuItem).getId() == 2 && (menu.getItem(1) as WatchUi.MenuItem).getId() == TallyEdit.ADD && menu.getItem(2) == null, "one button, then Add");
    TallyEdit.fill(menu);
    Test.assertMessage(menu.getItem(2) == null, "refilled, not doubled");
    var slot = new WatchUi.Menu2({:title => ""});
    TallyEdit.fillSlot(slot, 2);
    TallyEdit.set(2, "Name", "Bottle");
    TallyEdit.fillSlot(slot, 2);
    Test.assertMessage("Bottle".equals((slot.getItem(0) as WatchUi.MenuItem).getSubLabel()) && slot.getItem(5) == null, "slot menu refreshed in place");
    TallyEdit.set(2, "From", TallyButtons.ALWAYS);
    Test.assertEqualMessage(TallyEdit.hours(TallyButtons.slot(2) as TallyButton), "always", "always");

    var k = 0;
    for (var i = 1; i <= TallyButtons.SLOTS; i++) {
        for (var f = 0; f < fields.size(); f++) {
            Properties.setValue("B" + i + fields[f], saved[k]);
            k++;
        }
    }
    return true;
}

(:test)
function testLog(logger as Logger) as Boolean {
    TallyTestKit.clearLog();
    var t = 1700000000;
    Test.assertEqualMessage(TallyLog.add(t, "Milk"), 0, "the first entry is 0");
    TallyLog.add(t + 60, "Bed");
    TallyLog.add(t + 120, "Milk");
    Test.assertEqualMessage(TallyLog.count(), 3, "three logged");
    Test.assertEqualMessage(TallyLog.names().size(), 2, "two names");
    var all = TallyLog.since(t + 30);
    Test.assertEqualMessage(all[0].size(), 2, "two since then");
    Test.assertEqualMessage(all[1][1], 0, "the newest is Milk");

    // the sheet gets what settled, from the first it hasn't confirmed
    var batch = TallyLog.unsent(10, t + 100) as [Number, Array<Number>, Array<String>];
    Test.assertMessage(batch[0] == 0 && batch[1].size() == 2 && batch[2][1].equals("Bed"), "two settled entries");
    TallyLog.confirm(2);
    batch = TallyLog.unsent(10, t + 1000) as [Number, Array<Number>, Array<String>];
    Test.assertMessage(batch[0] == 2 && batch[1].size() == 1, "then the third");
    TallyLog.confirm(99);
    Test.assertEqualMessage(TallyLog.sent(), 2, "never past what exists");

    Test.assertMessage(TallyLog.undo(), "undo the unsent one");
    Test.assertEqualMessage(TallyLog.count(), 2, "two left");
    Test.assertMessage(!TallyLog.undo(), "the sheet has the rest: no undo");
    Test.assertMessage(TallyLog.unsent(10, t + 1000) == null, "nothing waiting");

    // History: change and delete. Entry 1 (Bed) is with the sheet, so its
    // changes wait for it; a new unsent entry is changed in place
    TallyLog.change(1, t + 90, "Milk");
    var e = TallyLog.entry(1) as [Number, String];
    Test.assertMessage(e[0] == t + 90 && e[1].equals("Milk"), "entry 1 is now Milk at +90");
    Test.assertEqualMessage(TallyLog.edits().size(), 3, "one change for the sheet");
    TallyLog.change(1, t + 90, "");
    Test.assertEqualMessage(TallyLog.edits().size(), 3, "the delete replaces it");
    Test.assertMessage((TallyLog.edits()[2] as String).equals(""), "as a delete");
    Test.assertEqualMessage(TallyLog.since(t)[0].size(), 1, "the deleted entry is left out");
    Test.assertEqualMessage(TallyLog.latest(10)[0].size(), 1, "and out of History");
    TallyLog.confirmEdits(1);
    Test.assertEqualMessage(TallyLog.edits().size(), 0, "the sheet applied it");
    var n = TallyLog.add(t + 300, "Typo");
    TallyLog.change(n, t + 300, "");
    Test.assertEqualMessage(TallyLog.edits().size(), 0, "an unsent entry changes in place");
    var gap = TallyLog.unsent(10, t + 1000) as [Number, Array<Number>, Array<String>];
    Test.assertMessage(gap[0] == n && gap[2][0].equals(""), "sent as a gap the sheet counts");
    TallyLog.confirm(n + 1);
    Test.assertMessage(TallyLog.latest(5)[0][0] == 0, "History, newest first: entry 0");

    // past a chunk
    for (var i = 0; i < TallyLog.CHUNK + 5; i++) {
        TallyLog.add(t + 200 + i, "Tick");
    }
    Test.assertEqualMessage(TallyLog.since(t)[0].size(), TallyLog.CHUNK + 6, "every live entry across two chunks");
    Test.assertEqualMessage(TallyLog.first(), 0, "nothing dropped yet");
    var id = TallyLog.installId();
    Test.assertMessage(id.length() == 8 && id.equals(TallyLog.installId()), "a steady install id");
    TallyTestKit.clearLog();
    return true;
}

// Every page draws, with and without entries, on this device's screen
(:test)
function testDraw(logger as Logger) as Boolean {
    TallyTestKit.clearLog();
    var settings = System.getDeviceSettings();
    var w = settings.screenWidth;
    var screen = (Graphics.createBufferedBitmap({:width => w, :height => settings.screenHeight}).get() as Graphics.BufferedBitmap).getDc();
    var view = new TallyView();
    view.onLayout(screen);
    logger.debug("font heights: xtiny " + Graphics.getFontHeight(Graphics.FONT_XTINY) + " tiny " + Graphics.getFontHeight(Graphics.FONT_TINY)
                 + " small " + Graphics.getFontHeight(Graphics.FONT_SMALL) + " medium " + Graphics.getFontHeight(Graphics.FONT_MEDIUM)
                 + " vector 0.042 em " + Graphics.getFontHeight(Lib.Fmt.vectorFont("RobotoCondensedRegular", (w * 0.042 * 1.17).toNumber(), Graphics.FONT_XTINY)));
    for (var p = 0; p < 4; p++) {
        view.page = p;
        view.onUpdate(screen);
    }
    // two weeks of evenings
    var now = Time.now().value();
    for (var d = 13; d >= 0; d--) {
        TallyLog.add(now - d * 86400 - 3600, "Meal");
        TallyLog.add(now - d * 86400 - 1800, "Symptom");
    }
    view.reload();
    var t0 = System.getTimer();
    for (var p = 0; p < 4; p++) {
        view.page = p;
        view.onUpdate(screen);
        view.nextName();
        view.onUpdate(screen);
    }
    logger.debug("four pages twice: " + (System.getTimer() - t0) + " ms");
    view.page = PAGE_LOG;
    // a tap on the top wedge logs its button, a tap on the centre takes it back
    var before = TallyLog.count();
    if (view.buttons().size() > 0) {
        view.tap(w / 2, (w * 0.17).toNumber());
        Test.assertEqualMessage(TallyLog.count(), before + 1, "the top wedge logged");
        view.onUpdate(screen);
        view.tap(w / 2, w / 2);
        Test.assertEqualMessage(TallyLog.count(), before, "the centre undid it");
    }
    // All: the buttons, then a name typed with Other
    TallyLog.add(Time.now().value() - 60, "Hiccups");
    view.reload();
    var all = TallyAll.names(view);
    Test.assertMessage(all.indexOf("Hiccups") == view.buttons().size(), "a typed name follows the buttons: " + all);
    var glanceDc = (Graphics.createBufferedBitmap({:width => (w * 0.77).toNumber(), :height => (w * 0.29).toNumber()}).get() as Graphics.BufferedBitmap).getDc();
    var glance = new TallyGlance();
    glance.onLayout(glanceDc);
    glance.onUpdate(glanceDc);
    TallyTestKit.clearLog();
    glance.onUpdate(glanceDc);
    return true;
}
