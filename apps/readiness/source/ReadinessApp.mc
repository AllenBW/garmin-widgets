import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Readiness (designs/README.md, design #4): the recovery picture as a
// watch face. Body Battery and stress gauges, sleep score, recovery time,
// resting heart rate and the training status, with the time in the middle.
class ReadinessApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    private var _view as ReadinessView?;

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new ReadinessView();
        _view = view;
        return [view, new ReadinessDelegate(view)];
    }

    // The settings on the watch itself, for every watch: the phone app's
    // list as a menu (Lib.WatchMenu, Choices)
    function getSettingsView() as [Views] or [Views, InputDelegates] or Null {
        return Lib.WatchMenu.view(WatchUi.loadResource(Rez.Strings.AppName) as String, Choices.entries());
    }

    // A choice made in the phone app or the watch's settings menu wins over
    // the last hold and over the watch face editor, until the editor is used
    // again (Choices.editor)
    function onSettingsChanged() as Void {
        Lib.Config.changedOnPhone();
        var view = _view;
        if (view != null) {
            view.reloadSettings();
        }
        WatchUi.requestUpdate();
    }
}
