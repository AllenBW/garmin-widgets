import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Weather;

module Lib {

    // What the faces made of numbers share (Blocks, Wall): the readings as
    // text, one colour per family of readings in every look, and rows of
    // numbers sized to reach the bezel. No labels: size, weight, colour and
    // place tell the numbers apart. Uses Daily, Fmt, Ink, Look, Slots and
    // Sun, so a face links those too.
    (:numbers)
    module Numbers {

        enum Value { DATE, HOURS, MINUTES, SUN_TIME, COUNTDOWN, TEMP, HIGH, LOW, HEART, STEPS, BODY, ALTITUDE, WIND }
        const VALUES = 13;

        // The daily look's personas, in the order of `colors`
        const NAMES = ["GOLD", "EMBER", "ORCHARD", "DUSK", "BLAZE", "VOLT", "FLARE"] as Array<String>;

        // [neutral (time, date), sun, weather, body, lesser reading's share,
        // least reading's share, fluorescent]
        const YOURS = [0xF2ECE2, 0xFFB020, 0x4DB2FF, 0xFF5C9E, 0.86, 0.70, false] as Array<Number or Float or Boolean>;
        const LOW_LIGHT = [Look.CREAM, Look.GLOW, 0xD9C08F, 0xE8785A, 0.85, 0.70, false] as Array<Number or Float or Boolean>;
        const HI_VIS_ORANGE = [Look.WHITE, Look.BLAZE, 0xFFD21A, 0xFF3D6E, 1.0, 1.0, true] as Array<Number or Float or Boolean>;
        const HI_VIS_BLUE = [Look.WHITE, Look.ARC, 0x2EF0E0, 0xB48CFF, 1.0, 1.0, true] as Array<Number or Float or Boolean>;
        const HI_VIS_GREEN = [Look.WHITE, Look.VOLT, Look.FLARE, 0x2EF0B0, 1.0, 1.0, true] as Array<Number or Float or Boolean>;
        const PERSONAS = [
            [0xE6CFA0, 0xFFB020, 0x2EE6B0, 0xFF5A36, 0.86, 0.70, false],
            [0xE6CFA0, 0xFF5A36, 0xE8D44A, 0xFF5C9E, 0.86, 0.70, false],
            [0xF2ECE2, 0x8CE03C, 0x2EE6B0, 0xE8D44A, 0.86, 0.70, false],
            [0xF8D2D8, 0xA77BFF, 0x38A8FF, 0xFF5C9E, 0.86, 0.70, false],
            HI_VIS_ORANGE,
            HI_VIS_GREEN,
            [Look.WHITE, Look.FLARE, 0x2EE6B0, 0xFF4F7A, 1.0, 1.0, true]
        ] as Array<Array<Number or Float or Boolean>>;

        // A digit's, a colon's, a slash's and a minus's advance in thousandths
        // of an em, one row per Ink face (Bionic Bold and Medium, then the
        // faces that stand in for them where a watch has no Bionic), from the TTFs
        const ADVANCE = [
            [516, 204, 409, 312],
            [500, 194, 400, 312],
            [506, 274, 331, 363],
            [494, 233, 371, 248],
            [568, 264, 390, 340],
            [621, 181, 443, 375],
            [562, 242, 412, 276],
            [507, 227, 374, 247],
            [621, 181, 443, 375]
        ] as Array<Array<Number>>;
        const DEGREE = 0.30;       // the width a degree sign adds, per digit height
        // The least room each reading takes in its row, in the order of Value:
        // 0 steps in the morning mustn't balloon its row and squeeze the next
        const LEAST = ["00/00", "00", "00", "00:00", "0:00", "00°", "00", "00", "00", "0000", "00", "0000", "00"] as Array<String>;

        // The colours of a look, as a Colors
        function colors(mode as Number) as Colors {
            var c = YOURS;
            if (mode == Look.BRIGHT) {
                c = HI_VIS_ORANGE;
            } else if (mode == Look.BRIGHT_BLUE) {
                c = HI_VIS_BLUE;
            } else if (mode == Look.BRIGHT_GREEN) {
                c = HI_VIS_GREEN;
            } else if (mode == Look.LOW) {
                c = LOW_LIGHT;
            } else if (mode == Look.DAILY) {
                c = PERSONAS[Look.day(PERSONAS.size())];
            }
            return new Colors(c);
        }

        // ------------------------------------------------------------ readings

        // Every reading as text, in the order of Value
        function read() as Array<String> {
            var out = new [VALUES] as Array<String>;
            var clock = System.getClockTime();
            var now = clock.hour * 3600 + clock.min * 60;
            var date = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
            out[DATE] = dateText(date.month as Number, date.day as Number);
            out[HOURS] = clock.hour.format("%02d");      // 24-hour, two digits, always
            out[MINUTES] = clock.min.format("%02d");
            var next = Lib.Sun.next(Lib.Sun.today());
            out[SUN_TIME] = (next != null) ? Lib.Fmt.clock24(next[1]) : "--:--";
            out[COUNTDOWN] = (next != null) ? countdown(now, next[1]) : "--:--";
            out[TEMP] = Lib.Slots.temperature()[0];
            var conditions = (Toybox has :Weather) ? Weather.getCurrentConditions() : null;
            out[HIGH] = temperature((conditions != null) ? conditions.highTemperature : null);
            out[LOW] = temperature((conditions != null) ? conditions.lowTemperature : null);
            out[HEART] = Lib.Daily.heartRate();
            out[STEPS] = Lib.Slots.dashes(Lib.Daily.steps());
            out[BODY] = Lib.Slots.dashes(Lib.Slots.bodyBattery(new Complications.Id(Complications.COMPLICATION_TYPE_BODY_BATTERY)));
            out[ALTITUDE] = Lib.Slots.altitude()[0];
            out[WIND] = Lib.Daily.wind()[0];
            return out;
        }

        // "10/31": numbers only, month then day, no year
        function dateText(month as Number, day as Number) as String {
            return month.toString() + "/" + day.toString();
        }

        // From `now` to an event, both seconds since midnight, as "4:44";
        // an event already past today is tomorrow's
        function countdown(now as Number, event as Number) as String {
            var left = event - now;
            if (left < 0) {
                left += 86400;
            }
            return (left / 3600).toString() + ":" + ((left / 60) % 60).format("%02d");
        }

        function temperature(celsius as Numeric?) as String {
            return (celsius != null) ? Lib.Fmt.temperatureValue(celsius) : "--";
        }

        // Every digit of the readings in turn, the texture of Wall
        function stream(values as Array<String>) as Array<Number> {
            var order = [HOURS, MINUTES, SUN_TIME, COUNTDOWN, TEMP, HEART, HIGH, LOW, DATE, BODY, STEPS] as Array<Number>;
            var out = [] as Array<Number>;
            for (var i = 0; i < order.size(); i++) {
                var chars = values[order[i]].toCharArray();
                for (var j = 0; j < chars.size(); j++) {
                    var d = chars[j].toNumber() - 48;
                    if (d >= 0 && d <= 9) {
                        out.add(d);
                    }
                }
            }
            if (out.size() == 0) {
                out.add(0);
            }
            return out;
        }

        // -------------------------------------------------------------- layout

        // A number's width per digit height, from zeros, so a row keeps its
        // size while the digits change; dashes count as the digits they stand for
        function ratio(text as String, face as Number) as Float {
            var chars = text.toCharArray();
            var advance = ADVANCE[face];
            var sum = 0;
            var extra = 0.0;
            for (var i = 0; i < chars.size(); i++) {
                var c = chars[i];
                if (c == ':') {
                    sum += advance[1];
                } else if (c == '/') {
                    sum += advance[2];
                } else if (c == 0x00B0.toChar()) {
                    extra = DEGREE;
                } else if (c == '-' && i == 0 && chars.size() > 1 && chars[1] != '-') {
                    sum += advance[3];
                } else {
                    sum += advance[0];
                }
            }
            return sum.toFloat() / (Lib.Ink.TOP[face] - Lib.Ink.BOTTOM[face]) + extra;
        }

        function half(y as Float, margin as Float) as Float {
            var r = 0.5 - margin;
            var d = r * r - (y - 0.5) * (y - 0.5);
            return (d <= 0.0) ? 0.0 : Math.sqrt(d).toFloat();
        }

        // The tallest row (as a fraction of the screen) that fits where its
        // width `perHeight` × h + `gaps` meets the bezel. `edge` is the row's
        // inner edge, as far from the screen's middle as it is, the row
        // growing away from the middle. `side` is the fixed edge's distance
        // from the vertical centre line, the row running from it to the
        // bezel, on the far side of it; null for a row across the whole chord.
        function fit(perHeight as Float, gaps as Float, edge as Float, side as Float?, margin as Float) as Float {
            var r = (side == null) ? perHeight / 2.0 : perHeight;
            var a = (side == null) ? -gaps / 2.0 : -(side + gaps);
            var radius = 0.5 - margin;
            var d0 = -edge.abs();
            var qa = r * r + 1.0;
            var qb = 2.0 * a * r + 2.0 * d0;
            var qc = a * a + d0 * d0 - radius * radius;
            var disc = qb * qb - 4.0 * qa * qc;
            if (disc < 0.0 || qc > 0.0) {
                return 0.0;
            }
            return ((qb + Math.sqrt(disc).toFloat()) / (2.0 * qa)).toFloat();
        }

        // Sets a row's items from x0 to x1 (fractions) at height h, top y,
        // the slack in the gaps: the first flush left, the last flush right
        function place(dc as Dc, pieces as Array<Piece>, targets as Array<Target>, items as Array<Item>, h as Float,
                       x0 as Float, x1 as Float, y as Float) as Void {
            var w = dc.getWidth().toFloat();
            var total = 0.0;
            for (var i = 0; i < items.size(); i++) {
                total += ratio(items[i].room, items[i].face) * h;
            }
            var slack = (x1 - x0 - total > 0.0) ? x1 - x0 - total : 0.0;
            var gap = (items.size() > 1) ? slack / (items.size() - 1) : 0.0;
            var x = x0;
            for (var i = 0; i < items.size(); i++) {
                var item = items[i];
                var slot = ratio(item.room, item.face) * h;
                pieces.add(new Piece(dc, item, h, x, slot, y, w,
                                     (items.size() == 1) ? 1 : ((i == 0) ? 0 : ((i == items.size() - 1) ? 2 : 1))));
                if (item.type != null) {
                    targets.add(new Target(x * w, y * w, (x + slot) * w, (y + h) * w, item.type as Complications.Type));
                }
                x += slot + gap;
            }
        }

        // A reading to set in a row, with the room it takes at least
        function reading(values as Array<String>, value as Number, face as Number, color as Number,
                         type as Complications.Type?) as Item {
            // Where the watch has none of the Bionic faces (the Venu 3, the
            // Forerunner 570), the nearest face it has draws and measures the
            // row (Lib.Ink.CHAIN); on the fenix 8 the face is its own
            face = Lib.Ink.resolve(face);
            var item = new Item(values[value], face, color, type);
            if (ratio(LEAST[value], face) > ratio(item.text, face)) {
                item.room = LEAST[value];
            }
            return item;
        }

        // The vector font for digits h × w tall, kept while its size lasts
        var fonts as Dictionary<Number, FontType> = {} as Dictionary<Number, FontType>;

        function font(face as Number, size as Number) as FontType {
            var key = size * 10 + face;
            var f = fonts[key];
            if (f == null) {
                f = Lib.Ink.font(face, size * 1000.0 / Lib.Ink.HEIGHT[face], Graphics.FONT_NUMBER_HOT);
                fonts[key] = f;
            }
            return f as FontType;
        }

        function fontSize(face as Number, digits as Float) as Number {
            return Math.round(Lib.Ink.em(face, digits) * Lib.Ink.HEIGHT[face] / 1000.0).toNumber();
        }

        function scale(color as Number, f as Float) as Number {
            var out = 0;
            for (var shift = 16; shift >= 0; shift -= 8) {
                out = out | ((((color >> shift) & 0xFF) * f).toNumber() << shift);
            }
            return out;
        }

        // The colours of a look
        class Colors {
            var neutral as Number;
            var sun as Number;
            var weather as Number;
            var body as Number;
            var second as Float;
            var third as Float;
            var fluorescent as Boolean;

            function initialize(c as Array<Number or Float or Boolean>) {
                neutral = c[0] as Number;
                sun = c[1] as Number;
                weather = c[2] as Number;
                body = c[3] as Number;
                second = c[4] as Float;
                third = c[5] as Float;
                fluorescent = c[6] as Boolean;
            }
        }

        // A reading to set: its text, typeface, colour, and the complication
        // a press and hold on it opens
        class Item {
            var text as String;
            var face as Number;
            var color as Number;
            var type as Complications.Type?;
            var room as String;             // what its width in the row is measured from

            function initialize(text_ as String, face_ as Number, color_ as Number, type_ as Complications.Type?) {
                text = text_;
                room = text_;
                face = face_;
                color = color_;
                type = type_;
            }
        }

        // Where a press and hold opens a complication
        class Target {
            var x0 as Float;
            var y0 as Float;
            var x1 as Float;
            var y1 as Float;
            var type as Complications.Type;

            function initialize(x0_ as Float, y0_ as Float, x1_ as Float, y1_ as Float, type_ as Complications.Type) {
                x0 = x0_;
                y0 = y0_;
                x1 = x1_;
                y1 = y1_;
                type = type_;
            }

            function contains(x as Number, y as Number) as Boolean {
                return x >= x0 && x <= x1 && y >= y0 && y <= y1;
            }
        }

        // A number placed on the screen, its degree sign a small ring
        class Piece {
            var text as String;
            var font as FontType;
            var x as Float;
            var y as Float;
            var color as Number;
            var ringX as Float = 0.0;
            var ringY as Float = 0.0;
            var ringR as Float = 0.0;
            var ringPen as Number = 1;

            // `align` 0 from the slot's left, 1 centred, 2 to its right
            function initialize(dc as Dc, item as Item, h as Float, slotX as Float, slot as Float, top as Float, w as Float,
                                align as Number) {
                var whole = item.text;
                var degree = whole.find("°") != null;
                text = degree ? whole.substring(0, whole.length() - 1) as String : whole;
                color = item.color;
                var size = fontSize(item.face, h * w);
                font = Numbers.font(item.face, size);
                var em = size * 1000.0 / Lib.Ink.HEIGHT[item.face];
                var advance = dc.getTextWidthInPixels(text, font).toFloat();
                var width = (slot - (degree ? DEGREE * h : 0.0)) * w;
                x = slotX * w + ((align == 0) ? 0.0 : ((align == 1) ? (width - advance) / 2.0 : width - advance));
                y = Lib.Ink.top(item.face, font, (top + h / 2.0) * w, em);
                if (degree) {
                    ringR = 0.115 * h * w;
                    ringX = x + advance + DEGREE * 0.62 * h * w;
                    ringY = top * w + ringR;
                    ringPen = (0.052 * h * w).toNumber();
                    ringPen = (ringPen < 1) ? 1 : ringPen;
                }
            }

            // Filled, or `hollow` as a thin outline, shifted by (ox, oy)
            function draw(dc as Dc, ox as Number, oy as Number, hollow as Boolean) as Void {
                if (hollow) {
                    Lib.Aod.drawHollowText(dc, x + ox, y + oy, font, text, color, Graphics.TEXT_JUSTIFY_LEFT);
                } else {
                    dc.setColor(color, Graphics.COLOR_TRANSPARENT);
                    dc.drawText(x + ox, y + oy, font, text, Graphics.TEXT_JUSTIFY_LEFT);
                }
                if (ringR > 0.0) {
                    var pen = hollow ? 1 : ringPen;
                    dc.setColor(color, Graphics.COLOR_TRANSPARENT);
                    dc.setPenWidth(pen);
                    dc.drawCircle(ringX + ox, ringY + oy, ringR - pen / 2.0);
                    dc.setPenWidth(1);
                }
            }
        }
    }
}
