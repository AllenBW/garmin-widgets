import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Vessel: the time as two glasses that fill to your readings, and a
// standby that stays on (designs/README.md, design #16).
class VesselApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    private var _view as VesselView?;

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new VesselView();
        _view = view;
        return [view, new VesselDelegate(view)];
    }

    // The settings on the watch itself, for every watch: the phone app's
    // list as a menu (Lib.WatchMenu, Choices)
    function getSettingsView() as [Views] or [Views, InputDelegates] or Null {
        return Lib.WatchMenu.view(WatchUi.loadResource(Rez.Strings.AppName) as String, Choices.entries());
    }

    // The settings changed in the phone app, the watch's settings menu (or
    // the simulator's settings editor): they win over the watch face editor
    // until it is next used
    function onSettingsChanged() as Void {
        Lib.Config.changedOnPhone();
        var view = _view;
        if (view != null) {
            view.reloadSettings();
        }
        WatchUi.requestUpdate();
    }
}
