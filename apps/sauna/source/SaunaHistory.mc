import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

// The last visits, kept on the watch as one row of numbers per visit so
// the glance can show the most recent one and this week's count without
// the app.
(:glance)
module SaunaHistory {
    const KEY = "visits";
    const MAX = 30;
    const STRIDE = 10;

    // Columns of a row
    const START = 0;       // unix seconds the visit began
    const KIND = 1;        // KIND_SAUNA or KIND_STEAM
    const ROUNDS = 2;
    const SAUNA_SEC = 3;   // seconds in the heat, all rounds
    const BREAK_SEC = 4;   // seconds out between and after rounds
    const MAX_HR = 5;      // beats per minute in the heat; 0 when none was read
    const DROP = 6;        // average fall a minute after each round's peak; -1 when none
    const MAX_TEMP = 7;    // the watch's hottest reading in tenths of a degree C; -1000 when none
    const BB_START = 8;    // Body Battery when the visit began; -1 when unknown
    const BB_END = 9;      // and when it was saved

    function all() as Array<Number> {
        var value = Storage.getValue(KEY);
        if (value instanceof Array && value.size() % STRIDE == 0) {
            return value as Array<Number>;
        }
        return [] as Array<Number>;
    }

    function count() as Number {
        return all().size() / STRIDE;
    }

    // Visit i, where 0 is the most recent; null past the end
    function visit(i as Number) as Array<Number>? {
        var rows = all();
        var n = rows.size() / STRIDE;
        if (i < 0 || i >= n) {
            return null;
        }
        var at = (n - 1 - i) * STRIDE;
        return rows.slice(at, at + STRIDE);
    }

    function last() as Array<Number>? {
        return visit(0);
    }

    // The most recent visit of one kind
    function lastOf(kind as Number) as Array<Number>? {
        var n = count();
        for (var i = 0; i < n; i++) {
            var row = visit(i) as Array<Number>;
            if (row[KIND] == kind) {
                return row;
            }
        }
        return null;
    }

    // Append a row, dropping the oldest beyond MAX
    function add(row as Array<Number>) as Void {
        var rows = all();
        var n = rows.size() / STRIDE;
        if (n >= MAX) {
            rows = rows.slice((n - MAX + 1) * STRIDE, null);
        }
        rows.addAll(row);
        Storage.setValue(KEY, rows as Array<Storage.ValueType>);
    }

    function clear() as Void {
        Storage.deleteValue(KEY);
    }

    // The usual one-minute fall for one kind, over the visits that measured one
    function avgDrop(kind as Number) as Number? {
        var rows = all();
        var sum = 0;
        var n = 0;
        for (var at = 0; at < rows.size(); at += STRIDE) {
            if (rows[at + KIND] == kind && rows[at + DROP] >= 0) {
                sum += rows[at + DROP];
                n += 1;
            }
        }
        return n > 0 ? sum / n : null;
    }

    // Visits of one kind (or any, with -1) since a moment: [sessions, seconds of heat]
    function since(kind as Number, unix as Number) as Array<Number> {
        var rows = all();
        var sessions = 0;
        var heat = 0;
        for (var at = 0; at < rows.size(); at += STRIDE) {
            if (rows[at + START] >= unix && (kind < 0 || rows[at + KIND] == kind)) {
                sessions += 1;
                heat += rows[at + SAUNA_SEC];
            }
        }
        return [sessions, heat] as Array<Number>;
    }

    // Local midnight at the start of this week, following the watch's first day of the week
    function weekStart() as Number {
        var today = Time.today();
        var info = Gregorian.info(today, Time.FORMAT_SHORT);
        var dow = info.day_of_week;
        var first = System.getDeviceSettings().firstDayOfWeek;
        var back = 0;
        if (dow instanceof Number) {
            back = (dow - first + 7) % 7;
        }
        return today.value() - back * 86400;
    }

    function thisWeek(kind as Number) as Array<Number> {
        return since(kind, weekStart());
    }
}
