import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Daylight: a 24 h sun dial watch face (designs/DESIGNS.md, design #3).
class DaylightApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [new DaylightView()];
    }
}
