import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.SensorHistory;

// What a slot on the Field face can show. The numbers are the values stored
// in the Slot1..Slot3 properties (resources/settings/settings.xml).
module Slots {

    const HEART_RATE = 0;
    const STEPS = 1;
    const BODY_BATTERY = 2;
    const CALORIES = 3;
    const FLOORS = 4;
    const DISTANCE = 5;
    const STRESS = 6;

    function label(kind as Number) as String {
        switch (kind) {
            case HEART_RATE:   return "HR";
            case STEPS:        return "STEPS";
            case BODY_BATTERY: return "BODY BATT";
            case CALORIES:     return "KCAL";
            case FLOORS:       return "FLOORS";
            case DISTANCE:     return "DIST";
            case STRESS:       return "STRESS";
        }
        return "";
    }

    function color(kind as Number) as ColorType {
        switch (kind) {
            case HEART_RATE:   return 0xFF4D4D;
            case BODY_BATTERY: return 0x46D18A;
            case STRESS:       return 0xFF7A3D;
        }
        return 0xF2F2F2;
    }

    // Current value as display text, "--" when the watch has nothing yet.
    function value(kind as Number) as String {
        switch (kind) {
            case HEART_RATE:   return heartRate();
            case STEPS:        return steps();
            case BODY_BATTERY: return newestSample(:getBodyBatteryHistory);
            case CALORIES:     return calories();
            case FLOORS:       return floors();
            case DISTANCE:     return distance();
            case STRESS:       return newestSample(:getStressHistory);
        }
        return "--";
    }

    // The native complication a press-and-hold on the slot should open, or
    // null when there is no matching widget (distance).
    function complicationType(kind as Number) as Complications.Type? {
        switch (kind) {
            case HEART_RATE:   return Complications.COMPLICATION_TYPE_HEART_RATE;
            case STEPS:        return Complications.COMPLICATION_TYPE_STEPS;
            case BODY_BATTERY: return Complications.COMPLICATION_TYPE_BODY_BATTERY;
            case CALORIES:     return Complications.COMPLICATION_TYPE_CALORIES;
            case FLOORS:       return Complications.COMPLICATION_TYPE_FLOORS_CLIMBED;
            case STRESS:       return Complications.COMPLICATION_TYPE_STRESS;
        }
        return null;
    }

    // ------------------------------------------------------------- sources

    function heartRate() as String {
        var info = Activity.getActivityInfo();
        var hr = (info != null) ? info.currentHeartRate : null;
        return (hr != null) ? hr.toString() : "--";
    }

    function steps() as String {
        var steps = ActivityMonitor.getInfo().steps;
        return (steps != null) ? Lib.Fmt.thousands(steps) : "--";
    }

    function calories() as String {
        var kcal = ActivityMonitor.getInfo().calories;
        return (kcal != null) ? Lib.Fmt.thousands(kcal) : "--";
    }

    function floors() as String {
        var floors = ActivityMonitor.getInfo().floorsClimbed;
        return (floors != null) ? floors.toString() : "--";
    }

    function distance() as String {
        var cm = ActivityMonitor.getInfo().distance;
        return (cm != null) ? Lib.Fmt.distance(cm) : "--";
    }

    // Newest sample of a SensorHistory series (Body Battery, stress), 0-100.
    function newestSample(getter as Symbol) as String {
        if (!(Toybox has :SensorHistory) || !(Toybox.SensorHistory has getter)) {
            return "--";
        }
        var options = {:period => 1, :order => SensorHistory.ORDER_NEWEST_FIRST};
        var iterator = null;
        if (getter == :getBodyBatteryHistory) {
            iterator = SensorHistory.getBodyBatteryHistory(options);
        } else if (getter == :getStressHistory) {
            iterator = SensorHistory.getStressHistory(options);
        }
        if (iterator == null) {
            return "--";
        }
        var sample = iterator.next();
        if (sample == null || sample.data == null) {
            return "--";
        }
        return (sample.data as Numeric).toNumber().toString();
    }
}
