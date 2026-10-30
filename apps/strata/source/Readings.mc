import Toybox.Activity;
import Toybox.Complications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.SensorHistory;
import Toybox.System;

// What a reading slot can show (the Slot1..Slot4 settings): each kind's
// number and unit, and the native widget a press opens. The view draws
// each kind's cue.
module Readings {

    enum Kind {
        TEMPERATURE,     // °F, always (the owner's choice)
        RAIN,            // the chance of rain, %
        HEART,           // bpm
        DISTANCE,        // walked today, mi or km
        BODY_BATTERY,    // 0 to 100
        ELEVATION,       // ft or m, as the watch is set
        HUMIDITY,        // %
        WIND,            // mph or km/h
        BATTERY,         // the watch's own, %
        STEPS            // today
    }

    const COUNT = 10;
    const DEFAULTS = [TEMPERATURE, RAIN, HEART, DISTANCE] as Array<Number>;

    // [number, unit] for a kind; "--" when the watch has nothing yet
    function read(kind as Number, celsius as Float?) as [String, String] {
        switch (kind) {
            case TEMPERATURE:
                return [(celsius != null) ? Math.round(celsius * 9.0 / 5.0 + 32.0).toNumber().toString() : "--", "°F"];
            case RAIN:
                return [orDashes(Lib.Daily.rainChance()), "%"];
            case HEART:
                return [Lib.Daily.heartRate(), "bpm"];
            case DISTANCE:
                return [Lib.Daily.distance(), Lib.Fmt.distanceUnit()];
            case BODY_BATTERY:
                return [orDashes(bodyBattery()), ""];
            case ELEVATION:
                return elevation();
            case HUMIDITY:
                return [orDashes(Lib.Daily.humidity()), "%"];
            case WIND:
                return Lib.Daily.wind();
            case BATTERY:
                return [Lib.Daily.watchBattery().toString(), "%"];
            case STEPS:
                var steps = Lib.Daily.steps();
                return [(steps != null) ? Lib.Fmt.compact(steps) : "--", ""];
        }
        return ["--", ""];
    }

    // The native widget to open for a press on a kind
    function complication(kind as Number) as Complications.Type {
        switch (kind) {
            case TEMPERATURE:
                return Complications.COMPLICATION_TYPE_CURRENT_TEMPERATURE;
            case HEART:
                return Complications.COMPLICATION_TYPE_HEART_RATE;
            case DISTANCE:
            case STEPS:
                return Complications.COMPLICATION_TYPE_STEPS;
            case BODY_BATTERY:
                return Complications.COMPLICATION_TYPE_BODY_BATTERY;
            case ELEVATION:
                return Complications.COMPLICATION_TYPE_ALTITUDE;
            case BATTERY:
                return Complications.COMPLICATION_TYPE_BATTERY;
        }
        return Complications.COMPLICATION_TYPE_CURRENT_WEATHER;   // rain, humidity, wind
    }

    // The kind the watch face editor's choice of complication means; null
    // for one Strata doesn't offer. The weather shows the chance of rain and
    // steps the miles walked, the owner's two everyday readings.
    function fromComplication(type as Complications.Type) as Number? {
        switch (type) {
            case Complications.COMPLICATION_TYPE_CURRENT_TEMPERATURE:
                return TEMPERATURE;
            case Complications.COMPLICATION_TYPE_CURRENT_WEATHER:
                return RAIN;
            case Complications.COMPLICATION_TYPE_HEART_RATE:
                return HEART;
            case Complications.COMPLICATION_TYPE_STEPS:
                return DISTANCE;
            case Complications.COMPLICATION_TYPE_BODY_BATTERY:
                return BODY_BATTERY;
            case Complications.COMPLICATION_TYPE_ALTITUDE:
                return ELEVATION;
            case Complications.COMPLICATION_TYPE_BATTERY:
                return BATTERY;
        }
        return null;
    }

    // The setting for slot `n` (0 to 3) as a kind, the default if unset or unknown
    function kind(value as Object?, n as Number) as Number {
        return (value instanceof Number && value >= 0 && value < COUNT) ? value : DEFAULTS[n];
    }

    function orDashes(n as Number?) as String {
        return (n != null) ? n.toString() : "--";
    }

    // The newest Body Battery sample, 0 to 100, or null
    function bodyBattery() as Number? {
        if (!(Toybox has :SensorHistory) || !(Toybox.SensorHistory has :getBodyBatteryHistory)) {
            return null;
        }
        var sample = SensorHistory.getBodyBatteryHistory({:period => 1, :order => SensorHistory.ORDER_NEWEST_FIRST}).next();
        return (sample != null && sample.data != null) ? (sample.data as Numeric).toNumber() : null;
    }

    // [number, unit]: the altitude now, else the newest logged, in feet or
    // metres as the watch is set; thousands of feet compacted ("12.3k")
    function elevation() as [String, String] {
        var feet = System.getDeviceSettings().elevationUnits == System.UNIT_STATUTE;
        var unit = feet ? "ft" : "m";
        var info = Activity.getActivityInfo();
        var metres = (info != null) ? info.altitude : null;
        if (metres == null && (Toybox has :SensorHistory) && (Toybox.SensorHistory has :getElevationHistory)) {
            var sample = SensorHistory.getElevationHistory({:period => 1, :order => SensorHistory.ORDER_NEWEST_FIRST}).next();
            metres = (sample != null && sample.data != null) ? (sample.data as Numeric).toFloat() : null;
        }
        if (metres == null) {
            return ["--", unit];
        }
        return [Lib.Fmt.compact(Math.round(feet ? metres * 3.28084 : metres).toNumber()), unit];
    }
}
