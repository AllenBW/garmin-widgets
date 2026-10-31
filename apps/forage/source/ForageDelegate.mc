import Toybox.Complications;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Watch faces get one gesture: press and hold. Holding on the verdict, the
// hive line or the comb opens the native weather widget.
class ForageDelegate extends WatchUi.WatchFaceDelegate {

    private var _view as ForageView;

    function initialize(view as ForageView) {
        WatchFaceDelegate.initialize();
        _view = view;
    }

    function onPress(clickEvent as ClickEvent) as Boolean {
        if (!(Toybox has :Complications)) {
            return false;
        }
        var xy = clickEvent.getCoordinates();
        var type = _view.targetAt(xy[0], xy[1]);
        if (type == null) {
            return false;
        }
        try {
            Complications.exitTo(new Complications.Id(type));
            return true;
        } catch (e instanceof Lang.InvalidValueException) {
            return false;   // no widget for this on this watch
        }
    }

    // The firmware calls this when onUpdate takes too long in low power mode
    function onPowerBudgetExceeded(powerInfo as WatchFacePowerInfo) as Void {
        System.println("Forage: power budget exceeded");
    }
}
