import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.UserProfile;

// Which routine suits now (designs/DESIGNS.md #20): the cool-down for an
// activity that ended in the last hour; the morning routine from just before
// waking to three hours after; the wind-down from ninety minutes before
// bed; a desk break when the move bar is filling during the day; the full
// session on an afternoon with no activity and none for two days; else the
// quick one. Pure arithmetic in suggest(), fed by the tests; now() reads
// the watch.
(:glance)
module StretchPlan {

    // Why, shown above the routine
    const WHY_MORNING = 0;
    const WHY_EVENING = 1;
    const WHY_DESK = 2;
    const WHY_REST = 3;
    const WHY_QUICK = 4;
    const WHY_AFTER = 5;
    const WHY_TEXT = ["GOOD MORNING", "WIND DOWN", "TIME TO MOVE", "REST DAY", "QUICK STRETCH", "AFTER YOUR "] as Array<String>;

    const AFTER_WINDOW = 3600;
    const DAY = 86400;
    const WAKE_DEFAULT = 7 * 3600;
    const SLEEP_DEFAULT = 22 * 3600 + 1800;
    const MOVE_BAR_DESK = 3;     // of five: about an hour sitting
    const HISTORY_MAX = 100;     // activities looked through, so a long history can't trip the watchdog
    const OWN_WITHIN = 120;      // seconds between a routine's start and its saved activity's

    // [routine, why]. clock, wake and sleep in seconds since midnight; sport
    // the last activity's (or -1) and ago the seconds since it ended; move
    // the move bar (0 to 5); restDays the days since the last full session
    // (99 for never); activeToday whether an activity ended today
    function suggest(clock as Number, wake as Number, sleep as Number, sport as Number, ago as Number,
                     move as Number, restDays as Number, activeToday as Boolean) as Array<Number> {
        if (sport >= 0 && ago >= 0 && ago <= AFTER_WINDOW) {
            var r = after(sport);
            if (r >= 0) {
                return [r, WHY_AFTER] as Array<Number>;
            }
        }
        if (within(clock, wake - 1800, wake + 3 * 3600)) {
            return [StretchRoutines.R_MORNING, WHY_MORNING] as Array<Number>;
        }
        if (within(clock, sleep - 5400, sleep + 3600)) {
            return [StretchRoutines.R_BEDTIME, WHY_EVENING] as Array<Number>;
        }
        var day = within(clock, wake + 3 * 3600, sleep - 5400);
        if (day && move >= MOVE_BAR_DESK) {
            return [StretchRoutines.R_DESK, WHY_DESK] as Array<Number>;
        }
        if (day && clock >= 12 * 3600 && !activeToday && restDays >= 2) {
            return [StretchRoutines.R_FULL, WHY_REST] as Array<Number>;
        }
        return [StretchRoutines.R_QUICK, WHY_QUICK] as Array<Number>;
    }

    // from <= clock < to, round midnight
    function within(clock as Number, from as Number, to as Number) as Boolean {
        var span = ((to - from) % DAY + DAY) % DAY;
        var at = ((clock - from) % DAY + DAY) % DAY;
        return at < span;
    }

    // The cool-down for a sport, or -1
    function after(sport as Number) as Number {
        if (sport == Activity.SPORT_RUNNING || sport == Activity.SPORT_HIKING) {
            return StretchRoutines.R_AFTER_RUN;
        }
        if (sport == Activity.SPORT_CYCLING) {
            return StretchRoutines.R_AFTER_RIDE;
        }
        if (sport == Activity.SPORT_TRAINING) {
            return StretchRoutines.R_AFTER_LIFT;
        }
        return -1;
    }

    // What the activity was, for "AFTER YOUR RUN"
    function sportWord(sport as Number) as String {
        if (sport == Activity.SPORT_RUNNING) {
            return "RUN";
        }
        if (sport == Activity.SPORT_CYCLING) {
            return "RIDE";
        }
        if (sport == Activity.SPORT_HIKING) {
            return "HIKE";
        }
        return "TRAINING";
    }

    // One of this app's own routines, saved as Training: not an activity to cool down from
    function own(start as Number, type as Number, rows as Array<Array<Number> >) as Boolean {
        if (type != Activity.SPORT_TRAINING) {
            return false;
        }
        for (var i = 0; i < rows.size(); i++) {
            var d = rows[i][StretchHistory.UNIX] - start;
            if (d >= -OWN_WITHIN && d <= OWN_WITHIN) {
                return true;
            }
        }
        return false;
    }

    // [routine, why, sport] for this moment on this watch
    function now() as Array<Number> {
        var nowUnix = Time.now().value();
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var clock = info.hour * 3600 + info.min * 60 + info.sec;
        var sport = -1;
        var ago = -1;
        var lastEnd = 0;
        var rows = StretchHistory.rows();
        if (UserProfile has :getUserActivityHistory) {
            try {
                var it = UserProfile.getUserActivityHistory();
                var a = it.next();
                // the newest is not promised to come first: take the latest end
                for (var seen = 0; a != null && seen < HISTORY_MAX; seen++) {
                    var start = a.startTime;
                    var dur = a.duration;
                    var type = a.type;
                    if (start != null && type != null && !own(start.value(), type as Number, rows)) {
                        var end = start.value() + (dur != null ? dur.value() : 0);
                        if (end > lastEnd) {
                            lastEnd = end;
                            sport = type as Number;
                        }
                    }
                    a = it.next();
                }
                if (lastEnd > 0) {
                    ago = nowUnix - lastEnd;
                }
            } catch (e) {
            }
        }
        var wake = WAKE_DEFAULT;
        var sleep = SLEEP_DEFAULT;
        try {
            var p = UserProfile.getProfile();
            if (p.wakeTime != null) {
                wake = (p.wakeTime as Time.Duration).value();
            }
            if (p.sleepTime != null) {
                sleep = (p.sleepTime as Time.Duration).value();
            }
        } catch (e) {
        }
        var move = 0;
        try {
            var am = ActivityMonitor.getInfo();
            if (am.moveBarLevel != null) {
                move = am.moveBarLevel as Number;
            }
        } catch (e) {
        }
        var restDays = 99;
        for (var i = rows.size() - 1; i >= 0; i--) {
            if (rows[i][StretchHistory.ROUTINE] == StretchRoutines.R_FULL) {
                restDays = StretchHistory.day(nowUnix) - StretchHistory.day(rows[i][StretchHistory.UNIX]);
                break;
            }
        }
        var activeToday = lastEnd > nowUnix - clock;
        var s = suggest(clock, wake, sleep, sport, ago, move, restDays, activeToday);
        return [s[0], s[1], sport] as Array<Number>;
    }

    function why(s as Array<Number>) as String {
        if (s[1] == WHY_AFTER && s[2] == Activity.SPORT_TRAINING) {
            return "AFTER TRAINING";   // anything Training: strength, but yoga too
        }
        return s[1] == WHY_AFTER ? WHY_TEXT[WHY_AFTER] + sportWord(s[2]) : WHY_TEXT[s[1]];
    }

    // "8 min" at the current level
    function minutes(routine as Number) as String {
        var sec = StretchRoutines.SECONDS[routine][StretchSettings.levelIndex()];
        return ((sec + 30) / 60) + " min";
    }
}
