import Toybox.Lang;

// Noir's arithmetic, apart from any drawing so the tests can feed it: the
// hands' angles, where the date and the look's name go, and how a hand
// sweeps from one angle to another. designs/preview_noir.py does the same
// sums.
module Dial {

    // The hands' angles, degrees clockwise from twelve: [hour, minute]
    function angles(hour as Number, minute as Number) as Array<Float> {
        return [(hour % 12 + minute / 60.0) * 30.0, minute * 6.0] as Array<Float>;
    }

    // How far apart two angles are, 0 to 180
    function apart(a as Float, b as Float) as Float {
        var d = (a - b).abs();
        while (d >= 360.0) {
            d -= 360.0;
        }
        return (d > 180.0) ? 360.0 - d : d;
    }

    // Where the date goes: 0 at three o'clock, 1 at nine, 2 at six, the
    // first that neither hand is near. Two hands can't take all three.
    function datePlace(hourDeg as Float, minuteDeg as Float) as Number {
        var at = [90.0, 270.0, 180.0] as Array<Float>;
        for (var i = 0; i < 3; i++) {
            if (apart(hourDeg, at[i]) > Layout.BLOCK && apart(minuteDeg, at[i]) > Layout.BLOCK) {
                return i;
            }
        }
        return 2;
    }

    // The look's name sits below the centre unless the minute hand does
    function titleBelow(minuteDeg as Float) as Boolean {
        return apart(minuteDeg, 180.0) > 90.0;
    }

    // The shorter way round from one angle to another: -180 to 180 degrees,
    // clockwise positive, 0 for a hand that hasn't moved
    function turn(from as Float, to as Float) as Float {
        var d = to - from;
        while (d > 180.0) {
            d -= 360.0;
        }
        while (d <= -180.0) {
            d += 360.0;
        }
        return d;
    }

    // How long a hand takes to sweep `turn` degrees on a wake, in ms: a
    // little longer the further it goes, well under a second at the most
    // (Lib.Motion's push, 70 ms, comes before it)
    function sweepMs(turn as Float) as Number {
        return Layout.SWEEP + (Layout.SWEEP_FAR * turn.abs() / 180.0).toNumber();
    }

    // Whether a sweep taking `dur` ms is still under way `t` ms after it began
    function sweeping(t as Number, dur as Number) as Boolean {
        return t < Lib.Motion.PUSH + dur;
    }

    // Where a hand is `t` ms into a sweep from `from` to `to` taking `dur`
    // ms: eased, slow out and slow in (Lib.Motion.ease with no bounce), the
    // shorter way round; `from` itself for a hand that hasn't moved, and
    // `to` exactly once the sweep is over
    function swept(from as Float, to as Float, t as Number, dur as Number) as Float {
        var d = turn(from, to);
        if (d == 0.0 || !sweeping(t, dur)) {
            return to;
        }
        return from + d * Lib.Motion.ease(t, dur, false, 0.0);
    }
}
