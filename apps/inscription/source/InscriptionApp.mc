import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Inscription: the time struck large like a coin, your readings round the
// rim, and a standby that stays on (designs/DESIGNS.md, design #17).
class InscriptionApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    private var _view as InscriptionView?;

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new InscriptionView();
        _view = view;
        return [view, new InscriptionDelegate(view)];
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
