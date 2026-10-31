import Toybox.Application.WatchFaceConfig;
import Toybox.Complications;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Watch faces get one gesture: press and hold. Holding on the sun line, the
// date, a ring or a number opens the native widget for it.
class RingsDelegate extends WatchUi.WatchFaceDelegate {

    private var _view as RingsView;

    function initialize(view as RingsView) {
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

    // The watch face editor changed the theme
    function onWatchFaceConfigEdited(options as {:configId as WatchFaceConfig.Id, :type as WatchUi.WatchFaceConfigType?,
                                                 :committed as Boolean}) as Void {
        _view.reloadSettings();
        WatchUi.requestUpdate();
    }

    // The firmware calls this when onUpdate takes too long in low power mode
    function onPowerBudgetExceeded(powerInfo as WatchFacePowerInfo) as Void {
        System.println("Rings: power budget exceeded");
    }
}
