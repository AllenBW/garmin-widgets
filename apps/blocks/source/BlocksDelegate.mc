import Toybox.Complications;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Watch faces get one gesture: press and hold. Holding on a reading opens
// its widget, and holding on the time steps to the next look (Lib.Look).
class BlocksDelegate extends WatchUi.WatchFaceDelegate {

    private var _view as BlocksView;

    function initialize(view as BlocksView) {
        WatchFaceDelegate.initialize();
        _view = view;
    }

    function onPress(clickEvent as ClickEvent) as Boolean {
        var xy = clickEvent.getCoordinates();
        var type = _view.targetAt(xy[0], xy[1]);
        if (type == null) {
            Lib.Look.next();
            _view.reloadSettings();
            WatchUi.requestUpdate();
            return true;
        }
        if (!(Toybox has :Complications)) {
            return false;
        }
        try {
            Complications.exitTo(new Complications.Id(type));
            return true;
        } catch (e) {
            return false;   // no widget for this on this watch
        }
    }

    // The firmware calls this when onUpdate takes too long in low power mode
    function onPowerBudgetExceeded(powerInfo as WatchFacePowerInfo) as Void {
        System.println("Blocks: power budget exceeded");
    }
}
