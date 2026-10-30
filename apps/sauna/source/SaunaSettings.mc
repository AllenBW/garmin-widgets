import Toybox.Application.Properties;
import Toybox.Lang;
import Toybox.System;

// The settings from the phone (resources/settings), each with its default
// when a value is missing or odd. Shared by the glance and the app.
(:glance)
module SaunaSettings {

    function number(key as String, fallback as Number) as Number {
        try {
            var v = Properties.getValue(key);
            if (v instanceof Number) {
                return v;
            }
            if (v instanceof Float) {
                return v.toNumber();
            }
        } catch (e) {
        }
        return fallback;
    }

    function bool(key as String, fallback as Boolean) as Boolean {
        try {
            var v = Properties.getValue(key);
            if (v instanceof Boolean) {
                return v;
            }
        } catch (e) {
        }
        return fallback;
    }

    function clamp(v as Number, lo as Number, hi as Number) as Number {
        return v < lo ? lo : (v > hi ? hi : v);
    }

    // Fahrenheit by default; 1 is Celsius, 2 follows the watch
    function applyUnit() as Void {
        var unit = number("TempUnit", 0);
        if (unit == 2) {
            SaunaText.fahrenheit = System.getDeviceSettings().temperatureUnits != System.UNIT_METRIC;
        } else {
            SaunaText.fahrenheit = unit == 0;
        }
    }

    function meditation() as Boolean {
        return number("ActivityType", 0) == 0;
    }

    function autoRounds() as Boolean {
        return bool("AutoRounds", true);
    }

    // Tenths: 10 is the plan's rate as is, 6 more eager, 15 more relaxed
    function sensitivity() as Float {
        return clamp(number("DoorSensitivity", 10), 3, 30) / 10.0;
    }

    // Degrees C on the watch's own thermometer; 0 is off
    function hotTemp() as Float {
        var v = number("HotWatch", 50);
        return (v == 0 ? 0 : clamp(v, 40, 80)).toFloat();
    }

    // The plan for one kind, from its group of settings (minutes on the phone, seconds here)
    function plan(kind as Number) as SaunaPlan {
        var p = new SaunaPlan(kind);
        var k = kind == KIND_STEAM ? "Steam" : "Sauna";
        p.roundTarget = clamp(number(k + "Round", p.roundTarget / 60), 0, 60) * 60;
        p.roundMax = clamp(number(k + "Max", p.roundMax / 60), 0, 90) * 60;
        p.breakTarget = clamp(number(k + "Break", p.breakTarget / 60), 0, 60) * 60;
        p.rounds = clamp(number(k + "Rounds", p.rounds), 1, 12);
        p.heatCap = clamp(number(k + "Cap", p.heatCap / 60), 0, 180) * 60;
        p.weekSessions = clamp(number(k + "WeekSessions", p.weekSessions), 1, 14);
        p.weekMinutes = clamp(number(k + "WeekMinutes", p.weekMinutes), 1, 600);
        return p;
    }
}
