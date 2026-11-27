import Toybox.Application.WatchFaceConfig;
import Toybox.Complications;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Watch faces get one gesture: press and hold. Holding on a gauge, a tile or
// the footer opens the native widget for that metric, and holding on the
// time steps to the next look (Lib.Look).
class ReadinessDelegate extends WatchUi.WatchFaceDelegate {

    private var _view as ReadinessView;

    function initialize(view as ReadinessView) {
        WatchFaceDelegate.initialize();
        _view = view;
    }

    function onPress(clickEvent as ClickEvent) as Boolean {
        var xy = clickEvent.getCoordinates();
        if (_view.timeAt(xy[0], xy[1])) {
            Lib.Look.next();
            _view.reloadSettings();
            WatchUi.requestUpdate();
            return true;
        }
        if (!(Toybox has :Complications)) {
            return false;
        }
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

    // The watch face editor changed a gauge's colour: it wins over the
    // phone app's settings until they are next changed (Choices.editor)
    function onWatchFaceConfigEdited(options as {:configId as WatchFaceConfig.Id, :type as WatchUi.WatchFaceConfigType?,
                                                 :committed as Boolean}) as Void {
        Lib.Config.changedInEditor();
        _view.reloadSettings();
        WatchUi.requestUpdate();
    }

    // The firmware calls this when onUpdate takes too long in low power mode
    function onPowerBudgetExceeded(powerInfo as WatchFacePowerInfo) as Void {
        System.println("Readiness: power budget exceeded");
    }
}
