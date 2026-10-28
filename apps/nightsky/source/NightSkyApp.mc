import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Night Sky: the sky overhead as a watch face.
class NightSkyApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [new NightSkyView()];
    }
}
