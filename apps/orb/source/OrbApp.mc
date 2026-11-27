import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Orb: Lockup's rows printed round a globe, where only what changed moves
// (designs/README.md, design #27).
class OrbApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    private var _view as OrbView?;

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new OrbView();
        _view = view;
        return [view, new OrbDelegate(view)];
    }

    // The settings on the watch itself, for every watch: the phone app's
    // list as a menu (Lib.WatchMenu, Choices)
    function getSettingsView() as [Views] or [Views, InputDelegates] or Null {
        return Lib.WatchMenu.view(WatchUi.loadResource(Rez.Strings.AppName) as String, Choices.entries());
    }

    // A choice made in the phone app or the watch's settings menu wins over
    // the last hold and over the watch face editor
    function onSettingsChanged() as Void {
        Lib.Config.changedOnPhone();
        var view = _view;
        if (view != null) {
            view.reloadSettings();
        }
        WatchUi.requestUpdate();
    }
}
