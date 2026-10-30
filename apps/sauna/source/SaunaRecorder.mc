import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.FitContributor;
import Toybox.Lang;
import Toybox.Math;

// The FIT file for Garmin Connect: a Meditation (or generic) activity named
// Sauna with one lap per phase, the watch temperature and the phase every
// second, the recovery on each break lap, and the visit's totals on the
// session. Everything is guarded so the app still runs if recording fails.
class SaunaRecorder {

    private var _session as ActivityRecording.Session? = null;
    private var _temp as FitContributor.Field? = null;        // tenths, as read
    private var _tempNative as FitContributor.Field? = null;  // whole degrees in Connect's own temperature slot
    private var _phase as FitContributor.Field? = null;
    private var _drop1 as FitContributor.Field? = null;       // lap: beats fallen a minute after the peak
    private var _drop2 as FitContributor.Field? = null;       // lap: two minutes
    private var _rounds as FitContributor.Field? = null;      // session
    private var _saunaMin as FitContributor.Field? = null;
    private var _breakMin as FitContributor.Field? = null;
    private var _maxTemp as FitContributor.Field? = null;
    private var _maxHr as FitContributor.Field? = null;
    private var _avgDrop as FitContributor.Field? = null;
    private var _kind as FitContributor.Field? = null;

    function initialize() {
    }

    function recording() as Boolean {
        var s = _session;
        return s != null && s.isRecording();
    }

    function active() as Boolean {
        return _session != null;
    }

    // Create and start the session; false when the device refuses
    function start(meditation as Boolean, kind as Number) as Boolean {
        if (!(Toybox has :ActivityRecording)) {
            return false;
        }
        try {
            var session = ActivityRecording.createSession({
                :name => SaunaText.kindName(kind),
                :sport => meditation ? Activity.SPORT_MEDITATION : Activity.SPORT_GENERIC,
                :subSport => Activity.SUB_SPORT_GENERIC
            });
            var record = FitContributor.MESG_TYPE_RECORD;
            var lap = FitContributor.MESG_TYPE_LAP;
            var sess = FitContributor.MESG_TYPE_SESSION;
            _temp = session.createField("Watch temp", 0, FitContributor.DATA_TYPE_FLOAT, {:mesgType => record, :units => "C"});
            _tempNative = session.createField("temperature", 1, FitContributor.DATA_TYPE_SINT8, {:mesgType => record, :units => "C", :nativeNum => 13});
            _phase = session.createField("Phase", 2, FitContributor.DATA_TYPE_UINT8, {:mesgType => record, :units => ""});
            _drop1 = session.createField("HR fall 1 min", 3, FitContributor.DATA_TYPE_SINT16, {:mesgType => lap, :units => "bpm"});
            _drop2 = session.createField("HR fall 2 min", 4, FitContributor.DATA_TYPE_SINT16, {:mesgType => lap, :units => "bpm"});
            _rounds = session.createField("Rounds", 5, FitContributor.DATA_TYPE_UINT8, {:mesgType => sess, :units => ""});
            _saunaMin = session.createField("Sauna time", 6, FitContributor.DATA_TYPE_UINT16, {:mesgType => sess, :units => "min"});
            _breakMin = session.createField("Break time", 7, FitContributor.DATA_TYPE_UINT16, {:mesgType => sess, :units => "min"});
            _maxTemp = session.createField("Max watch temp", 8, FitContributor.DATA_TYPE_FLOAT, {:mesgType => sess, :units => "C"});
            _maxHr = session.createField("Max HR in sauna", 9, FitContributor.DATA_TYPE_UINT8, {:mesgType => sess, :units => "bpm"});
            _avgDrop = session.createField("Avg HR fall 1 min", 10, FitContributor.DATA_TYPE_SINT16, {:mesgType => sess, :units => "bpm"});
            _kind = session.createField("Kind", 11, FitContributor.DATA_TYPE_UINT8, {:mesgType => sess, :units => ""});
            setData(_kind, kind);
            _session = session;
            return session.start();
        } catch (e) {
            _session = null;
            return false;
        }
    }

    // Pause and resume keep the same file
    function pause() as Void {
        var s = _session;
        if (s != null && s.isRecording()) {
            s.stop();
        }
    }

    function resume() as Void {
        var s = _session;
        if (s != null && !s.isRecording()) {
            s.start();
        }
    }

    // Once a second
    function record(temp as Float?, phase as Number) as Void {
        if (_session == null) {
            return;
        }
        if (temp != null) {
            setData(_temp, temp);
            setData(_tempNative, Math.round(temp).toNumber());
        }
        setData(_phase, phase);
    }

    // Close the lap that is ending. A break lap carries the recovery of the
    // round before it; a sauna lap carries zeros there.
    function lap(recovered as SaunaRound?) as Void {
        var s = _session;
        if (s == null) {
            return;
        }
        setRecovery(recovered);
        s.addLap();
    }

    private function setRecovery(round as SaunaRound?) as Void {
        var d1 = 0;
        var d2 = 0;
        if (round != null) {
            var a = round.drop1;
            var b = round.drop2;
            d1 = a == null ? 0 : a;
            d2 = b == null ? 0 : b;
        }
        setData(_drop1, d1);
        setData(_drop2, d2);
    }

    // Stop and keep the file; true when it was written
    function save(tracker as SaunaTracker) as Boolean {
        var s = _session;
        if (s == null) {
            return false;
        }
        // the lap still open is a break (its round's recovery) or a round
        setRecovery(tracker.phase == PHASE_BREAK ? tracker.current() : null);
        setData(_rounds, tracker.roundCount());
        setData(_saunaMin, tracker.saunaSeconds() / 60);
        setData(_breakMin, tracker.breakSeconds() / 60);
        var mt = tracker.maxTemp;
        if (mt != null) {
            setData(_maxTemp, mt);
        }
        setData(_maxHr, tracker.maxHr());
        var drop = tracker.avgDrop1();
        setData(_avgDrop, drop == null ? 0 : drop);
        setData(_kind, tracker.plan.kind);
        var ok = false;
        try {
            if (s.isRecording()) {
                s.stop();
            }
            ok = s.save();
        } catch (e) {
            ok = false;
        }
        _session = null;
        return ok;
    }

    function discard() as Void {
        var s = _session;
        if (s == null) {
            return;
        }
        try {
            if (s.isRecording()) {
                s.stop();
            }
            s.discard();
        } catch (e) {
        }
        _session = null;
    }

    private function setData(field as FitContributor.Field?, value as Numeric) as Void {
        if (field != null) {
            field.setData(value);
        }
    }
}
