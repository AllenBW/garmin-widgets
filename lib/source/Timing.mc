import Toybox.Lang;
import Toybox.System;

module Lib {

    // How quickly a face lights, for the watch's log
    // (GARMIN/Apps/LOGS/<NAME>.TXT, which scripts/watch.sh push creates; a
    // watch without the file writes nothing). From a start (the view made)
    // or a wake (onExitSleep), it prints the first lit frame and any slow
    // frame after it, then the moment the face has settled:
    //   "<Face>: start +12 ms: a frame of 430 ms, the part 0"
    //   "<Face>: start: settled in 1470 ms, 2 frames, the slowest 915 ms"
    // The same lines come out of the simulator, to compare a change.
    (:timing)
    module Timing {

        const SLOW = 100;        // ms: a frame worth a line of its own

        class Log {
            var part as Number = 0;              // this frame's ms in the face's own costly part (a border, the loads)
            private var _name as String;
            private var _since as Number;        // when the face started or woke; -1 once settled
            private var _why as String = "start";
            private var _frames as Number = 0;
            private var _slowest as Number = 0;

            function initialize(name as String) {
                _name = name;
                _since = System.getTimer();
            }

            // onExitSleep
            function wake() as Void {
                _since = System.getTimer();
                _why = "wake";
                _frames = 0;
                _slowest = 0;
            }

            // Whether a start or a wake is still being timed
            function timing() as Boolean {
                return _since >= 0;
            }

            // At the end of each lit onUpdate, with System.getTimer() from its
            // top: `settled` when nothing more is due (no motion, nothing
            // left to draw over later frames)
            function frame(started as Number, settled as Boolean) as Void {
                if (_since < 0) {
                    return;
                }
                var now = System.getTimer();
                var took = now - started;
                if (_frames == 0 || took >= SLOW) {
                    System.println(_name + ": " + _why + " +" + (started - _since) + " ms: a frame of " + took + " ms, the part " + part);
                }
                _frames++;
                _slowest = (took > _slowest) ? took : _slowest;
                part = 0;
                if (settled) {
                    System.println(_name + ": " + _why + ": settled in " + (now - _since) + " ms, " + _frames + " frames, the slowest " + _slowest + " ms");
                    _since = -1;
                }
            }
        }
    }
}
