import Toybox.Lang;
import Toybox.Math;

// Heart-rate variability from the watch's beat-to-beat intervals: RMSSD,
// the root mean square of successive differences, over about a minute.
// The research signal for heat: it falls in the heat, rises as you cool
// and settles after half an hour. Logged, not coached on, for now.
module SaunaHrv {

    // RMSSD in ms over consecutive intervals; null with fewer than ten
    function rmssd(intervals as Array<Number>) as Number? {
        var w = new HrvWindow();
        w.add(intervals);
        return w.value();
    }
}

// Accumulates intervals as they arrive; value() reads the window, reset()
// starts the next one but remembers the last beat so the chain continues
class HrvWindow {
    const MIN_BEATS = 10;
    const SHORTEST = 300;    // ms: anything outside this range is an artefact, and breaks the chain
    const LONGEST = 2000;

    private var _last as Number? = null;
    private var _sumSq as Float = 0.0;
    private var _n as Number = 0;

    function initialize() {
    }

    function add(intervals as Array<Number>) as Void {
        for (var i = 0; i < intervals.size(); i++) {
            var v = intervals[i];
            if (v < SHORTEST || v > LONGEST) {
                _last = null;
                continue;
            }
            var last = _last;
            if (last != null) {
                var d = (v - last).toFloat();
                _sumSq += d * d;
                _n += 1;
            }
            _last = v;
        }
    }

    function beats() as Number {
        return _n;
    }

    function value() as Number? {
        if (_n < MIN_BEATS) {
            return null;
        }
        return Math.sqrt(_sumSq / _n).toNumber();
    }

    function reset() as Void {
        _sumSq = 0.0;
        _n = 0;
    }
}
