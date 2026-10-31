---
name: watch-face-review
description: Design and adversarially review a Connect IQ watch face (or glance) in this repo until it is elegant, balanced and glanceable, using a four-reviewer team (typography, spacing/feng shui, nature/art direction, glanceability skeptic) on preview renders with sample data and then on the real simulator. Use when building a new face, redesigning one, or when the owner says a face looks messy, unbalanced, or asks for a design review or "the team".
---

# Watch face design review

The loop that took Strata from "messy" to wearable (2026-10-30, eight
rounds): render the face with realistic sample data, have four adversarial
reviewers attack it from different lenses, fix, re-render, repeat until all
four pass, then port to Monkey C and confirm on the simulator. Read
`references/pitfalls.md` before the first render; it holds the platform
traps that cost rounds last time.

## 1. Previews with sample data (before any reviewer)

The simulator shows almost no data (no heart-rate history, distance,
alarms, weather), so a face judged there looks empty or wrong. Write
`designs/preview_<app>.py` (Pillow; see `designs/preview_strata.py` for the
pattern): it draws the face from the same layout fractions and generated
tables as the view, with the watch's own TTFs from
`~/Library/Application Support/Garmin/ConnectIQ/Fonts`, at 4x and scaled
down, and fills in sample readings: a day sample and a night sample with
different values (e.g. 14:38, sunset 19:22, 46°F, HR 72, 3.4 mi, one alarm,
waning gibbous; and 21:05, sunrise 07:12, 28°F, HR 58, 0.4 mi, no alarm,
waxing crescent). Render day, night, always-on, and 416 px, each at 1x and
2x. Every setting the face has gets a CLI switch (`strata=1 accent=4`), and
a contact sheet of all options goes to reviewers and the owner. Pillow
lives in a scratchpad venv (`python3 -m venv`, `pip install pillow`, run
with `-I`).

Also give the face a sample build: `(:live)`/`(:sample)` variants of a
`sample()` function, `base.excludeAnnotations = sample` in `monkey.jungle`,
`base.excludeAnnotations = live` in `sample.jungle`, built with
`CIQ_JUNGLE="monkey.jungle;sample.jungle" scripts/build.sh <app> <device>`.

## 2. The team

Spawn four `general-purpose` agents in one message, each with the shared
brief (`references/brief-template.md`, filled in) plus its lens from
`references/lenses.md`. They only look, measure and report; they never
edit the repo. Keep their IDs: later rounds go to the same agents with
`SendMessage`, so each re-checks its own earlier findings ("fixed /
remaining") instead of starting cold. Write each round's brief to a file in
the scratchpad and send the path.

Rounds:
- Round 1 on the first renders. Expect 5–6/10 from everyone; that is the
  point.
- Apply fixes where reviewers agree; where they conflict, prefer the
  owner's words, then the measured finding over the taste one. Owner
  feedback that arrives mid-round overrides the team; tell the team in the
  next brief, quoted verbatim, and say what is now off the table.
- Each later round: a short brief listing what changed (with numbers),
  new render paths, "re-check your findings", a word limit, PASS/FAIL.
- Send narrow changes only to the lenses they touch (colours: nature and
  spacing; icons: typography and skeptic) to save time; the spacing
  reviewer measures everything and is slow (up to 90 minutes).
- Stop when every lens passes on the real simulator capture. Tell them to
  "fail only for something a careful designer would still change", or
  polish rounds never end.

## 3. Port and confirm on the watch

Port to the view, build all three devices, run the tests, then capture the
sample build on the simulator with `scripts/sim-shot.sh` (in this skill;
needs the sandbox off). Compare the capture with the previews before
sending it out: the first real capture of Strata showed every text 15 %
smaller than the approved previews (pitfalls). Send the capture to all four
for a final round; a reviewer who failed for a now-fixed reason gets a
short confirmation request.

## 4. Tell the owner

Report scores per lens, the decisions the team forced (what was rejected
and why), the remaining polish, and what was not verified (always-on can't
be driven in the simulator). Show the simulator capture, and the contact
sheet when there are settings. Record new platform lessons in
`references/pitfalls.md`.
