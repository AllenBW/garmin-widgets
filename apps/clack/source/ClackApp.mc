import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Clack: a split-flap clock with no case, each digit its own leaf, rolling
// at twenty frames a second after a wake (designs/README.md, design #24).
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

    // The settings on the watch itself, for every watch: the phone app's
    // list as a menu (Lib.WatchMenu, Choices)
    function getSettingsView() as [Views] or [Views, InputDelegates] or Null {
        return Lib.WatchMenu.view(WatchUi.loadResource(Rez.Strings.AppName) as String, Choices.entries());
    }

    // The settings changed in the phone app, the watch's settings menu (or
    // the simulator's settings editor): they win over the watch face editor
    // until it is next used, and a new look chosen there over the last hold
    function onSettingsChanged() as Void {
        ClackSettings.changedOnPhone();
        var view = _view;
        if (view != null) {
            view.reloadSettings();
        }
        WatchUi.requestUpdate();
    }
}
