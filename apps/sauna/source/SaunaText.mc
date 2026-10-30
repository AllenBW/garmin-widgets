import Toybox.Lang;
import Toybox.Time;

// Words and numbers for the glance and the screens
(:glance)
module SaunaText {

    // Seconds -> "12:34", or "1:02:34" past an hour
    function clock(seconds as Number) as String {
        if (seconds < 0) {
            seconds = 0;
        }
        var h = seconds / 3600;
        var m = (seconds / 60) % 60;
        var s = seconds % 60;
        if (h > 0) {
            return h.toString() + ":" + m.format("%02d") + ":" + s.format("%02d");
        }
        return m.toString() + ":" + s.format("%02d");
    }

    // Seconds -> "38 min", or "1 h 05" past an hour
    function minutes(seconds as Number) as String {
        var m = (seconds + 30) / 60;
        if (m < 60) {
            return m.toString() + " min";
        }
        return (m / 60).toString() + " h " + (m % 60).format("%02d");
    }

    function rounds(n as Number) as String {
        return n == 1 ? "1 round" : n.toString() + " rounds";
    }

    // A fall in heart rate -> "-28", or "--" when it was not measured
    function drop(bpm as Number?) as String {
        if (bpm == null) {
            return "--";
        }
        return (bpm >= 0 ? "-" : "+") + bpm.abs().toString();
    }

    // Tenths of a degree from a history row -> "48°", or "" when none
    function tenths(value as Number) as String {
        return value <= -1000 ? "" : Lib.Fmt.temperature(value / 10.0);
    }

    // The glance headline from a history row: "3 rounds · 38 min"
    function headline(row as Array<Number>?) as String {
        if (row == null) {
            return "No visits yet";
        }
        return rounds(row[SaunaHistory.ROUNDS]) + " · " + minutes(row[SaunaHistory.SAUNA_SEC]);
    }

    // The glance detail: "Tue 28 Oct · max 142 bpm · -31 in 1 min"
    function detail(row as Array<Number>?) as String {
        if (row == null) {
            return "START records a visit";
        }
        var s = Lib.Fmt.shortDate(new Time.Moment(row[SaunaHistory.START]));
        if (row[SaunaHistory.MAX_HR] > 0) {
            s += " · max " + row[SaunaHistory.MAX_HR] + " bpm";
        }
        if (row[SaunaHistory.DROP] >= 0) {
            s += " · " + drop(row[SaunaHistory.DROP]) + " in 1 min";
        }
        return s;
    }
}
