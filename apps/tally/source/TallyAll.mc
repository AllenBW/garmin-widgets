import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// Every button, whatever the hour, then every other name with entries in
// the last LOOKBACK days (the ones typed with Other), newest first, then
// Other itself (a name typed on the watch, for something no button covers),
// a past entry (one missed earlier: a name, then a time), and History.
// Choosing a name logs it now and goes back.
module TallyAll {

    const OTHER = :other;
    const HISTORY = :history;
    const PAST = :past;
    const LOOKBACK = 90;        // days

    function open(view as TallyView) as Void {
        var menu = new WatchUi.Menu2({:title => "All"});
        var days = view.days();
        var names = names(view);
        for (var i = 0; i < names.size(); i++) {
            menu.addItem(new WatchUi.MenuItem(names[i], today(days, names[i]), names[i], null));
        }
        menu.addItem(new WatchUi.MenuItem("Other…", "type a name", OTHER, null));
        menu.addItem(new WatchUi.MenuItem("Add a past entry", "one you missed", PAST, null));
        menu.addItem(new WatchUi.MenuItem("History", "change or delete entries", HISTORY, null));
        WatchUi.pushView(menu, new TallyAllDelegate(view), WatchUi.SLIDE_UP);
    }

    // The buttons in the phone's order, then the other names with entries
    // in the last LOOKBACK days, the most recently used first
    function names(view as TallyView) as Array<String> {
        var out = [] as Array<String>;
        var buttons = view.buttons();
        for (var i = 0; i < buttons.size(); i++) {
            if (out.indexOf(buttons[i].name) < 0) {
                out.add(buttons[i].name);
            }
        }
        var table = TallyLog.names();
        var log = TallyLog.since(Time.now().value() - LOOKBACK * 86400);
        for (var i = log[1].size() - 1; i >= 0; i--) {
            var name = table[log[1][i]];
            if (out.indexOf(name) < 0) {
                out.add(name);
            }
        }
        return out;
    }

    // "2 today", or nothing
    function today(days as TallyDays, name as String) as String? {
        var mine = days.of(name)[0];
        var n = 0;
        for (var i = 0; i < mine.size(); i++) {
            if (mine[i] == 0) {
                n++;
            }
        }
        return (n > 0) ? n + " today" : null;
    }

    // "Today 7:42", "Yesterday 19:05", "Tue 3 Nov 7:42"
    function when(t as Number) as String {
        var today = Time.today().value();
        var day = (t >= today) ? "Today" : (t >= today - 86400) ? "Yesterday" : Lib.Fmt.shortDate(new Time.Moment(t));
        return day + " " + Lib.Fmt.clockAt(t);
    }
}

class TallyAllDelegate extends WatchUi.Menu2InputDelegate {

    private var _view as TallyView;

    function initialize(view as TallyView) {
        Menu2InputDelegate.initialize();
        _view = view;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == TallyAll.HISTORY) {
            WatchUi.switchToView(TallyHistory.menu(), new TallyHistoryDelegate(_view), WatchUi.SLIDE_LEFT);
            return;
        }
        if (id == TallyAll.PAST) {
            var menu = new WatchUi.Menu2({:title => "Past entry"});
            var names = TallyAll.names(_view);
            for (var i = 0; i < names.size(); i++) {
                menu.addItem(new WatchUi.MenuItem(names[i], null, names[i], null));
            }
            WatchUi.switchToView(menu, new TallyPastDelegate(_view), WatchUi.SLIDE_LEFT);
            return;
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (id == TallyAll.OTHER) {
            if (WatchUi has :TextPicker) {
                WatchUi.pushView(new WatchUi.TextPicker(""), new TallyOtherDelegate(_view), WatchUi.SLIDE_UP);
            }
        } else if (id instanceof String) {
            _view.log(id);
        }
    }
}

class TallyOtherDelegate extends WatchUi.TextPickerDelegate {

    private var _view as TallyView;

    function initialize(view as TallyView) {
        TextPickerDelegate.initialize();
        _view = view;
    }

    function onTextEntered(text as String, changed as Boolean) as Boolean {
        var name = TallyButtons.trim(text);
        if (name.length() > 0) {
            _view.log(name);
        }
        return true;
    }

    function onCancel() as Boolean {
        return true;
    }
}

// History: every entry on the watch, newest first (the last SHOWN). Choose
// one to change its button or its time, or to delete it. Each step
// replaces the menu before it, so BACK from any of them returns here and
// BACK from here to the buttons.
module TallyHistory {

    const SHOWN = 100;
    const BUTTON = :button;
    const TIME = :time;
    const DELETE = :delete;
    const SURE = :sure;

    function menu() as WatchUi.Menu2 {
        var menu = new WatchUi.Menu2({:title => "History"});
        var latest = TallyLog.latest(SHOWN);
        var table = TallyLog.names();
        // newest time first: a past entry sits where it happened
        var order = [] as Array<Number>;
        for (var i = 0; i < latest[0].size(); i++) {
            var k = order.size();
            while (k > 0 && latest[1][order[k - 1]] < latest[1][i]) {
                k--;
            }
            order = order.slice(0, k).addAll([i]).addAll(order.slice(k, null));
        }
        for (var j = 0; j < order.size(); j++) {
            var i = order[j];
            menu.addItem(new WatchUi.MenuItem(table[latest[2][i]], TallyAll.when(latest[1][i]), latest[0][i], null));
        }
        if (latest[0].size() == 0) {
            menu.addItem(new WatchUi.MenuItem("Nothing yet", null, :none, null));
        }
        return menu;
    }

    function back(view as TallyView) as Void {
        view.reload();
        view.sync();
        WatchUi.switchToView(menu(), new TallyHistoryDelegate(view), WatchUi.SLIDE_RIGHT);
    }
}

class TallyHistoryDelegate extends WatchUi.Menu2InputDelegate {

    private var _view as TallyView;

    function initialize(view as TallyView) {
        Menu2InputDelegate.initialize();
        _view = view;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var n = item.getId();
        if (!(n instanceof Number)) {
            return;
        }
        var e = TallyLog.entry(n);
        if (e == null) {
            return;
        }
        var menu = new WatchUi.Menu2({:title => e[1]});
        menu.addItem(new WatchUi.MenuItem("Button", e[1], TallyHistory.BUTTON, null));
        menu.addItem(new WatchUi.MenuItem("Time", TallyAll.when(e[0]), TallyHistory.TIME, null));
        menu.addItem(new WatchUi.MenuItem("Delete", null, TallyHistory.DELETE, null));
        WatchUi.switchToView(menu, new TallyEntryDelegate(_view, n), WatchUi.SLIDE_LEFT);
    }
}

// One entry: change its button or time, or delete it (asked twice)
class TallyEntryDelegate extends WatchUi.Menu2InputDelegate {

    private var _view as TallyView;
    private var _n as Number;

    function initialize(view as TallyView, n as Number) {
        Menu2InputDelegate.initialize();
        _view = view;
        _n = n;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        var e = TallyLog.entry(_n);
        if (e == null) {
            TallyHistory.back(_view);
            return;
        }
        if (id == TallyHistory.BUTTON) {
            var menu = new WatchUi.Menu2({:title => "Button"});
            var names = TallyAll.names(_view);
            for (var i = 0; i < names.size(); i++) {
                menu.addItem(new WatchUi.MenuItem(names[i], names[i].equals(e[1]) ? "now" : null, names[i], null));
            }
            WatchUi.switchToView(menu, new TallyRenameDelegate(_view, _n), WatchUi.SLIDE_LEFT);
        } else if (id == TallyHistory.TIME) {
            var picker = new TallyTimePicker(e[0]);
            WatchUi.switchToView(picker, new TallyTimeDelegate(_view, _n, picker), WatchUi.SLIDE_LEFT);
        } else if (id == TallyHistory.DELETE) {
            var menu = new WatchUi.Menu2({:title => "Delete?"});
            menu.addItem(new WatchUi.MenuItem("Delete " + e[1], TallyAll.when(e[0]), TallyHistory.SURE, null));
            menu.addItem(new WatchUi.MenuItem("Keep it", null, :keep, null));
            WatchUi.switchToView(menu, new TallyDeleteDelegate(_view, _n), WatchUi.SLIDE_LEFT);
        }
    }

    function onBack() as Void {
        TallyHistory.back(_view);
    }
}

class TallyRenameDelegate extends WatchUi.Menu2InputDelegate {

    private var _view as TallyView;
    private var _n as Number;

    function initialize(view as TallyView, n as Number) {
        Menu2InputDelegate.initialize();
        _view = view;
        _n = n;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var e = TallyLog.entry(_n);
        var name = item.getId();
        if (e != null && name instanceof String) {
            TallyLog.change(_n, e[0], name);
        }
        TallyHistory.back(_view);
    }

    function onBack() as Void {
        TallyHistory.back(_view);
    }
}

class TallyDeleteDelegate extends WatchUi.Menu2InputDelegate {

    private var _view as TallyView;
    private var _n as Number;

    function initialize(view as TallyView, n as Number) {
        Menu2InputDelegate.initialize();
        _view = view;
        _n = n;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var e = TallyLog.entry(_n);
        if (item.getId() == TallyHistory.SURE && e != null) {
            TallyLog.change(_n, e[0], "");
        }
        TallyHistory.back(_view);
    }

    function onBack() as Void {
        TallyHistory.back(_view);
    }
}

// A picker of labelled values (the day, the hour, the minute)
class TallyChoices extends WatchUi.PickerFactory {

    private var _labels as Array<String>;

    function initialize(labels as Array<String>) {
        PickerFactory.initialize();
        _labels = labels;
    }

    function getSize() as Number {
        return _labels.size();
    }

    function getValue(index as Number) as Object? {
        return index;
    }

    function getDrawable(index as Number, selected as Boolean) as Drawable? {
        return new WatchUi.Text({:text => _labels[index], :color => Graphics.COLOR_WHITE, :font => Graphics.FONT_MEDIUM,
                                 :locX => WatchUi.LAYOUT_HALIGN_CENTER, :locY => WatchUi.LAYOUT_VALIGN_CENTER});
    }
}

// An entry's time: the day (today and the six before), the hour, the minute
class TallyTimePicker extends WatchUi.Picker {

    static const DAYS_BACK = 7;

    function initialize(t as Number) {
        var today = Time.today().value();
        var ago = (t >= today) ? 0 : (today - t + 86399) / 86400;
        if (ago >= DAYS_BACK) {
            ago = DAYS_BACK - 1;
        }
        var days = [] as Array<String>;
        for (var d = 0; d < DAYS_BACK; d++) {
            days.add((d == 0) ? "Today" : (d == 1) ? "Yesterday"
                     : Gregorian.info(new Time.Moment(today - d * 86400 + 43200), Time.FORMAT_MEDIUM).day_of_week as String);
        }
        var hours = [] as Array<String>;
        var twelve = !System.getDeviceSettings().is24Hour;
        for (var h = 0; h < 24; h++) {
            hours.add(twelve ? (((h % 12 == 0) ? 12 : h % 12) + ((h < 12) ? " am" : " pm")) : h.format("%02d"));
        }
        var minutes = [] as Array<String>;
        for (var m = 0; m < 60; m++) {
            minutes.add(m.format("%02d"));
        }
        var wall = Lib.Fmt.localSeconds(t);
        Picker.initialize({:title => new WatchUi.Text({:text => "Time", :font => Graphics.FONT_SMALL,
                                                       :locX => WatchUi.LAYOUT_HALIGN_CENTER, :locY => WatchUi.LAYOUT_VALIGN_BOTTOM,
                                                       :color => Graphics.COLOR_WHITE}),
                           :pattern => [new TallyChoices(days), new TallyChoices(hours), new TallyChoices(minutes)],
                           :defaults => [ago, wall / 3600, (wall / 60) % 60]});
    }

    // The moment the picked values name, never later than now
    static function moment(values as Array) as Number {
        var t = Time.today().value() - (values[0] as Number) * 86400 + (values[1] as Number) * 3600 + (values[2] as Number) * 60;
        var now = Time.now().value();
        return (t > now) ? now : t;
    }
}

class TallyTimeDelegate extends WatchUi.PickerDelegate {

    private var _view as TallyView;
    private var _n as Number;

    function initialize(view as TallyView, n as Number, picker as TallyTimePicker) {
        PickerDelegate.initialize();
        _view = view;
        _n = n;
    }

    function onAccept(values as Array) as Boolean {
        var e = TallyLog.entry(_n);
        if (e != null) {
            TallyLog.change(_n, TallyTimePicker.moment(values), e[1]);
        }
        TallyHistory.back(_view);
        return true;
    }

    function onCancel() as Boolean {
        TallyHistory.back(_view);
        return true;
    }
}

// A past entry: the name chosen, then its time
class TallyPastDelegate extends WatchUi.Menu2InputDelegate {

    private var _view as TallyView;

    function initialize(view as TallyView) {
        Menu2InputDelegate.initialize();
        _view = view;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var name = item.getId();
        if (name instanceof String) {
            var picker = new TallyTimePicker(Time.now().value() - 3600);
            WatchUi.switchToView(picker, new TallyPastTimeDelegate(_view, name), WatchUi.SLIDE_LEFT);
        }
    }
}

class TallyPastTimeDelegate extends WatchUi.PickerDelegate {

    private var _view as TallyView;
    private var _name as String;

    function initialize(view as TallyView, name as String) {
        PickerDelegate.initialize();
        _view = view;
        _name = name;
    }

    // Logged at the picked time, then History shows where it landed
    function onAccept(values as Array) as Boolean {
        TallyLog.add(TallyTimePicker.moment(values), _name);
        TallyHistory.back(_view);
        return true;
    }

    function onCancel() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
