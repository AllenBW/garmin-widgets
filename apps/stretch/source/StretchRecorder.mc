import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Lang;

// The session for Garmin Connect: Training, Flexibility Training, named
// after the routine, with a lap for each stretch.
class StretchRecorder {

    private var _session as ActivityRecording.Session? = null;

    function initialize() {
    }

    function active() as Boolean {
        return _session != null;
    }

    // false when the device refuses
    function start(name as String) as Boolean {
        if (!(Toybox has :ActivityRecording)) {
            return false;
        }
        try {
            var s = ActivityRecording.createSession({
                :name => name,
                :sport => Activity.SPORT_TRAINING,
                :subSport => Activity.SUB_SPORT_FLEXIBILITY_TRAINING
            });
            if (s.start()) {
                _session = s;
                return true;
            }
        } catch (e) {
        }
        _session = null;
        return false;
    }

    function lap() as Void {
        var s = _session;
        try {
            if (s != null && s.isRecording()) {
                s.addLap();
            }
        } catch (e) {
        }
    }

    function pause() as Void {
        var s = _session;
        try {
            if (s != null && s.isRecording()) {
                s.stop();
            }
        } catch (e) {
        }
    }

    function resume() as Void {
        var s = _session;
        try {
            if (s != null && !s.isRecording()) {
                s.start();
            }
        } catch (e) {
        }
    }

    // false when it didn't reach the watch's activities
    function save() as Boolean {
        var s = _session;
        _session = null;
        if (s == null) {
            return false;
        }
        try {
            if (s.isRecording()) {
                s.stop();
            }
            return s.save();
        } catch (e) {
        }
        return false;
    }

    function discard() as Void {
        var s = _session;
        _session = null;
        try {
            if (s != null) {
                if (s.isRecording()) {
                    s.stop();
                }
                s.discard();
            }
        } catch (e) {
        }
    }
}
