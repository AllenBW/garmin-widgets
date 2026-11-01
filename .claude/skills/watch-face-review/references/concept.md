# Finding the idea (before the review loop)

What turned Marquee, a face the owner called "nothing special … you're
just firehosing me with data", into three faces the owner wanted all of
(Vessel, Inscription, Overlap; 2026-10-31). The review loop polishes a
face; it cannot make a dull idea special. Do this first.

## What failed, so it isn't repeated

- **A metaphor laid on top** (a theatre marquee: a lit box behind the time
  with bulbs as gauges). Reviewers scored it 9/10 on polish while the owner
  felt nothing. A metaphor that needs explaining ("what, like a ticket?")
  is decoration. The bulbs needed decoding (which half-row is which
  reading?), so they were data and ornament at once and good at neither.
- **The safe rework**: same data, tidier layout, four font and spacing
  variants. Still a data screen: date, five icons, five numbers, five
  gauges. Sheets of ten near-identical options are a firehose too.
- **A coloured background** (a sky wash that follows the sun). The owner
  ruled it out: AMOLED, black costs nothing, so the face is made of
  layout, one accent and type.
- **Mirror symmetry**: everything on the vertical axis scored 2–3/10 for
  off-centre balance from every critic.

## How the good ones were found

1. **An adversarial art review of the concept itself**, not the polish.
   Three critics, each through one artist's concrete moves, all asked
   the same five things (utility, visibility, elegance, creativity,
   off-centre balance), whether the name/metaphor resonates, and to
   sketch a replacement with a name an ordinary wearer understands.
   Give them the code and renders, not your opinion; they converged
   independently, which is the signal.
   - Picasso: reduction (the Bull lithographs: strip until only the
     essential remains), mass against line, asymmetry over mirror.
   - Monet: the series (a face is the same subject at every hour; does
     it change with the hour?), colour as time, horizonless crops.
   - O'Keeffe: magnify one form until the frame crops it (Red Canna),
     a single object against open ground (Pelvis, Ladder to the Moon),
     no fussy detail.
   Brief: `scratchpad/brief_concept.md` pattern; under 450 words each.
2. **One principle**: the time is the picture; the data whispers or
   becomes part of the time. Every good concept answered "where does the
   data go?" without adding a UI element:
   - **Become the time** (Vessel): each digit pair fills like a glass to
     a reading; the number sits on its waterline. The gauge *is* the time.
   - **Become typography** (Inscription): readings set as small spaced
     capitals round the rim like a coin's legend; no icons, no gauges.
   - **Step back for composition** (Overlap): scale contrast and the
     bezel's crop do the work; the hours enormous and dim, cropped,
     the minutes bright in front; one reading.
3. **Three different ideas, one image each**, plus each one's standby.
   Not variants of one layout. Name each in one plain word.
4. **Standby keeps the idea**: Vessel's glasses empty to a single
   waterline, Inscription keeps its legend, Overlap keeps its crop.
   A standby that is just "the same, dimmer" wastes the idea.

## Rules of thumb that held

- At most three things visible besides the time (Vessel: date, two
  waterline readings, one foot; Overlap: date and one reading). Five can
  work only as ornament (Inscription's rim).
- No box behind the time, no gauges that need a legend, no icon on every
  item. Icons are for the item you'd otherwise misread.
- The most important number (the hours) is never the faint one.
- Off-centre is a composition, not a shift: mass against open black,
  something cropped by the bezel, a column that follows the curve.
- Letter-spaced capitals (RobotoCondensedRegular, tracking ~0.010 w) read
  as refined; bold condensed numbers read as data.
- Bionic Bold (Garmin's own, "BionicBold") has the most character of the
  built-in fonts. The fēnix 8's Latin vector fonts: BionicBold,
  BionicMedium (really Rajdhani), RobotoCondensedBold/Regular,
  RobotoRegular/Medium/Italic, PridiRegular (serif), KosugiRegular,
  NanumGothicBold (from the device's `simulator.json`).

## The tools that make these buildable

- `Dc.drawRadialText` (vector fonts): text on a circle (Inscription).
- `Dc.setClip` + `drawText`: fill a glyph to a level (Vessel); the
  outline is the text drawn at offsets (VesselView.outline).
- Draw the back layer, then the front text's outline in black a few px
  wide, then the front text: a gap between overlapping glyphs (Overlap).
- Sketch in Pillow first with the watch's TTFs (glyph masks, MinFilter
  for outlines, per-character rotation for radial text); measure the
  standby lit share in the same script.

## Pacing with the owner

Show the concept sheet early, before porting anything. Don't argue for
the incumbent; when the owner says it doesn't resonate, test that
adversarially and accept the verdict. Short messages: the pictures, one
line per idea, a recommendation.
