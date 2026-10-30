# <Face> watch face: design review brief

You are one reviewer on a small team adversarially verifying the design of
"<Face>", a Garmin fēnix 8 watch face (454×454 round AMOLED, also 416×416).
Your job is to find what is still wrong, not to approve. Assume it is not
yet good enough. Do not edit any files in the repo; you only look, measure
and report.

## What the owner asked for (verbatim)

<Paste the owner's own words: the latest request and any earlier ones that
still apply. Never paraphrase them.>

The owner's required data: <list>.

## What this version does

<Bullets: layout, how each value is shown, settings, what changed since the
last version and why.>

## Images (sample data, rendered by designs/preview_<app>.py)

- Day, 454 px: <path> (2x: <path>)
- Night: <path>
- Always-on: <path>
- 416 px: <path>
- Settings contact sheet: <path> (if any)
- BEFORE (the previous version, or a simulator capture): <path>
- Real watch (simulator, sample build): <path> (once ported)

Day sample: <values>. Night sample: <values>.

The physical screen is about 1.4 inches across; judge at that size (the 1x
PNG at about 100 % on a laptop is roughly wrist size at arm's length).
Pixels outside the circle do not exist.

## What the watch can and cannot do (keep fixes implementable)

Lines (1–3 px, anti-aliased), circles, ellipses, arcs, filled polygons,
rounded rectangles; text in these vector fonts at any pixel size:
RobotoCondensedBold, RobotoCondensedRegular, RobotoRegular, RobotoMedium,
RobotoItalic, BionicBold, BionicMedium, PridiRegular (a serif),
KosugiRegular; text along a circle. No gradients, no blur, no letter
tracking unless each letter is drawn separately. Any 24-bit colour.
Anything precomputed offline (tables from designs/gen_*.py) is free; work
per frame is limited (a few thousand calls). Always-on must light under
10 % of pixels and shift each minute.

You may measure the PNGs with Pillow: <venv>/bin/python -I.
Source to consult: <paths>.

## Report format (under <N> words)

1. Verdict: PASS or FAIL for your lens, and a 1–10 score.
2. Up to <M> findings, most severe first. Each: what is wrong (location and
   a measurement where you can), why it hurts, and ONE concrete fix with
   numbers (positions as fractions of the screen, sizes, hex colours, font
   names).
3. One line on what must be kept because it already works.
