import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.FitContributor;
import Toybox.Lang;
import Toybox.Math;

// The FIT file for Garmin Connect: a Meditation (or generic) activity named
// by the kind, with one lap per phase; the watch temperature, the phase,
// the breathing rate, the stress score and the minute's HRV every second;
// the recovery on each break lap; the visit's totals, kind, mode and Body
// Battery on the session. Each field is created on its own so a device
// that refuses one still records the rest.
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
    private var _guided as FitContributor.Field? = null;
    private var _breath as FitContributor.Field? = null;      // record
    private var _stress as FitContributor.Field? = null;
    private var _hrv as FitContributor.Field? = null;
    private var _bbStart as FitContributor.Field? = null;     // session
    private var _bbEnd as FitContributor.Field? = null;

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
    function start(meditation as Boolean, kind as Number, guided as Boolean) as Boolean {
        if (!(Toybox has :ActivityRecording)) {
            return false;
        }
        var session;
        try {
            session = ActivityRecording.createSession({
                :name => SaunaText.kindName(kind),
                :sport => meditation ? Activity.SPORT_MEDITATION : Activity.SPORT_GENERIC,
                :subSport => Activity.SUB_SPORT_GENERIC
            });
        } catch (e) {
            return false;
        }
        var record = FitContributor.MESG_TYPE_RECORD;
        var lap = FitContributor.MESG_TYPE_LAP;
        var sess = FitContributor.MESG_TYPE_SESSION;
        _temp = field(session, "Watch temp", 0, FitContributor.DATA_TYPE_FLOAT, record, "C", null);
        _tempNative = field(session, "temperature", 1, FitContributor.DATA_TYPE_SINT8, record, "C", 13);
        _phase = field(session, "Phase", 2, FitContributor.DATA_TYPE_UINT8, record, "", null);
        _drop1 = field(session, "HR fall 1 min", 3, FitContributor.DATA_TYPE_SINT16, lap, "bpm", null);
        _drop2 = field(session, "HR fall 2 min", 4, FitContributor.DATA_TYPE_SINT16, lap, "bpm", null);
        _rounds = field(session, "Rounds", 5, FitContributor.DATA_TYPE_UINT8, sess, "", null);
        _saunaMin = field(session, "Sauna time", 6, FitContributor.DATA_TYPE_UINT16, sess, "min", null);
        _breakMin = field(session, "Break time", 7, FitContributor.DATA_TYPE_UINT16, sess, "min", null);
        _maxTemp = field(session, "Max watch temp", 8, FitContributor.DATA_TYPE_FLOAT, sess, "C", null);
        _maxHr = field(session, "Max HR in heat", 9, FitContributor.DATA_TYPE_UINT8, sess, "bpm", null);
        _avgDrop = field(session, "Avg HR fall 1 min", 10, FitContributor.DATA_TYPE_SINT16, sess, "bpm", null);
        _kind = field(session, "Kind", 11, FitContributor.DATA_TYPE_UINT8, sess, "", null);
        _guided = field(session, "Guided", 12, FitContributor.DATA_TYPE_UINT8, sess, "", null);
        _breath = field(session, "Breathing", 13, FitContributor.DATA_TYPE_UINT8, record, "brpm", null);
        _stress = field(session, "Stress", 14, FitContributor.DATA_TYPE_UINT8, record, "", null);
        _hrv = field(session, "HRV RMSSD", 15, FitContributor.DATA_TYPE_UINT16, record, "ms", null);
        _bbStart = field(session, "Body Battery start", 16, FitContributor.DATA_TYPE_UINT8, sess, "", null);
        _bbEnd = field(session, "Body Battery end", 17, FitContributor.DATA_TYPE_UINT8, sess, "", null);
        setData(_kind, kind);
        setData(_guided, guided ? 1 : 0);
        _session = session;
        var ok = false;
        try {
            ok = session.start();
        } catch (e) {
            _session = null;
        }
        return ok;
    }

    private function field(session as ActivityRecording.Session, name as String, id as Number, type as FitContributor.DataType,
                           mesg as Number, units as String, nativeNum as Number?) as FitContributor.Field? {
        try {
            if (nativeNum != null) {
                return session.createField(name, id, type, {:mesgType => mesg, :units => units, :nativeNum => nativeNum});
            }
            return session.createField(name, id, type, {:mesgType => mesg, :units => units});
        } catch (e) {
            return null;
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

    // Once a second; null readings leave the previous value standing
    function record(temp as Float?, phase as Number, breath as Number?, stress as Number?, hrv as Number?) as Void {
        if (_session == null) {
            return;
        }
        if (temp != null) {
            setData(_temp, temp);
            setData(_tempNative, Math.round(temp).toNumber());
        }
        setData(_phase, phase);
        if (breath != null) {
            setData(_breath, breath);
        }
        if (stress != null) {
            setData(_stress, stress);
        }
        if (hrv != null) {
            setData(_hrv, hrv);
        }
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
    function save(tracker as SaunaTracker, bbStart as Number?, bbEnd as Number?) as Boolean {
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
        setData(_guided, tracker.guided ? 1 : 0);
        if (bbStart != null) {
            setData(_bbStart, bbStart);
        }
        if (bbEnd != null) {
            setData(_bbEnd, bbEnd);
        }
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
