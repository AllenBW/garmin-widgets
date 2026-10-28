import Toybox.ActivityMonitor;
import Toybox.Complications;
import Toybox.Lang;
import Toybox.SensorHistory;
import Toybox.UserProfile;

// One minute's worth of body metrics; null where the watch has nothing yet
class Readings {
    var bodyBattery as Number? = null;      // 0..100
    var stress as Number? = null;           // 0..100
    var sleepScore as Number? = null;       // 0..100
    var recoveryMinutes as Number? = null;  // 0 when recovered
    var restingHr as Number? = null;        // beats per minute
    var trainingStatus as String? = null;   // "Productive", "Recovery", ...

    function initialize() {
    }
}

// Where each number comes from. Body Battery and stress are the newest
// SensorHistory samples (stress falls back to the activity monitor), sleep
// score, recovery time and training status are complications, and the
// resting heart rate is in the user profile. HRV status and Training
// Readiness are not exposed to Connect IQ (see designs/DESIGNS.md).
module Metrics {

    function read() as Readings {
        var r = new Readings();
        r.bodyBattery = newestSample(:getBodyBatteryHistory);
        r.stress = newestSample(:getStressHistory);
        if (r.stress == null) {
            r.stress = ActivityMonitor.getInfo().stressScore;
        }
        r.sleepScore = complicationNumber(Complications.COMPLICATION_TYPE_SLEEP_SCORE);
        r.recoveryMinutes = recoveryMinutes();
        r.restingHr = UserProfile.getProfile().restingHeartRate;
        r.trainingStatus = complicationString(Complications.COMPLICATION_TYPE_TRAINING_STATUS);
        return r;
    }

    // Minutes left to recover: the complication, else the activity
    // monitor's hours
    function recoveryMinutes() as Number? {
        var minutes = complicationNumber(Complications.COMPLICATION_TYPE_RECOVERY_TIME);
        if (minutes != null) {
            return minutes;
        }
        var info = ActivityMonitor.getInfo();
        var hours = (info has :timeToRecovery) ? info.timeToRecovery : null;
        return (hours != null) ? hours * 60 : null;
    }

    // A complication's value when it is a number, else null
    function complicationNumber(type as Complications.Type) as Number? {
        var value = complicationValue(type);
        if (value instanceof Number) {
            return value;
        }
        if (value instanceof Float) {
            return value.toNumber();
        }
        return null;
    }

    // A complication's value when it is text, else null
    function complicationString(type as Complications.Type) as String? {
        var value = complicationValue(type);
        return (value instanceof String) ? value : null;
    }

    function complicationValue(type as Complications.Type) as Complications.Value or String or Null {
        if (!(Toybox has :Complications)) {
            return null;
        }
        try {
            return Complications.getComplication(new Complications.Id(type)).value;
        } catch (e) {
            return null;   // not available on this watch
        }
    }

    // Newest sample of a SensorHistory series (Body Battery, stress), 0..100
    function newestSample(getter as Symbol) as Number? {
        if (!(Toybox has :SensorHistory) || !(Toybox.SensorHistory has getter)) {
            return null;
        }
        var options = {:period => 1, :order => SensorHistory.ORDER_NEWEST_FIRST};
        var iterator = null;
        if (getter == :getBodyBatteryHistory) {
            iterator = SensorHistory.getBodyBatteryHistory(options);
        } else if (getter == :getStressHistory) {
            iterator = SensorHistory.getStressHistory(options);
        }
        if (iterator == null) {
            return null;
        }
        var sample = iterator.next();
        if (sample == null || sample.data == null) {
            return null;
        }
        return (sample.data as Numeric).toNumber();
    }
}
