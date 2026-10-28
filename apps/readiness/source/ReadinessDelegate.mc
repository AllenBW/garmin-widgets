import Toybox.Complications;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Press and hold on a gauge, a tile or the footer opens the native widget
// for that metric.
class ReadinessDelegate extends WatchUi.WatchFaceDelegate {

    private var _view as ReadinessView;

    function initialize(view as ReadinessView) {
        WatchFaceDelegate.initialize();
        _view = view;
    }

    function onPress(clickEvent as ClickEvent) as Boolean {
        if (!(Toybox has :Complications)) {
            return false;
        }
        var xy = clickEvent.getCoordinates();
        var type = _view.metricAt(xy[0], xy[1]);
        if (type == null) {
            return false;
        }
        try {
            Complications.exitTo(new Complications.Id(type));
            return true;
        } catch (e instanceof Lang.InvalidValueException) {
            return false;   // no widget for this metric on this watch
        }
    }

    // The firmware calls this when onUpdate takes too long in low power mode
    function onPowerBudgetExceeded(powerInfo as WatchFacePowerInfo) as Void {
        System.println("Readiness: power budget exceeded");
    }
}
