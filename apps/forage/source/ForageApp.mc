import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Forage: are the bees flying, and when can the hive be opened
// (designs/DESIGNS.md, design #15).
class ForageApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new ForageView();
        return [view, new ForageDelegate(view)];
    }
}
