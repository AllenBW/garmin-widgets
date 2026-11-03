# Tally's Google Sheet

Every tap on the watch also goes to a Google Sheet of your own, a row per
entry, through a small Apps Script web app. The watch keeps the last
6,000 entries itself either way; the sheet is for keeping everything,
your own analysis, and sharing.

## Set up (once, about five minutes)

1. Make a new Google Sheet (sheets.new). Give it a plain title; there's
   no need to name a person in it.
2. Extensions → Apps Script. Replace the editor's contents with
   [`Tally.gs`](Tally.gs) and save.
3. Optional: choose `test` in the toolbar and Run, and allow access when
   asked. A "Log" tab appears with one row, "Test"; delete the row.
4. Deploy → New deployment → type **Web app**. Execute as **Me**, who has
   access **Anyone** (the watch can't sign in to Google). Deploy and copy
   the **Web app URL** (it ends in `/exec`).
5. On the phone: Garmin Connect → the watch → Connect IQ apps → Tally →
   Settings → **Google Sheet link**, paste the link, save.

The watch sends what the sheet hasn't confirmed about 15 seconds after a
tap (after the undo window), whenever the app opens, and every 15
minutes in the background while anything is waiting. It needs the phone
nearby (or Wi-Fi).

## Tabs

**Log**: a row per entry. When (date and time), Day, Time, Button, Unix
(seconds), Watch (which watch sent it), Entry (its number on that watch),
Note (empty: yours to fill in on the phone). An entry changed or deleted
in the watch's History is changed or deleted here too (the Note stays).

**Summary**: rebuilt after every batch from the last 28 days, for
whatever buttons the log holds (or Tally → Update summary in the
sheet's menu):
- each button's entries, days, usual time (the busiest two hours, as on
  the watch), how many days it fell within them, and the last entry;
- what came before: for each button with three or more entries, every
  other button that came within six hours before it at least twice, how
  often, the usual gap, and how often it came before the same time on
  days without the event. A routine that comes before everything shows
  up just as often on the days without, so compare the two;
- counts by hour of the day (as a heat map) and by day.

It shows what happened together, not what caused what. To share it with
someone (a doctor, say), share the sheet, or File → Download → PDF with
the Summary tab selected.

## Privacy

The link can only add rows: nothing in the sheet can be read through
it, but anyone who has the link could add rows, so keep it to yourself.
The sheet sits in your own Google account, under your control, and is
yours to look after, the more so if it holds someone's health
information. A changed script needs Deploy → Manage deployments → edit →
new version; the link stays the same.
