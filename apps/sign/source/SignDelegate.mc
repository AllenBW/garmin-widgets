import Toybox.Application.WatchFaceConfig;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Watch faces get one gesture: press and hold. A hold steps to the next look
// (Lib.Look), its name standing where the date is for a moment.
class SignDelegate extends WatchUi.WatchFaceDelegate {

    private var _view as SignView;

    function initialize(view as SignView) {
        WatchFaceDelegate.initialize();
        _view = view;
    }

    function onPress(clickEvent as ClickEvent) as Boolean {
        Lib.Look.next();
        _view.reloadSettings();
        WatchUi.requestUpdate();
        return true;
    }

    // The editor changed a tube: it wins over the phone app's settings until
    // they are next changed (Lib.Neon.chosen)
    function onWatchFaceConfigEdited(options as {:configId as WatchFaceConfig.Id, :type as WatchUi.WatchFaceConfigType?,
                                                 :committed as Boolean}) as Void {
        Lib.Neon.changedInEditor();
        _view.reloadSettings();
        WatchUi.requestUpdate();
    }

    // The firmware calls this when onUpdate takes too long in low power mode
    function onPowerBudgetExceeded(powerInfo as WatchFacePowerInfo) as Void {
        System.println("Sign: power budget exceeded");
    }
}
