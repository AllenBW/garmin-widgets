import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Vessel: the time as two glasses that fill to your readings, and a
// standby that stays on (designs/DESIGNS.md, design #16).
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

    // The settings changed in the phone app (or the simulator's settings
    // editor): they win over the watch face editor until it is next used
    function onSettingsChanged() as Void {
        Lib.Config.changedOnPhone();
        var view = _view;
        if (view != null) {
            view.reloadSettings();
        }
        WatchUi.requestUpdate();
    }
}
