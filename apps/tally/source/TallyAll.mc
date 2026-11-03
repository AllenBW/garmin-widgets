import Toybox.Lang;
import Toybox.WatchUi;

// Every button, whatever the hour, then the names logged with Other in the
// last two weeks, then Other itself: a name typed on the watch, for
// something no button covers. Choosing one logs it and goes back.
module TallyAll {

    const OTHER = :other;

    function open(view as TallyView) as Void {
        var menu = new WatchUi.Menu2({:title => "All"});
        var days = view.days();
        var listed = [] as Array<String>;
        var buttons = view.buttons();
        for (var i = 0; i < buttons.size(); i++) {
            var name = buttons[i].name;
            if (listed.indexOf(name) < 0) {
                listed.add(name);
                menu.addItem(new WatchUi.MenuItem(name, today(days, name), name, null));
            }
        }
        for (var i = days.which.size() - 1; i >= 0; i--) {
            var name = days.names[days.which[i]];
            if (listed.indexOf(name) < 0) {
                listed.add(name);
                menu.addItem(new WatchUi.MenuItem(name, today(days, name), name, null));
            }
        }
        menu.addItem(new WatchUi.MenuItem("Other…", "type a name", OTHER, null));
        WatchUi.pushView(menu, new TallyAllDelegate(view), WatchUi.SLIDE_UP);
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
}

class TallyAllDelegate extends WatchUi.Menu2InputDelegate {

    private var _view as TallyView;

    function initialize(view as TallyView) {
        Menu2InputDelegate.initialize();
        _view = view;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
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
