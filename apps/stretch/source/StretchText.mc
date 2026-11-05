import Toybox.Lang;

// Words shared by the glance and the app
(:glance)
module StretchText {

    // "3-day streak · 5 this week", or a nudge when there is none
    function streakLine(now as Number) as String {
        var r = StretchHistory.rows();
        var streak = StretchHistory.streak(now, r);
        var week = StretchHistory.week(now, r);
        if (week == 0) {
            return "No stretching this week yet";
        }
        var w = week + " this week";
        if (streak >= 2) {
            return streak + "-day streak · " + w;
        }
        return w;
    }

    // 462000 ms as "7:42"
    function clock(ms as Number) as String {
        var s = (ms + 999) / 1000;
        if (s < 0) {
            s = 0;
        }
        return (s / 60) + ":" + (s % 60).format("%02d");
    }

    function stretches(n as Number) as String {
        return n == 1 ? "1 stretch" : n + " stretches";
    }
}
