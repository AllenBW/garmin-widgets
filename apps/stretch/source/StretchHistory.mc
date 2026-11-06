import Toybox.Application;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

// Finished sessions on the watch, newest last: [unix, routine, seconds,
// complete]. Thirty kept. The streak counts days in a row with any
// stretching, today or yesterday back.
(:glance)
module StretchHistory {

    const KEY = "h";
    const KEEP = 30;
    const UNIX = 0;
    const ROUTINE = 1;
    const SECONDS = 2;
    const COMPLETE = 3;

    function rows() as Array<Array<Number> > {
        var v = Application.Storage.getValue(KEY);
        var good = [] as Array<Array<Number> >;
        if (v instanceof Array) {
            // a row no version of the app would read is left out, never a crash on every open
            for (var i = 0; i < v.size(); i++) {
                var row = v[i];
                if (row instanceof Array && row.size() > COMPLETE && row[UNIX] instanceof Number
                    && row[ROUTINE] instanceof Number && row[SECONDS] instanceof Number) {
                    good.add(row as Array<Number>);
                }
            }
        }
        return good;
    }

    function add(unix as Number, routine as Number, seconds as Number, complete as Boolean) as Void {
        var r = rows();
        r.add([unix, routine, seconds, complete ? 1 : 0] as Array<Number>);
        if (r.size() > KEEP) {
            r = r.slice(r.size() - KEEP, null);
        }
        Application.Storage.setValue(KEY, r as Array<Application.Storage.ValueType>);
    }

    function clear() as Void {
        Application.Storage.deleteValue(KEY);
    }

    // Local day number of a moment, for counting days in a row
    function day(unix as Number) as Number {
        var info = Gregorian.info(new Time.Moment(unix), Time.FORMAT_SHORT);
        // moment() reads the fields as UTC, so this is the local date's own day number
        var midnight = Gregorian.moment({:year => info.year, :month => info.month as Number, :day => info.day,
                                         :hour => 0, :minute => 0, :second => 0});
        return midnight.value() / 86400;
    }

    // Days in a row up to today, or up to yesterday when today has none yet
    function streak(now as Number, r as Array<Array<Number> >) as Number {
        var today = day(now);
        var days = {} as Dictionary<Number, Boolean>;
        for (var i = 0; i < r.size(); i++) {
            days[day(r[i][UNIX])] = true;
        }
        var d = days.hasKey(today) ? today : today - 1;
        var n = 0;
        while (days.hasKey(d)) {
            n++;
            d--;
        }
        return n;
    }

    // Three sessions or more in each of the last two weeks, below the deepest
    // level: time to hold longer
    function readyForMore(now as Number, r as Array<Array<Number> >, level as Number) as Boolean {
        if (level >= 2) {
            return false;
        }
        var today = day(now);
        var thisWeek = 0;
        var lastWeek = 0;
        for (var i = 0; i < r.size(); i++) {
            var d = today - day(r[i][UNIX]);
            if (d >= 0 && d < 7) {
                thisWeek++;
            } else if (d >= 7 && d < 14) {
                lastWeek++;
            }
        }
        return thisWeek >= 3 && lastWeek >= 3;
    }

    // Sessions in the last seven days, today included
    function week(now as Number, r as Array<Array<Number> >) as Number {
        var from = day(now) - 6;
        var n = 0;
        for (var i = 0; i < r.size(); i++) {
            if (day(r[i][UNIX]) >= from) {
                n++;
            }
        }
        return n;
    }
}
