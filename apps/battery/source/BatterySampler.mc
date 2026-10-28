import Toybox.Background;
import Toybox.Lang;
import Toybox.System;

// The background service: woken every SAMPLE_MINUTES, it appends one sample
// to the battery log and exits. Nothing else runs here, so it stays far
// below the 64 KB background budget.
(:background)
class BatterySampler extends System.ServiceDelegate {

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        var count = BatteryLog.recordNow();
        Background.exit(count);
    }
}
