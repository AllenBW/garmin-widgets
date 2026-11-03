import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// The buttons themselves, changed on the watch. They live in the same
// twelve setting slots the phone edits (B1 .. B12), written in place.
// Choose one to rename it, change its colour, size or hours, or remove it:
// its slot empties and its entries keep their name, so History and the
// sheet still show them. Add a button fills the first empty slot.
//
// Each choice opens over the menu before it and refreshes that menu when
// it closes, so BACK always goes one step up.
module TallyEdit {

    const ADD = :add;
    const NAME = :name;
    const COLOUR = :colour;
    const SIZE = :size;
    const HOURS = :hours;
    const REMOVE = :remove;
    const ALWAYS = :always;
    const SOME = :some;
    const SURE = :sure;

    function set(slot as Number, field as String, value as Properties.ValueType) as Void {
        Properties.setValue("B" + slot + field, value);
    }

    // The Buttons list: each button with its colour and how it shows, then Add
    function fill(menu as WatchUi.Menu2) as Void {
        while (menu.getItem(0) != null) {
            menu.deleteItem(0);
        }
        var free = false;
        for (var i = 1; i <= TallyButtons.SLOTS; i++) {
            var b = TallyButtons.slot(i);
            if (b == null) {
                free = true;
            } else {
                menu.addItem(new WatchUi.IconMenuItem(b.name, describe(b), i, new TallySwatch(b.colour), null));
            }
        }
        if (free) {
            menu.addItem(new WatchUi.MenuItem("Add a button", null, ADD, null));
        }
    }

    // "Amber · always", "Violet · 7 am–10 am · large"
    function describe(b as TallyButton) as String {
        return colourName(b.colour) + " · " + hours(b) + ((b.size == 2) ? " · large" : "");
    }

    function hours(b as TallyButton) as String {
        if (b.from == TallyButtons.ALWAYS || b.from % 24 == b.until % 24) {
            return "always";
        }
        return TallyAll.hour(b.from) + "–" + TallyAll.hour(b.until);
    }

    function colourName(colour as Number) as String {
        var i = TallyButtons.COLOURS.indexOf(colour);
        return (i >= 0) ? TallyButtons.NAMES[i] : "";
    }

    // One button's menu, its labels refreshed after each change
    function fillSlot(menu as WatchUi.Menu2, slot as Number) as Void {
        var b = TallyButtons.slot(slot);
        if (b == null) {
            return;
        }
        menu.setTitle(b.name);
        var items = [["Name", b.name, NAME], ["Colour", colourName(b.colour), COLOUR],
                     ["Size", (b.size == 2) ? "Large" : "Normal", SIZE], ["Shown", hours(b), HOURS],
                     ["Remove", null, REMOVE]] as Array<[String, String?, Symbol]>;
        for (var k = 0; k < items.size(); k++) {
            var item = new WatchUi.MenuItem(items[k][0], items[k][1], items[k][2], null);
            if (menu.getItem(k) == null) {
                menu.addItem(item);
            } else {
                menu.updateItem(item, k);
            }
        }
    }

    // A new button's colour: the first one no other button has
    function freeColour() as Number {
        var used = [] as Array<Number>;
        for (var i = 1; i <= TallyButtons.SLOTS; i++) {
            var b = TallyButtons.slot(i);
            if (b != null) {
                used.add(TallyButtons.COLOURS.indexOf(b.colour));
            }
        }
        for (var c = 0; c < TallyButtons.COLOURS.size(); c++) {
            if (used.indexOf(c) < 0) {
                return c;
            }
        }
        return 0;
    }
}

// A colour dot for a menu row
class TallySwatch extends WatchUi.Drawable {

    private var _colour as Number;

    function initialize(colour as Number) {
        Drawable.initialize({});
        _colour = colour;
    }

    function draw(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(_colour, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(w / 2, h / 2, ((w < h) ? w : h) * 0.3);
    }
}

class TallyButtonsDelegate extends WatchUi.Menu2InputDelegate {

    private var _view as TallyView;
    private var _menu as WatchUi.Menu2;

    function initialize(view as TallyView, menu as WatchUi.Menu2) {
        Menu2InputDelegate.initialize();
        _view = view;
        _menu = menu;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == TallyEdit.ADD) {
            if (WatchUi has :TextPicker) {
                WatchUi.pushView(new WatchUi.TextPicker(""), new TallyNameDelegate(new TallyChanged(_view, _menu, null, 0)), WatchUi.SLIDE_UP);
            }
        } else if (id instanceof Number) {
            var menu = new WatchUi.Menu2({:title => item.getLabel()});
            TallyEdit.fillSlot(menu, id);
            WatchUi.pushView(menu, new TallySlotDelegate(_view, _menu, menu, id), WatchUi.SLIDE_LEFT);
        }
    }
}

// One button: name, colour, size, hours, remove
class TallySlotDelegate extends WatchUi.Menu2InputDelegate {

    private var _view as TallyView;
    private var _list as WatchUi.Menu2;
    private var _menu as WatchUi.Menu2;
    private var _slot as Number;

    function initialize(view as TallyView, list as WatchUi.Menu2, menu as WatchUi.Menu2, slot as Number) {
        Menu2InputDelegate.initialize();
        _view = view;
        _list = list;
        _menu = menu;
        _slot = slot;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        var b = TallyButtons.slot(_slot);
        if (b == null) {
            return;
        }
        var changed = new TallyChanged(_view, _list, _menu, _slot);
        if (id == TallyEdit.NAME) {
            if (WatchUi has :TextPicker) {
                WatchUi.pushView(new WatchUi.TextPicker(b.name), new TallyNameDelegate(changed), WatchUi.SLIDE_UP);
            }
        } else if (id == TallyEdit.COLOUR) {
            var menu = new WatchUi.Menu2({:title => "Colour"});
            for (var c = 0; c < TallyButtons.COLOURS.size(); c++) {
                menu.addItem(new WatchUi.IconMenuItem(TallyButtons.NAMES[c], null, c, new TallySwatch(TallyButtons.COLOURS[c]), null));
            }
            menu.setFocus(TallyButtons.COLOURS.indexOf(b.colour));
            WatchUi.pushView(menu, new TallyChoiceDelegate(changed, "Colour"), WatchUi.SLIDE_LEFT);
        } else if (id == TallyEdit.SIZE) {
            var menu = new WatchUi.Menu2({:title => "Size"});
            menu.addItem(new WatchUi.MenuItem("Normal", "one place in the ring", 1, null));
            menu.addItem(new WatchUi.MenuItem("Large", "two places, easier to hit", 2, null));
            menu.setFocus(b.size - 1);
            WatchUi.pushView(menu, new TallyChoiceDelegate(changed, "Size"), WatchUi.SLIDE_LEFT);
        } else if (id == TallyEdit.HOURS) {
            var menu = new WatchUi.Menu2({:title => "Shown"});
            menu.addItem(new WatchUi.MenuItem("Always", null, TallyEdit.ALWAYS, null));
            menu.addItem(new WatchUi.MenuItem("Only some hours", "on the main screen; always in All", TallyEdit.SOME, null));
            menu.setFocus((TallyEdit.hours(b).equals("always")) ? 0 : 1);
            WatchUi.pushView(menu, new TallyShownDelegate(changed, b), WatchUi.SLIDE_LEFT);
        } else if (id == TallyEdit.REMOVE) {
            var menu = new WatchUi.Menu2({:title => "Remove?"});
            menu.addItem(new WatchUi.MenuItem("Remove " + b.name, "its entries stay", TallyEdit.SURE, null));
            menu.addItem(new WatchUi.MenuItem("Keep it", null, :keep, null));
            WatchUi.pushView(menu, new TallyRemoveDelegate(changed), WatchUi.SLIDE_LEFT);
        }
    }
}

// After a change: the main screen and both menus show it
class TallyChanged {

    private var _view as TallyView;
    private var _list as WatchUi.Menu2;
    private var _menu as WatchUi.Menu2?;     // the button's own menu; none while adding
    var slot as Number;

    function initialize(view as TallyView, list as WatchUi.Menu2, menu as WatchUi.Menu2?, slot as Number) {
        _view = view;
        _list = list;
        _menu = menu;
        self.slot = slot;
    }

    function done() as Void {
        _view.reload();
        TallyEdit.fill(_list);
        var menu = _menu;
        if (menu != null) {
            TallyEdit.fillSlot(menu, slot);
        }
    }
}

// A name typed for a button; slot 0 adds one in the first empty slot
class TallyNameDelegate extends WatchUi.TextPickerDelegate {

    private var _changed as TallyChanged;

    function initialize(changed as TallyChanged) {
        TextPickerDelegate.initialize();
        _changed = changed;
    }

    function onTextEntered(text as String, changed as Boolean) as Boolean {
        var name = TallyButtons.trim(text);
        if (name.length() == 0) {
            return true;
        }
        var slot = _changed.slot;
        if (slot == 0) {
            for (var i = TallyButtons.SLOTS; i >= 1; i--) {
                if (TallyButtons.slot(i) == null) {
                    slot = i;
                }
            }
            if (slot == 0) {
                return true;
            }
            TallyEdit.set(slot, "Colour", TallyEdit.freeColour());
            TallyEdit.set(slot, "From", TallyButtons.ALWAYS);
            TallyEdit.set(slot, "Until", 24);
            TallyEdit.set(slot, "Size", 1);
            _changed.slot = slot;
        }
        TallyEdit.set(slot, "Name", name);
        _changed.done();
        return true;
    }

    function onCancel() as Boolean {
        return true;
    }
}

// A colour or a size, written to the button's slot
class TallyChoiceDelegate extends WatchUi.Menu2InputDelegate {

    private var _changed as TallyChanged;
    private var _field as String;

    function initialize(changed as TallyChanged, field as String) {
        Menu2InputDelegate.initialize();
        _changed = changed;
        _field = field;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var value = item.getId();
        if (value instanceof Number) {
            TallyEdit.set(_changed.slot, _field, value);
            _changed.done();
        }
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

class TallyShownDelegate extends WatchUi.Menu2InputDelegate {

    private var _changed as TallyChanged;
    private var _button as TallyButton;

    function initialize(changed as TallyChanged, button as TallyButton) {
        Menu2InputDelegate.initialize();
        _changed = changed;
        _button = button;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        if (item.getId() == TallyEdit.ALWAYS) {
            TallyEdit.set(_changed.slot, "From", TallyButtons.ALWAYS);
            TallyEdit.set(_changed.slot, "Until", 24);
            _changed.done();
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        } else {
            var b = _button;
            var always = b.from == TallyButtons.ALWAYS || b.from % 24 == b.until % 24;
            var picker = new TallyHoursPicker(always ? 7 : b.from, always ? 10 : b.until);
            WatchUi.switchToView(picker, new TallyHoursDelegate(_changed), WatchUi.SLIDE_LEFT);
        }
    }
}

// The hours a button shows: from (0 .. 23), until (1 .. 24); past midnight is fine
class TallyHoursPicker extends WatchUi.Picker {

    function initialize(from as Number, until as Number) {
        var starts = [] as Array<String>;
        var ends = [] as Array<String>;
        for (var h = 0; h < 24; h++) {
            starts.add(TallyAll.hour(h));
            ends.add(TallyAll.hour(h + 1));
        }
        Picker.initialize({:title => new WatchUi.Text({:text => "From – until", :font => Graphics.FONT_SMALL,
                                                       :locX => WatchUi.LAYOUT_HALIGN_CENTER, :locY => WatchUi.LAYOUT_VALIGN_BOTTOM,
                                                       :color => Graphics.COLOR_WHITE}),
                           :pattern => [new TallyChoices(starts), new TallyChoices(ends)],
                           :defaults => [from % 24, (until + 23) % 24]});
    }
}

class TallyHoursDelegate extends WatchUi.PickerDelegate {

    private var _changed as TallyChanged;

    function initialize(changed as TallyChanged) {
        PickerDelegate.initialize();
        _changed = changed;
    }

    function onAccept(values as Array) as Boolean {
        var from = values[0] as Number;
        var until = (values[1] as Number) + 1;
        TallyEdit.set(_changed.slot, "From", (from == until % 24) ? TallyButtons.ALWAYS : from);
        TallyEdit.set(_changed.slot, "Until", until);
        _changed.done();
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    function onCancel() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}

class TallyRemoveDelegate extends WatchUi.Menu2InputDelegate {

    private var _changed as TallyChanged;

    function initialize(changed as TallyChanged) {
        Menu2InputDelegate.initialize();
        _changed = changed;
    }

    // Removed: back past its own menu to the list
    function onSelect(item as WatchUi.MenuItem) as Void {
        if (item.getId() == TallyEdit.SURE) {
            TallyEdit.set(_changed.slot, "Name", "");
            _changed.done();
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
