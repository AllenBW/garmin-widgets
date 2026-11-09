import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Clack: a split-flap clock with no case, each digit its own leaf, rolling
// at twenty frames a second after a wake (designs/DESIGNS.md, design #24).
class ClackApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    private var _view as ClackView?;

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new ClackView();
        _view = view;
        return [view, new ClackDelegate(view)];
    }

    // The settings changed in the phone app (or the simulator's settings
    // editor): they win over the watch face editor until it is next used
    function onSettingsChanged() as Void {
        ClackSettings.changedOnPhone();
        var view = _view;
        if (view != null) {
            view.reloadSettings();
        }
        WatchUi.requestUpdate();
    }
}
