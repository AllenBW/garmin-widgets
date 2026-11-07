import Toybox.Lang;
import Toybox.Math;

// The roll, as the owner approved it on the states page (designs/DESIGNS.md
// #20, designs/clack/README.md §9): pure arithmetic fed by ClackView and the
// tests. A leaf's flip is a push off the stop (slow, slightly accelerating,
// to the release angle) and then a drop from the tables Drops.mc holds, the
// fall under gravity against the air and the leaf beneath, the bounce at the
// stop (designs/gen_clack.py from preview_clack.roll_profile). The timing of
// a minute: the units leaf's push ends on the minute, the tens leaf takes the
// same push two frames behind, the hour leaves start a beat after the minutes
// slip. A wake rolls every missed minute up to four, else straight to now.
module Roll {

    const FPS = 20;                              // frames a second, what the simulator holds (pitfalls.md)
    const CREEP_LO = 0.6;                        // the push, seconds
    const CREEP_HI = 1.4;
    const CATCHUP_LO = 0.1;                      // a catch-up push: the leaf is already off its stop
    const CATCHUP_HI = 0.25;
    const HOUR_CREEP = 0.3;                      // the hour leaves' push
    const HOUR_CATCHUP = 0.25;
    const BEAT_LO = 6;                           // frames after the minutes slip before the hour leaves start
    const BEAT_HI = 10;
    const TENS_LAG = 2;                          // frames the tens leaf starts behind the units
    const MOST_STEPS = 4;                        // missed minutes rolled one by one, else straight to now
    const HOLD = 3;                              // frames of rest between catch-up steps
    const MINUTES = 1440;

    // One leaf mid-flip: from one digit to the next along `angles` (degrees,
    // 0 up, 180 down, one per frame), frame k, negative before it starts
    class Flip {
        var from as String;
        var to as String;
        var angles as Array<Float>;
        var k as Number;

        function initialize(from as String, to as String, angles as Array<Float>, delay as Number) {
            self.from = from;
            self.to = to;
            self.angles = angles;
            k = -delay;
        }

        // The flap's angle this frame: 0 while the flip waits for its start
        function angle() as Float {
            if (k < 0) {
                return 0.0;
            }
            return angles[(k < angles.size()) ? k : angles.size() - 1];
        }

        function done() as Boolean {
            return k >= angles.size();
        }
    }

    // A flip's angles per frame: the push over `creep` seconds to the drop
    // table's release angle, then the table's fall
    function profile(creep as Float, table as Array<Float>) as Array<Float> {
        var release = table[0];
        var n = pushFrames(creep);
        var out = [] as Array<Float>;
        for (var k = 0; k < n; k++) {
            out.add(release * Math.pow((k + 1).toFloat() / n, 1.3).toFloat());
        }
        for (var i = 1; i < table.size(); i++) {
            out.add(table[i]);
        }
        return out;
    }

    // The frames a push takes, one at least
    function pushFrames(creep as Float) as Number {
        var n = Math.round(creep * FPS).toNumber();
        return (n < 1) ? 1 : n;
    }

    // A drop table, picked at random
    function table() as Array<Float> {
        return Drops.TABLES[(Math.rand() % Drops.COUNT).abs()];
    }

    // A number between lo and hi
    function between(lo as Float, hi as Float) as Float {
        return lo + (hi - lo) * ((Math.rand() % 10000).abs() / 10000.0);
    }

    // The minutes of the day to roll through from the one shown to now:
    // each of them when at most MOST_STEPS passed, else now alone; none
    // when nothing passed
    function steps(shown as Number, now as Number) as Array<Number> {
        var d = now - shown;
        if (d < -720) {
            d += MINUTES;                        // across midnight; a minute behind is a step armed ahead of the clock
        }
        var out = [] as Array<Number>;
        if (d <= 0) {
            return out;
        }
        if (d > MOST_STEPS) {
            out.add(now);
            return out;
        }
        for (var k = 1; k <= d; k++) {
            out.add((shown + k) % MINUTES);
        }
        return out;
    }

    // The four leaves' digits for a minute of the day: hour tens, hour
    // units, minute tens, minute units; a blank hour tens leaf for a
    // one-digit 12-hour hour
    function digits(minute as Number, is24 as Boolean) as Array<String> {
        var m = ((minute % MINUTES) + MINUTES) % MINUTES;
        var hour = m / 60;
        var min = m % 60;
        var tens = "";
        if (!is24) {
            hour = hour % 12;
            hour = (hour == 0) ? 12 : hour;
            if (hour >= 10) {
                tens = "1";
            }
        } else {
            tens = (hour / 10).toString();
        }
        return [tens, (hour % 10).toString(), (min / 10).toString(), (min % 10).toString()] as Array<String>;
    }

    // The flag under or on the hour leaves in 12-hour mode: "AM", "PM", or
    // nothing in 24-hour mode
    function flag(minute as Number, is24 as Boolean) as String {
        if (is24) {
            return "";
        }
        var m = ((minute % MINUTES) + MINUTES) % MINUTES;
        return (m >= 720) ? "PM" : "AM";
    }
}
