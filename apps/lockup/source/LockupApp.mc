import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Lockup: rows of numbers reaching the bezel all the way round, coloured by
// family (designs/DESIGNS.md, design #20).
class LockupApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    private var _view as LockupView?;

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new LockupView();
        _view = view;
        return [view, new LockupDelegate(view)];
    }

    // A new look chosen in the phone app wins over the last hold
    function onSettingsChanged() as Void {
        Lib.Look.changedOnPhone();
        var view = _view;
        if (view != null) {
            view.reloadSettings();
        }
        WatchUi.requestUpdate();
    }
}
