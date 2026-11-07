import Toybox.Application.WatchFaceConfig;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// The watch face editor's edits: the view (the layout and the digits' face)
// is a style there; each edit redraws.
class ClackDelegate extends WatchUi.WatchFaceDelegate {

    private var _view as ClackView;

    function initialize(view as ClackView) {
        WatchFaceDelegate.initialize();
        _view = view;
    }

    // The editor changed the view: it wins over the phone app's settings
    // until they are next changed
    function onWatchFaceConfigEdited(options as {:configId as WatchFaceConfig.Id, :type as WatchUi.WatchFaceConfigType?,
                                                 :committed as Boolean}) as Void {
        ClackSettings.changedInEditor();
        _view.reloadSettings();
        WatchUi.requestUpdate();
    }

    // The firmware calls this when onUpdate takes too long in low power mode
    function onPowerBudgetExceeded(powerInfo as WatchFacePowerInfo) as Void {
        System.println("Clack: power budget exceeded");
    }
}
