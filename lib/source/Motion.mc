import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

module Lib {

    // How a number arrives on the faces that move: Clack's mechanism, a push
    // off the stop, the move and a bounce that dies away (ease), and the
    // frames' clock that Clack's logs on the fēnix 8 taught (Pacer). Shared by
    // Ticker, Shuttle and Orb, which move only what changed since last seen.
    (:motion)
    module Motion {

        const PUSH = 70;           // ms the push off the stop takes, backwards a little
        const SETTLE = 500;        // ms the bounce takes to die away after the move
        const BACK = 0.025;        // how far back the push goes, as a share of the move

        // The share of the way from 0 to 1, `t` ms after the start of a move
        // taking `dur` ms: a little below 0 during the push, then falling
        // (accelerating, `fall`) or easing in and out, then a bounce of
        // `amp` off the stop that dies away
        function ease(t as Number, dur as Number, fall as Boolean, amp as Float) as Float {
            if (t <= 0) {
                return 0.0;
            }
            if (t < PUSH) {
                return (-BACK * Math.sin(Math.PI * t / PUSH)).toFloat();
            }
            var x = (t - PUSH).toFloat() / dur;
            if (x < 1.0) {
                if (fall) {
                    return x * x;
                }
                if (x < 0.5) {
                    return 4.0 * x * x * x;
                }
                var e = 2.0 - 2.0 * x;
                return 1.0 - e * e * e / 2.0;
            }
            var y = (t - PUSH - dur) / 1000.0;
            if (y * 1000.0 >= SETTLE) {
                return 1.0;
            }
            return (1.0 - amp * Math.pow(Math.E, -y * 10.0) * (Math.sin(y * Math.PI / 0.12)).abs()).toFloat();
        }

        // Whether a move of `dur` ms has settled `t` ms after its start
        function done(t as Number, dur as Number) as Boolean {
            return t >= PUSH + dur + SETTLE;
        }

        // The frames' clock and timer. Timer.start kills a watch face in low
        // power mode, and the watch shows a face in low power mode too, so the
        // timer runs only once a wake (onExitSleep) or the system's
        // once-a-second updates have shown the face awake. Motion moves only
        // by drawn frames: after a wake the watch draws nothing for a moment,
        // and a move run on the clock alone goes by unseen, so `step` gives
        // the time since the last drawn frame, at most `most` frames' worth
        // (a stall skips motion rather than stretching it).
        class Pacer {
            const QUICK = 1500;        // ms: an update this soon after the last is the once-a-second one
            const QUICK_RUN = 2;       // quick gaps in a row that prove high power mode
            const ASLEEP_GAP = 5000;   // ms without an update: low power mode, when nothing has said otherwise

            var awake as Boolean = true;
            private var _known as Boolean = false;
            private var _proven as Boolean = false;
            private var _period as Number;
            private var _most as Number;
            private var _timer as Timer.Timer? = null;
            private var _running as Boolean = false;
            private var _still as Boolean = false;
            private var _lastUpdate as Number = 0;
            private var _quick as Number = 0;
            private var _lastFrame as Number = 0;

            function initialize(period as Number, most as Number) {
                _period = period;
                _most = most;
            }

            // The tests: no timer
            function setStill() as Void {
                _still = true;
            }

            // Shown, in either power mode: the cadence decides
            function onShow() as Void {
                _quick = 0;
                _lastUpdate = 0;
                _proven = false;
            }

            function onHide() as Void {
                stop();
                _proven = false;
            }

            // A wake: high power mode for certain
            function onExitSleep() as Void {
                awake = true;
                _known = true;
                _proven = true;
                _lastFrame = 0;
            }

            function onEnterSleep() as Void {
                awake = false;
                _known = true;
                _proven = false;
                stop();
            }

            // At the top of onUpdate, with System.getTimer(): the cadence, and
            // the ms the motion moves on this frame
            function step(now as Number) as Number {
                cadence(now);
                var gap = now - _lastFrame;
                if (_lastFrame == 0 || gap < 0 || gap > 2000) {
                    gap = _period;
                }
                _lastFrame = now;
                return (gap > _period * _most) ? _period * _most : gap;
            }

            // At the end of onUpdate: frames while something moves, none after
            function want(busy as Boolean) as Void {
                if (!busy) {
                    stop();
                    return;
                }
                if (_running || _still || !awake || !_proven) {
                    return;
                }
                var timer = _timer;
                if (timer == null) {
                    timer = new Timer.Timer();
                    _timer = timer;
                }
                timer.start(method(:tick), _period, true);
                _running = true;
            }

            function running() as Boolean {
                return _running;
            }

            // Whether the face has been shown awake, so a timer may start
            function proven() as Boolean {
                return _proven;
            }

            function tick() as Void {
                WatchUi.requestUpdate();
            }

            private function stop() as Void {
                var timer = _timer;
                if (timer != null && _running) {
                    timer.stop();
                }
                _running = false;
            }

            // Awake, the system redraws the face every second; asleep, once a
            // minute. Quick updates in a row prove the face awake; a long gap,
            // before onEnterSleep or onExitSleep has spoken, means asleep
            private function cadence(now as Number) as Void {
                var gap = (_lastUpdate > 0) ? now - _lastUpdate : -1;
                _lastUpdate = now;
                if (gap < 0) {
                    return;
                }
                if (gap <= QUICK) {
                    if (_quick < QUICK_RUN) {
                        _quick++;
                    }
                } else {
                    _quick = 0;
                    if (gap > ASLEEP_GAP && !_known) {
                        awake = false;
                        _proven = false;
                    }
                }
                if (_quick >= QUICK_RUN) {
                    if (!_known) {
                        awake = true;
                    }
                    if (awake) {
                        _proven = true;
                    }
                }
            }
        }
    }
}
