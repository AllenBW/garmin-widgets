import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// Minimal AMOLED-aware watch face.
// High power: full layout with a battery ring, date, steps and heart rate.
// Low power (always-on): time only, thin and dim, shifted every minute so no
// pixel stays lit longer than the 3 minute burn-in limit.
class StarterFaceView extends WatchUi.WatchFace {

    private var _isAwake as Boolean = true;
    private var _burnInProtection as Boolean = false;

    function initialize() {
        WatchFace.initialize();
        var settings = System.getDeviceSettings();
        _burnInProtection = (settings has :requiresBurnInProtection) && settings.requiresBurnInProtection;
    }

    function onUpdate(dc as Dc) as Void {
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        if (!_isAwake && _burnInProtection) {
            drawLowPower(dc);
        } else {
            drawActive(dc);
        }
    }

    function onEnterSleep() as Void {
        _isAwake = false;
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        _isAwake = true;
        WatchUi.requestUpdate();
    }

    private function drawActive(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        var accent = getAccentColor();

        // Battery ring
        var battery = System.getSystemStats().battery;
        var radius = cx - 8;
        dc.setPenWidth(6);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, radius);
        var sweep = (battery * 3.6).toNumber();
        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        if (sweep >= 360) {
            dc.drawCircle(cx, cy, radius);
        } else if (sweep > 0) {
            // Clockwise from 12 o'clock
            dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, 90, (450 - sweep) % 360);
        }

        // Date
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var dateStr = Lang.format("$1$ $2$ $3$", [info.day_of_week, info.month, info.day]);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.24, Graphics.FONT_SMALL, dateStr, Graphics.TEXT_JUSTIFY_CENTER);

        // Time
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy, Graphics.FONT_NUMBER_THAI_HOT, getTimeString(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Steps and heart rate
        var steps = ActivityMonitor.getInfo().steps;
        var stepsStr = steps != null ? steps.toString() : "--";
        var hrStr = "--";
        var activityInfo = Activity.getActivityInfo();
        if (activityInfo != null) {
            var hr = activityInfo.currentHeartRate;
            if (hr != null) {
                hrStr = hr.toString();
            }
        }
        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.68, Graphics.FONT_SMALL, stepsStr + " steps   " + hrStr + " bpm",
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawLowPower(dc as Dc) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;

        // Walk the time around a small 5x5 grid of offsets, one step per minute
        var min = System.getClockTime().min;
        var dx = ((min % 5) - 2) * 6;
        var dy = (((min / 5) % 5) - 2) * 6;

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + dx, cy + dy, Graphics.FONT_NUMBER_MEDIUM, getTimeString(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function getTimeString() as String {
        var clock = System.getClockTime();
        var hour = clock.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) {
                hour = 12;
            }
        }
        return Lang.format("$1$:$2$", [hour.format("%d"), clock.min.format("%02d")]);
    }

    private function getAccentColor() as Number {
        var value = Application.Properties.getValue("AccentColor");
        return value instanceof Number ? value : 0xE07A1F;
    }
}
