import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Noir: an analog dial in neon, the hands loops of tube (design #59).
class NoirApp extends Application.AppBase {

    private var _view as NoirView?;

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new NoirView();
        _view = view;
        return [view, new NoirDelegate(view)];
    }

    // The settings on the watch itself, for every watch: the phone app's
    // list as a menu (Lib.WatchMenu, Choices)
    function getSettingsView() as [Views] or [Views, InputDelegates] or Null {
        return Lib.WatchMenu.view(WatchUi.loadResource(Rez.Strings.AppName) as String, Choices.entries());
    }

    // A choice made in the phone app or the watch's settings menu wins over
    // the last hold and over the watch face editor
    function onSettingsChanged() as Void {
        Lib.Neon.changedOnPhone();
        var view = _view;
        if (view != null) {
            view.reloadSettings();
        }
        WatchUi.requestUpdate();
    }
}
