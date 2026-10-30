import Toybox.ActivityMonitor;
import Toybox.Lang;
import Toybox.SensorHistory;

// What the three rings show: steps against the step goal, floors climbed
// against the floors goal, and Body Battery out of 100.
module Goals {

    // [steps, goal]; nulls when the watch has nothing yet
    function steps() as [Number?, Number?] {
        var info = ActivityMonitor.getInfo();
        return [info.steps, info.stepGoal];
    }

    function floors() as [Number?, Number?] {
        var info = ActivityMonitor.getInfo();
        var climbed = (info has :floorsClimbed) ? info.floorsClimbed : null;
        var goal = (info has :floorsClimbedGoal) ? info.floorsClimbedGoal : null;
        return [climbed, goal];
    }

    // The newest Body Battery sample, 0..100, or null
    function bodyBattery() as Number? {
        if (!(Toybox has :SensorHistory) || !(Toybox.SensorHistory has :getBodyBatteryHistory)) {
            return null;
        }
        var iterator = SensorHistory.getBodyBatteryHistory({:period => 1, :order => SensorHistory.ORDER_NEWEST_FIRST});
        var sample = iterator.next();
        if (sample == null || sample.data == null) {
            return null;
        }
        return (sample.data as Numeric).toNumber();
    }

    // value / goal clamped to 0..1; 0 when either is missing
    function fraction(value as Number?, goal as Number?) as Float {
        if (value == null || goal == null || goal <= 0) {
            return 0.0;
        }
        var f = value.toFloat() / goal;
        return (f > 1.0) ? 1.0 : (f < 0.0 ? 0.0 : f);
    }
}
