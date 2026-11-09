import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Tally (designs/README.md, design #19): buttons you make, each tap a
// moment logged, and the pattern they make over two weeks. The buttons
// (name, colour, the hours they show) are set on the phone in Garmin
// Connect; every entry goes to the owner's Google Sheet too.
//
// Runs in three places: the background service (TallySender, TallyLog),
// the glance (TallyGlance) and the app.
(:background, :glance)
class TallyApp extends Application.AppBase {

    private var _view as TallyView?;

    function initialize() {
        AppBase.initialize();
    }

    (:typecheck(disableGlanceCheck))
    function getServiceDelegate() as [System.ServiceDelegate] {
        return [new TallyService()];
    }

    // Left out of the sample build's captures of the app (the simulator
    // opens an app with a glance on its glance; sample.jungle)
    (:glanceview, :typecheck(disableBackgroundCheck))
    function getGlanceView() as [GlanceView] or [GlanceView, GlanceViewDelegate] or Null {
        TallySample.load();
        return [new TallyGlance()];
    }

    function getGlanceTheme() as AppBase.GlanceTheme {
        return AppBase.GLANCE_THEME_RED;
    }

    (:typecheck([disableBackgroundCheck, disableGlanceCheck]))
    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new TallyView();
        _view = view;
        TallySender.schedule();
        return [view, new TallyDelegate(view)];
    }

    // The buttons or the sheet changed on the phone
    (:typecheck([disableBackgroundCheck, disableGlanceCheck]))
    function onSettingsChanged() as Void {
        var view = _view;
        if (view != null) {
            view.reload();
        }
        TallySender.schedule();
        WatchUi.requestUpdate();
    }

    // The background service sent a batch
    function onBackgroundData(data as PersistableType) as Void {
        WatchUi.requestUpdate();
    }
}
