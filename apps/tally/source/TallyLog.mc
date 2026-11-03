import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;

// Every tap, kept in the object store: its time and its button's name.
// Entries are numbered from 0 in the order they were logged. They live in
// chunks of CHUNK (a stored value may not pass 32 KB), each a flat array
// [time, name index, time, name index, ...], and the newest KEEP chunks stay
// on the watch; the sheet keeps everything. Names go in a table that only
// grows, so a renamed button keeps its old entries under the old name.
//
// Loaded in the background service too (it sends what the sheet hasn't
// confirmed), so nothing here uses Lib.
(:background, :glance)
module TallyLog {

    const CHUNK = 500;
    const KEEP = 12;            // 6,000 entries on the watch

    const NAMES = "names";      // Array<String>
    const COUNT = "count";      // entries ever logged: the next entry's number
    const SENT = "sent";        // entries the sheet has confirmed
    const ID = "id";            // this install, so the sheet can tell watches apart
    const LAST = "last";        // the glance's line: [time, name, colour, days running]

    function count() as Number {
        var n = Storage.getValue(COUNT);
        return (n instanceof Number) ? n : 0;
    }

    function sent() as Number {
        var n = Storage.getValue(SENT);
        return (n instanceof Number) ? n : 0;
    }

    // The oldest entry still on the watch
    function first() as Number {
        var c = (count() - 1) / CHUNK - KEEP + 1;
        return (c > 0) ? c * CHUNK : 0;
    }

    function names() as Array<String> {
        var v = Storage.getValue(NAMES);
        return (v instanceof Array) ? v as Array<String> : [] as Array<String>;
    }

    function chunk(c as Number) as Array<Number> {
        var v = Storage.getValue("c" + c);
        return (v instanceof Array) ? v as Array<Number> : [] as Array<Number>;
    }

    // Log `name` at `time`; returns the entry's number
    function add(time as Number, name as String) as Number {
        var table = names();
        var index = table.indexOf(name);
        if (index < 0) {
            table.add(name);
            Storage.setValue(NAMES, table as Array<Storage.ValueType>);
            index = table.size() - 1;
        }
        var n = count();
        var c = n / CHUNK;
        var items = (n % CHUNK == 0) ? [] as Array<Number> : chunk(c);
        items.add(time);
        items.add(index);
        Storage.setValue("c" + c, items as Array<Storage.ValueType>);
        Storage.setValue(COUNT, n + 1);
        if (c - KEEP >= 0) {
            Storage.deleteValue("c" + (c - KEEP));
        }
        return n;
    }

    // Take back the newest entry, unless the sheet already has it
    function undo() as Boolean {
        var n = count();
        if (n == 0 || n <= sent()) {
            return false;
        }
        n -= 1;
        var c = n / CHUNK;
        var items = chunk(c);
        if (items.size() >= 2) {
            items = items.slice(0, items.size() - 2);
        }
        if (items.size() == 0) {
            Storage.deleteValue("c" + c);
        } else {
            Storage.setValue("c" + c, items as Array<Storage.ValueType>);
        }
        Storage.setValue(COUNT, n);
        return true;
    }

    // Entries logged at or after `since`, oldest first: [times, name indexes]
    function since(since as Number) as [Array<Number>, Array<Number>] {
        var times = [] as Array<Number>;
        var which = [] as Array<Number>;
        var n = count();
        if (n == 0) {
            return [times, which];
        }
        var lo = first() / CHUNK;
        var parts = [] as Array<Array<Number>>;
        for (var c = (n - 1) / CHUNK; c >= lo; c--) {
            var items = chunk(c);
            parts.add(items);
            if (items.size() > 0 && items[0] < since) {
                break;
            }
        }
        for (var p = parts.size() - 1; p >= 0; p--) {
            var items = parts[p];
            for (var i = 0; i + 1 < items.size(); i += 2) {
                if (items[i] >= since) {
                    times.add(items[i]);
                    which.add(items[i + 1]);
                }
            }
        }
        return [times, which];
    }

    // Up to `max` entries from the first the sheet hasn't confirmed, logged
    // before `before` (so an entry can still be undone while it settles):
    // [number of the first, times, names], or null when there are none
    function unsent(max as Number, before as Number) as [Number, Array<Number>, Array<String>]? {
        var from = sent();
        if (from < first()) {
            from = first();     // dropped from the watch before it could be sent
        }
        var n = count();
        var table = names();
        var times = [] as Array<Number>;
        var labels = [] as Array<String>;
        var c = -1;
        var items = [] as Array<Number>;
        for (var e = from; e < n && times.size() < max; e++) {
            if (e / CHUNK != c) {
                c = e / CHUNK;
                items = chunk(c);
            }
            var i = (e % CHUNK) * 2;
            if (i + 1 >= items.size() || items[i] >= before) {
                break;
            }
            times.add(items[i]);
            labels.add(table[items[i + 1]]);
        }
        return (times.size() == 0) ? null : [from, times, labels];
    }

    // The sheet holds every entry before `next`
    function confirm(next as Number) as Void {
        if (next > sent() && next <= count()) {
            Storage.setValue(SENT, next);
        }
    }

    function installId() as String {
        var id = Storage.getValue(ID);
        if (id instanceof String) {
            return id;
        }
        Math.srand(Time.now().value());
        id = "";
        for (var i = 0; i < 8; i++) {
            var k = Math.rand() % 16;
            id += "0123456789abcdef".substring(k, k + 1);
        }
        Storage.setValue(ID, id);
        return id;
    }
}
