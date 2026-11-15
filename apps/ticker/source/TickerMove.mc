import Toybox.Lang;

// One move of Ticker's tapes, from what was last seen to what is now: pure
// arithmetic on the ms since it began (`t`, which only drawn frames advance).
// The timings are the approved sketch's. The minute tape steps through every
// minute between, in 450 ms and 120 ms more a minute, with Lib.Motion's
// in-and-out ease and a bounce of an eighth of a minute. Each thin tape turns
// to the first of its readings that changed (the top from 150 ms over 550,
// the bottom from 250 ms over 600); then that reading's changed digits slide
// in their own slots, units first, 60 ms apart, each falling into place in
// 360 ms (from 750 and 850 ms, or from when the turn would have begun if the
// tape had no need to turn).
class TickerMove {

    const MINUTE = 450;            // ms a step of one minute takes
    const PER_MINUTE = 120;        // ms each further minute adds
    const MINUTE_BOUNCE = 0.12;    // of a minute's pitch, whatever the run
    const TURN_BOUNCE = 0.1;       // of the turn
    const SLIDE = 360;             // ms a digit takes to fall into its slot
    const SLIDE_BOUNCE = 0.05;
    const LAG = 60;                // ms between one digit's slide and the next to its left

    // [top, bottom]
    const TURN_AT = [150, 250] as Array<Number>;
    const TURN = [550, 600] as Array<Number>;
    const SLIDE_AT = [750, 850] as Array<Number>;

    var t as Number = 0;
    var from as Array<String>;     // the readings last seen
    var to as Array<String>;       // and now
    var minuteFrom as Number;      // the minute the run starts from (minutes since midnight, may be below 0)
    var steps as Number;           // minutes it runs through
    var tape0 as Array<Number>;    // each thin tape's centre reading before, [top, bottom], as an index into its readings
    var tape1 as Array<Number>;    // and after (below 0 or past the end: the turn goes round the short way)
    var slideAt as Array<Number>;  // ms each thin tape's slides begin
    var ends as Array<Number>;     // ms each band settles: [top tape, time, bottom tape]; 0 for one that doesn't move
    var live as Array<Boolean>;    // bands still to be drawn moving

    // `slides`: per thin tape, the most digits that change in any one of its readings
    function initialize(from_ as Array<String>, to_ as Array<String>, minuteFrom_ as Number, steps_ as Number,
                        tape0_ as Array<Number>, tape1_ as Array<Number>, slides as Array<Number>) {
        from = from_;
        to = to_;
        minuteFrom = minuteFrom_;
        steps = steps_;
        tape0 = tape0_;
        tape1 = tape1_;
        slideAt = [0, 0] as Array<Number>;
        ends = [0, 0, 0] as Array<Number>;
        live = [false, false, false] as Array<Boolean>;
        if (steps > 0) {
            ends[1] = Lib.Motion.PUSH + minuteDur() + Lib.Motion.SETTLE;
        }
        for (var i = 0; i < 2; i++) {
            var turned = tape0[i] != tape1[i];
            var end = turned ? TURN_AT[i] + Lib.Motion.PUSH + TURN[i] + Lib.Motion.SETTLE : 0;
            slideAt[i] = turned ? SLIDE_AT[i] : TURN_AT[i];
            if (slides[i] > 0) {
                var last = slideAt[i] + (slides[i] - 1) * LAG + Lib.Motion.PUSH + SLIDE + Lib.Motion.SETTLE;
                end = (last > end) ? last : end;
            }
            ends[i * 2] = end;
        }
        for (var b = 0; b < 3; b++) {
            live[b] = ends[b] > 0;
        }
    }

    private function minuteDur() as Number {
        return MINUTE + PER_MINUTE * steps;
    }

    // Where the minute tape is, in minutes: from `minuteFrom` to `minuteFrom + steps`
    function minutePos() as Float {
        if (steps == 0) {
            return minuteFrom.toFloat();
        }
        return minuteFrom + steps * Lib.Motion.ease(t, minuteDur(), false, MINUTE_BOUNCE / steps);
    }

    // Where thin tape i is, in readings
    function tapePos(i as Number) as Float {
        var a = tape0[i];
        var b = tape1[i];
        if (a == b) {
            return a.toFloat();
        }
        return a + (b - a) * Lib.Motion.ease(t - TURN_AT[i], TURN[i], false, TURN_BOUNCE);
    }

    // How far a digit on thin tape i has slid into its slot (0 the old digit
    // in place, 1 the new), `right` the changed digits to its right
    function slide(i as Number, right as Number) as Float {
        return Lib.Motion.ease(t - slideAt[i] - right * LAG, SLIDE, true, SLIDE_BOUNCE);
    }

    function end() as Number {
        var most = 0;
        for (var b = 0; b < 3; b++) {
            most = (ends[b] > most) ? ends[b] : most;
        }
        return most;
    }

    function done() as Boolean {
        return t >= end();
    }
}
