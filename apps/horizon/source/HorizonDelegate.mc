import Toybox.Application.WatchFaceConfig;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Watch faces get one gesture: press and hold. Horizon has nothing to open,
// so a hold anywhere steps to the next look (Lib.Look), its name standing
// in place of the date for a moment.
class HorizonDelegate extends WatchUi.WatchFaceDelegate {

    private var _view as HorizonView;

    function initialize(view as HorizonView) {
        WatchFaceDelegate.initialize();
        _view = view;
    }

    function onPress(clickEvent as ClickEvent) as Boolean {
        Lib.Look.next();
        _view.reloadSettings();
        WatchUi.requestUpdate();
        return true;
    }

    // The editor changed the sky or the time colour: it wins over the phone
    // app's settings until they are next changed (Skies.chosen)
    function onWatchFaceConfigEdited(options as {:configId as WatchFaceConfig.Id, :type as WatchUi.WatchFaceConfigType?,
                                                 :committed as Boolean}) as Void {
        Skies.changedInEditor();
        _view.reloadSettings();
        WatchUi.requestUpdate();
    }

    // The firmware calls this when onUpdate takes too long in low power mode
    function onPowerBudgetExceeded(powerInfo as WatchFacePowerInfo) as Void {
        System.println("Horizon: power budget exceeded");
    }
}
