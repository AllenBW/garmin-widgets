import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Wall: a face made of numbers, sized by importance and coloured by family
// (designs/README.md, design #22).
class WallApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    private var _view as WallView?;

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new WallView();
        _view = view;
        return [view, new WallDelegate(view)];
    }

    // The settings on the watch itself, for every watch: the phone app's
    // list as a menu (Lib.WatchMenu, Choices)
    function getSettingsView() as [Views] or [Views, InputDelegates] or Null {
        return Lib.WatchMenu.view(WatchUi.loadResource(Rez.Strings.AppName) as String, Choices.entries());
    }

    // The settings changed in the phone app or the watch's settings menu:
    // they win over the watch face editor until it is next used, and a new
    // look chosen there wins over the last hold
    function onSettingsChanged() as Void {
        Lib.Config.changedOnPhone();
        var view = _view;
        if (view != null) {
            view.reloadSettings();
        }
        WatchUi.requestUpdate();
    }
}
