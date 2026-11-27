import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

module Lib {

    // A face's settings on the watch itself (AppBase.getSettingsView), for
    // every watch, not only those with the fēnix 8's watch face editor: the
    // phone app's list as a menu, each setting with its choice under its
    // name, and a list of the choices behind each. A choice writes the very
    // property the phone app does, then calls the app's onSettingsChanged,
    // so a choice made on the watch is one made on the phone: it wins over
    // the editor until the editor is used again (Lib.Config, Lib.Neon). The
    // look comes first, as on the phone, and choosing one is a hold on the
    // face (Lib.Look). Uses Look, so a face links that too.
    (:watchmenu)
    module WatchMenu {

        // A setting: [its title, its property (null for the look), the
        // choices' labels, the choices' values (numbers, or true and false
        // for a switch)]
        typedef Entry as [String, String?, Array<String>, Array<Number> or Array<Boolean>];

        // The menu and its delegate, for getSettingsView
        function view(title as String, entries as Array<Entry>) as [WatchUi.Views, WatchUi.InputDelegates] {
            var menu = new WatchUi.Menu2({:title => title});
            for (var i = 0; i < entries.size(); i++) {
                menu.addItem(new WatchUi.MenuItem(entries[i][0], label(entries[i]), i, null));
            }
            return [menu, new Menu(entries)];
        }

        // Where the setting stands: the place of its value among the
        // choices (the first when unset or out of range)
        function current(entry as Entry) as Number {
            var key = entry[1];
            var value = null;
            try {
                value = (key == null) ? Look.mode() : Application.Properties.getValue(key);
            } catch (e) {
                value = null;
            }
            var values = entry[3];
            for (var i = 0; i < values.size(); i++) {
                if (same(values[i], value)) {
                    return i;
                }
            }
            return 0;
        }

        // Whether a property's value is a choice's: a number the same
        // number, a switch the same way
        function same(choice as Number or Boolean, value as Object?) as Boolean {
            if (choice instanceof Number) {
                return (value instanceof Number) && choice == value;
            }
            return (value instanceof Boolean) && choice == value;
        }

        function label(entry as Entry) as String {
            return entry[2][current(entry)];
        }

        // Take the choice at `index`: the look as a hold takes it, any other
        // setting as the phone app writes it; then the app takes it up
        function choose(entry as Entry, index as Number) as Void {
            var key = entry[1];
            var value = entry[3][index];
            if (key == null) {
                Application.Storage.setValue(Look.KEY, value);
            } else {
                Application.Properties.setValue(key, value);
            }
            Application.getApp().onSettingsChanged();
        }

        // The settings menu: a setting opens the list of its choices
        class Menu extends WatchUi.Menu2InputDelegate {

            private var _entries as Array<Entry>;

            function initialize(entries as Array<Entry>) {
                Menu2InputDelegate.initialize();
                _entries = entries;
            }

            function onSelect(item as WatchUi.MenuItem) as Void {
                var entry = _entries[item.getId() as Number];
                var list = new WatchUi.Menu2({:title => entry[0], :focus => current(entry)});
                for (var i = 0; i < entry[2].size(); i++) {
                    list.addItem(new WatchUi.MenuItem(entry[2][i], null, i, null));
                }
                WatchUi.pushView(list, new Choices(entry, item), WatchUi.SLIDE_LEFT);
            }
        }

        // A setting's choices: picking one takes it and goes back to the menu,
        // the setting's line there showing the new choice
        class Choices extends WatchUi.Menu2InputDelegate {

            private var _entry as Entry;
            private var _line as WatchUi.MenuItem;

            function initialize(entry as Entry, line as WatchUi.MenuItem) {
                Menu2InputDelegate.initialize();
                _entry = entry;
                _line = line;
            }

            function onSelect(item as WatchUi.MenuItem) as Void {
                choose(_entry, item.getId() as Number);
                _line.setSubLabel(label(_entry));
                WatchUi.popView(WatchUi.SLIDE_RIGHT);
            }
        }
    }
}
