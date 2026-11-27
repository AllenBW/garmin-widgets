import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Daylight: a 24 h sun dial watch face (designs/README.md, design #3).
class DaylightApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    private var _view as DaylightView?;

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new DaylightView();
        _view = view;
        return [view, new DaylightDelegate(view)];
    }

    // The settings on the watch itself, for every watch: the phone app's
    // list as a menu (Lib.WatchMenu, Choices)
    function getSettingsView() as [Views] or [Views, InputDelegates] or Null {
        return Lib.WatchMenu.view(WatchUi.loadResource(Rez.Strings.AppName) as String, Choices.entries());
    }

    // A choice made in the phone app or the watch's settings menu wins over
    // the last hold and over the watch face editor
    function onSettingsChanged() as Void {
        Skies.changedOnPhone();
        var view = _view;
        if (view != null) {
            view.reloadSettings();
        }
        WatchUi.requestUpdate();
    }
}
