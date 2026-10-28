import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Horizon: the next twelve hours on the bezel (designs/DESIGNS.md, design #7).
class HorizonApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [new HorizonView()];
    }
}
