import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Today: the owner's own list on one face (designs/README.md, design #11).
class TodayApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new TodayView();
        return [view, new TodayDelegate(view)];
    }
}
