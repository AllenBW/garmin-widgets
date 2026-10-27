import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

module Lib {

    // Text formatting: numbers, durations, units.
    (:fmt)
    module Fmt {

        // 8412 -> "8,412"
        function thousands(n as Number) as String {
            if (n < 0) {
                return "-" + thousands(-n);
            }
            if (n < 1000) {
                return n.toString();
            }
            return thousands(n / 1000) + "," + (n % 1000).format("%03d");
        }

        // Hours -> "6d 4h", "14h", "45m"
        function duration(hours as Float) as String {
            if (hours < 1.0) {
                return (hours * 60).toNumber().toString() + "m";
            }
            var whole = hours.toNumber();
            if (whole < 24) {
                return whole.toString() + "h";
            }
            return (whole / 24).toString() + "d " + (whole % 24).toString() + "h";
        }

        // Seconds since midnight -> "6:52" or "17:41", following the 12/24 h setting
        function clock(secondsSinceMidnight as Number) as String {
            var hour = (secondsSinceMidnight / 3600) % 24;
            var min = (secondsSinceMidnight / 60) % 60;
            if (!System.getDeviceSettings().is24Hour) {
                hour = hour % 12;
                if (hour == 0) {
                    hour = 12;
                }
            }
            return Lang.format("$1$:$2$", [hour.format("%d"), min.format("%02d")]);
        }

        // Centimetres -> "3.2 km" or "2.0 mi", following the device setting
        function distance(cm as Number) as String {
            var metric = System.getDeviceSettings().distanceUnits == System.UNIT_METRIC;
            var value = metric ? cm / 100000.0 : cm / 160934.4;
            return value.format("%.1f") + (metric ? " km" : " mi");
        }

        // Celsius -> "18°" or "64°", following the device setting
        function temperature(celsius as Numeric) as String {
            var metric = System.getDeviceSettings().temperatureUnits == System.UNIT_METRIC;
            var value = metric ? celsius : celsius * 9.0 / 5.0 + 32.0;
            return Math.round(value).toNumber().toString() + "°";
        }

        // A TrueType font at `size` pixels, or `fallback` when the device has no
        // vector fonts. Face names on the fenix 8 family (SDK 9.3 simulator):
        // RobotoRegular, RobotoMedium, RobotoCondensedRegular, RobotoCondensedBold,
        // BionicMedium, BionicBold.
        function vectorFont(face as String, size as Number, fallback as FontType) as FontType {
            if (!(Graphics has :getVectorFont)) {
                return fallback;
            }
            try {
                var font = Graphics.getVectorFont({:face => face, :size => size});
                return (font != null) ? font : fallback;
            } catch (e) {
                return fallback;
            }
        }

        // The first font in `fonts` that fits `text` within maxWidth pixels,
        // or the last one if none does.
        function fitFont(dc as Dc, text as String, fonts as Array<FontType>, maxWidth as Number) as FontType {
            for (var i = 0; i < fonts.size(); i++) {
                if (dc.getTextWidthInPixels(text, fonts[i]) <= maxWidth) {
                    return fonts[i];
                }
            }
            return fonts[fonts.size() - 1];
        }
    }
}
