import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class StarterFaceApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [new StarterFaceView()];
    }

    // Called when the user changes settings in the phone app or the on-device editor
    function onSettingsChanged() as Void {
        WatchUi.requestUpdate();
    }
}
