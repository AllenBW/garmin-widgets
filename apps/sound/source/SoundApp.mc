import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Sound Level (designs/DESIGNS.md, design #14): an approximate sound
// level meter from the watch microphone, with the danger range from the
// NIOSH exposure limit and a cue by every button. The glance is the last
// reading; the app listens while it is open and keeps no audio.
(:glance)
class SoundApp extends Application.AppBase {

    private var _view as SoundView?;

    function initialize() {
        AppBase.initialize();
    }

    function getGlanceView() as [GlanceView] or [GlanceView, GlanceViewDelegate] or Null {
        return [new SoundGlance()];
    }

    function getGlanceTheme() as AppBase.GlanceTheme {
        return AppBase.GLANCE_THEME_BLUE;
    }

    (:typecheck(disableGlanceCheck))
    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new SoundView();
        _view = view;
        return [view, new SoundDelegate(view)];
    }

    // Settings edited on the phone while the app is open
    (:typecheck(disableGlanceCheck))
    function onSettingsChanged() as Void {
        var view = _view;
        if (view != null) {
            view.reloadSettings();
            WatchUi.requestUpdate();
        }
    }

    // Leaving the app: stop the microphone, keep the last reading for the glance
    (:typecheck(disableGlanceCheck))
    function onStop(state as Dictionary?) as Void {
        var view = _view;
        if (view != null) {
            view.shutdown();
        }
    }
}
