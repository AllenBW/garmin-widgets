import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

// Sends the entries the sheet hasn't confirmed to the owner's Google Sheet
// (the Apps Script web app in apps/tally/sheet/), BATCH at a time, through
// the phone or Wi-Fi. The script answers with the number of the next entry
// it wants, so a batch that arrives twice is written once.
//
// Runs in the foreground (after a tap settles) and in the background
// service (every SYNC_MINUTES while anything is waiting).
(:background)
class TallySender {

    static const BATCH = 25;
    static const SETTLE = 15;           // seconds: the undo window, and a little
    static const SYNC_MINUTES = 15;

    private var _done as Method(ok as Boolean) as Void or Null;

    function initialize(done as Method(ok as Boolean) as Void or Null) {
        _done = done;
    }

    static function url() as String {
        var url = Properties.getValue("SheetUrl");
        return (url instanceof String) ? url : "";
    }

    // Start sending; false when there is nothing to send or nowhere to send it
    function send() as Boolean {
        var link = url();
        if (link.find("https://") != 0) {
            return false;
        }
        var batch = TallyLog.unsent(BATCH, Time.now().value() - SETTLE);
        if (batch == null) {
            return false;
        }
        var lines = "";
        for (var i = 0; i < batch[1].size(); i++) {
            lines += batch[1][i].toString() + "|" + clean(batch[2][i]) + "\n";
        }
        try {
            Communications.makeWebRequest(link,
                {"id" => TallyLog.installId(), "from" => batch[0].toString(), "e" => lines},
                {:method => Communications.HTTP_REQUEST_METHOD_GET,
                 :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON},
                method(:onResponse));
        } catch (e) {
            return false;
        }
        return true;
    }

    // A name may hold anything typed on the phone; the line format can't
    // hold a bar or a line break
    private function clean(name as String) as String {
        var out = "";
        var chars = name.toCharArray();
        for (var i = 0; i < chars.size(); i++) {
            var ch = chars[i];
            out += (ch == '|' || ch == '\n' || ch == '\r') ? " " : ch.toString();
        }
        return out;
    }

    function onResponse(code as Number, data as Dictionary or String or Null) as Void {
        var ok = false;
        if (code == 200 && data instanceof Dictionary) {
            var next = data["next"];
            if (next instanceof Number || next instanceof Float || next instanceof Long) {
                TallyLog.confirm(next.toNumber());
                ok = true;
            }
        }
        var done = _done;
        if (done != null) {
            done.invoke(ok);
        }
    }

    // Wake the background service while entries wait for the sheet, and not otherwise
    static function schedule() as Void {
        if (!(Toybox has :Background)) {
            return;
        }
        try {
            var waiting = TallyLog.sent() < TallyLog.count() && url().find("https://") == 0;
            var registered = Background.getTemporalEventRegisteredTime() != null;
            if (waiting && !registered) {
                Background.registerForTemporalEvent(new Time.Duration(SYNC_MINUTES * 60));
            } else if (!waiting && registered) {
                Background.deleteTemporalEvent();
            }
        } catch (e) {
            // the next start tries again
        }
    }
}

// The background service: send one batch, and stop waking once the sheet has everything
(:background)
class TallyService extends System.ServiceDelegate {

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        if (!new TallySender(method(:done)).send()) {
            done(false);
        }
    }

    function done(ok as Boolean) as Void {
        TallySender.schedule();
        Background.exit(ok);
    }
}
