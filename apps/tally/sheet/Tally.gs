// Tally's sheet: receives the watch's entries and appends them to the
// "Log" tab, one row each. Set up once (sheet/README.md): paste this into
// the sheet's Apps Script, deploy it as a web app, and put its link in
// Garmin Connect (Tally's settings, Google Sheet link).
//
// The watch sends GET ?id=<watch>&from=<first entry's number>&e=<lines>,
// each line "<unix seconds>|<button name>" (an empty name is an entry
// deleted before it was sent: counted, not written). The script
// remembers, per watch, the number of the next entry it wants, so a batch
// that arrives twice is written once, and answers {"ok": true, "next": n}.
// Changes made in the watch's History come as op=edit, each line
// "<entry number>|<unix seconds>|<name>" (empty: delete the row), answered
// {"ok": true, "edited": lines}. Nothing in the sheet can be read through
// the link.
//
// After each batch it rebuilds the "Summary" tab from the last DAYS days,
// for whatever buttons the log holds: each button's count and usual time,
// counts by hour and by day, and which buttons tend to come before which.

var TAB = 'Log';
var SUMMARY = 'Summary';
var DAYS = 28;
var WINDOW = 2 * 3600;   // "usually": the busiest two hours of the day
var BEFORE = 6 * 3600;   // "came before": within six hours
var HEADERS = ['When', 'Day', 'Time', 'Button', 'Unix', 'Watch', 'Entry', 'Note'];

function doGet(e) {
  var p = e.parameter;
  var lock = LockService.getScriptLock();
  lock.waitLock(10000);
  try {
    if (p.op === 'edit') {
      return json({ok: true, edited: edit(p)});
    }
    var props = PropertiesService.getScriptProperties();
    var key = 'next_' + p.id;
    var next = Number(props.getProperty(key) || 0);
    var from = Number(p.from);
    var lines = String(p.e || '').split('\n').filter(String);
    var sheet = tab();
    var zone = Session.getScriptTimeZone();
    var rows = [];
    lines.forEach(function (line, i) {
      if (from + i < next) {
        return;  // already written
      }
      var bar = line.indexOf('|');
      var name = line.slice(bar + 1);
      if (name === '') {
        return;  // deleted on the watch before it was sent
      }
      rows.push(row(Number(line.slice(0, bar)), name, p.id, from + i, zone));
    });
    if (rows.length) {
      sheet.getRange(sheet.getLastRow() + 1, 1, rows.length, HEADERS.length).setValues(rows);
    }
    next = Math.max(next, from + lines.length);
    props.setProperty(key, String(next));
    if (rows.length) {
      try {
        summarize();
      } catch (err) {
        console.error(err);  // the entries are in; the summary waits for the next batch
      }
    }
    return json({ok: true, next: next});
  } finally {
    lock.releaseLock();
  }
}

function row(unix, name, watch, entry, zone) {
  var when = new Date(unix * 1000);
  return [when, Utilities.formatDate(when, zone, 'yyyy-MM-dd'), Utilities.formatDate(when, zone, 'HH:mm'),
          name, unix, watch, entry, ''];
}

// Changes from the watch's History: find each entry's row by watch and
// entry number, then rewrite it (keeping the Note) or delete it
function edit(p) {
  var lines = String(p.e || '').split('\n').filter(String);
  var sheet = tab();
  var zone = Session.getScriptTimeZone();
  var last = sheet.getLastRow();
  var keys = last < 2 ? [] : sheet.getRange(2, 6, last - 1, 2).getValues();
  var gone = [];
  lines.forEach(function (line) {
    var parts = line.split('|');
    var entry = Number(parts[0]);
    var unix = Number(parts[1]);
    var name = parts.slice(2).join('|');
    for (var r = 0; r < keys.length; r++) {
      if (String(keys[r][0]) === String(p.id) && Number(keys[r][1]) === entry) {
        if (name === '') {
          gone.push(r + 2);
        } else {
          var note = sheet.getRange(r + 2, 8).getValue();
          var fresh = row(unix, name, p.id, entry, zone);
          fresh[7] = note;
          sheet.getRange(r + 2, 1, 1, HEADERS.length).setValues([fresh]);
        }
        break;
      }
    }
  });
  gone.sort(function (a, b) { return b - a; }).forEach(function (r) { sheet.deleteRow(r); });
  try {
    summarize();
  } catch (err) {
    console.error(err);
  }
  return lines.length;
}

// The Log tab, made with its headers the first time
function tab() {
  var book = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = book.getSheetByName(TAB);
  if (!sheet) {
    sheet = book.insertSheet(TAB);
    sheet.appendRow(HEADERS);
    sheet.setFrozenRows(1);
    sheet.getRange('A:A').setNumberFormat('ddd d mmm yyyy h:mm am/pm');
  }
  return sheet;
}

function json(o) {
  return ContentService.createTextOutput(JSON.stringify(o)).setMimeType(ContentService.MimeType.JSON);
}

// ------------------------------------------------------------------ summary

function onOpen() {
  SpreadsheetApp.getUi().createMenu('Tally').addItem('Update summary', 'summarize').addToUi();
}

// The Summary tab, rebuilt from the Log tab's last DAYS days
function summarize() {
  var book = SpreadsheetApp.getActiveSpreadsheet();
  var log = book.getSheetByName(TAB);
  if (!log || log.getLastRow() < 2) {
    return;
  }
  var zone = Session.getScriptTimeZone();
  var since = Date.now() / 1000 - DAYS * 86400;
  var entries = log.getRange(2, 1, log.getLastRow() - 1, HEADERS.length).getValues()
    .filter(function (r) { return Number(r[4]) >= since && String(r[3]) !== ''; })
    .map(function (r) {
      var unix = Number(r[4]);
      var hms = Utilities.formatDate(new Date(unix * 1000), zone, 'H:m:s').split(':').map(Number);
      var sec = hms[0] * 3600 + hms[1] * 60 + hms[2];
      return {name: String(r[3]), unix: unix, sec: sec, midnight: unix - sec,
              day: Utilities.formatDate(new Date(unix * 1000), zone, 'yyyy-MM-dd')};
    })
    .sort(function (a, b) { return a.unix - b.unix; });

  var byName = {};
  entries.forEach(function (e) { (byName[e.name] = byName[e.name] || []).push(e); });
  var names = Object.keys(byName).sort(function (a, b) { return byName[b].length - byName[a].length; });
  var days = unique(entries.map(function (e) { return e.day; }));
  var midnightOf = {};
  entries.forEach(function (e) { midnightOf[e.day] = e.midnight; });

  var out = [];
  var heads = [];
  function heading(text) { out.push([]); heads.push(out.length); out.push([text]); }

  out.push(['Tally summary: the last ' + DAYS + ' days, ' + entries.length + ' entries on ' + days.length + ' days. Updated ' +
            Utilities.formatDate(new Date(), zone, 'EEE d MMM yyyy HH:mm') + '.']);
  out.push(['Counts show what happened together, not what caused what.']);

  heading('Buttons');
  out.push(['Button', 'Entries', 'Days', 'Usually', 'Days in its busiest two hours', 'Last']);
  var usualOf = {};
  names.forEach(function (n) {
    var list = byName[n];
    var u = usual(list.map(function (e) { return e.sec; }));
    usualOf[n] = u;
    var within = u ? unique(list.filter(function (e) { return circular(e.sec - u.start) < WINDOW; })
                                .map(function (e) { return e.day; })).length : '';
    out.push([n, list.length, unique(list.map(function (e) { return e.day; })).length, u ? clock(u.time) : '',
              within, Utilities.formatDate(new Date(list[list.length - 1].unix * 1000), zone, 'EEE d MMM HH:mm')]);
  });

  heading('What came before (within ' + BEFORE / 3600 + ' hours)');
  out.push(['Before', 'Event', 'Times', 'Of', 'Usually before by', 'On days without the event', 'Of those days']);
  names.forEach(function (event) {
    var list = byName[event];
    if (list.length < 3) {
      return;
    }
    var eventDays = unique(list.map(function (e) { return e.day; }));
    var controls = days.filter(function (d) { return eventDays.indexOf(d) < 0; });
    var at = usualOf[event] ? usualOf[event].time : median(list.map(function (e) { return e.sec; }));
    names.forEach(function (other) {
      if (other === event) {
        return;
      }
      var theirs = byName[other].map(function (e) { return e.unix; });
      var gaps = list.map(function (e) { return gapBefore(e.unix, theirs); }).filter(function (g) { return g !== null; });
      if (gaps.length < 2) {
        return;
      }
      var controlHits = controls.filter(function (d) { return gapBefore(midnightOf[d] + at, theirs) !== null; }).length;
      out.push([other, event, gaps.length, list.length, duration(median(gaps)), controls.length ? controlHits : '',
                controls.length || '']);
    });
  });

  heading('By hour of the day');
  out.push(['Hour'].concat(names));
  var hourStart = out.length;
  for (var h = 0; h < 24; h++) {
    out.push([clock(h * 3600)].concat(names.map(function (n) {
      return byName[n].filter(function (e) { return Math.floor(e.sec / 3600) === h; }).length || '';
    })));
  }

  heading('By day');
  out.push(['Day'].concat(names));
  days.slice().reverse().forEach(function (d) {
    out.push([d].concat(names.map(function (n) {
      return byName[n].filter(function (e) { return e.day === d; }).length || '';
    })));
  });

  var width = Math.max.apply(null, out.map(function (r) { return r.length; }));
  out = out.map(function (r) { while (r.length < width) { r.push(''); } return r; });
  var sheet = book.getSheetByName(SUMMARY) || book.insertSheet(SUMMARY);
  sheet.clear();
  sheet.clearConditionalFormatRules();
  sheet.getRange(1, 1, out.length, width).setValues(out);
  sheet.getRange(1, 1).setFontWeight('bold');
  heads.forEach(function (row) {
    sheet.getRange(row, 1).setFontWeight('bold').setFontSize(12);
    sheet.getRange(row + 1, 1, 1, width).setFontWeight('bold');
  });
  // the hour table as a heat map
  var block = sheet.getRange(hourStart + 1, 2, 24, Math.max(names.length, 1));
  sheet.setConditionalFormatRules([SpreadsheetApp.newConditionalFormatRule().setGradientMinpoint('#FFFFFF')
    .setGradientMaxpoint('#E8634F').setRanges([block]).build()]);
}

// The busiest WINDOW of the day (it may span midnight) and the average
// time inside it, as on the watch; null with fewer than two entries
function usual(secs) {
  if (secs.length < 2) {
    return null;
  }
  var s = secs.slice().sort(function (a, b) { return a - b; });
  var n = s.length;
  var at = function (k) { return k < n ? s[k] : s[k - n] + 86400; };
  var best = 0, start = 0, j = 0;
  for (var i = 0; i < n; i++) {
    if (j < i) { j = i; }
    while (j + 1 < i + n && at(j + 1) - s[i] < WINDOW) { j++; }
    if (j - i + 1 > best) { best = j - i + 1; start = i; }
  }
  var sum = 0;
  for (var k = start; k < start + best; k++) { sum += at(k); }
  return {time: Math.round(sum / best) % 86400, start: s[start], count: best};
}

// Seconds from the newest of `times` in the BEFORE hours ahead of `t`, or null
function gapBefore(t, times) {
  var best = null;
  times.forEach(function (u) {
    var gap = t - u;
    if (gap > 0 && gap <= BEFORE && (best === null || gap < best)) { best = gap; }
  });
  return best;
}

function unique(list) {
  return list.filter(function (v, i) { return list.indexOf(v) === i; });
}

function median(list) {
  var s = list.slice().sort(function (a, b) { return a - b; });
  return s[Math.floor(s.length / 2)];
}

function circular(seconds) {
  return ((seconds % 86400) + 86400) % 86400;
}

function clock(sec) {
  var m = Math.floor(circular(sec) / 60);
  return Math.floor(m / 60) + ':' + ('0' + (m % 60)).slice(-2);
}

function duration(sec) {
  var m = Math.round(sec / 60);
  return m < 60 ? m + ' min' : Math.floor(m / 60) + ' h ' + ('0' + (m % 60)).slice(-2);
}

// Run once from the editor to check the setup: writes one row, "Test"
function test() {
  var now = Math.floor(Date.now() / 1000);
  Logger.log(doGet({parameter: {id: 'editor', from: '0', e: now + '|Test\n'}}).getContent());
}
