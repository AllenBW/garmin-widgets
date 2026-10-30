import Toybox.Application.Storage;
import Toybox.Lang;

// The last visits, kept on the watch as one row of numbers per visit so
// the glance can show the most recent one without the app.
(:glance)
module SaunaHistory {
    const KEY = "visits";
    const MAX = 30;
    const STRIDE = 7;

    // Columns of a row
    const START = 0;       // unix seconds the visit began
    const ROUNDS = 1;
    const SAUNA_SEC = 2;   // seconds in the heat, all rounds
    const BREAK_SEC = 3;   // seconds out between and after rounds
    const MAX_HR = 4;      // beats per minute in the heat; 0 when none was read
    const DROP = 5;        // average fall a minute after each round's peak; -1 when none
    const MAX_TEMP = 6;    // the watch's hottest reading in tenths of a degree C; -1000 when none

    function all() as Array<Number> {
        var value = Storage.getValue(KEY);
        if (value instanceof Array) {
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
}
