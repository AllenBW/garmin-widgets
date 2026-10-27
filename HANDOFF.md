# Handoff: garmin-widgets

Connect IQ watch faces and glances for the Garmin fēnix 8 Pro. This file tells
the next session how to move the project into its permanent repository and
carry on.

## Where everything is

All project files are published with the design page:

- **Design page:** https://claude.ai/artifact/CQcd2fNRPKsgigd9j7dfKd (private to
  the owner)
- **Project files:** each file is attached to that page under `repo/`, at the
  same relative path it has in the repository. Read them with the Artifact tool:
  `action: "read"`, `url: <page url>`, `paths: [...]`. List them with
  `action: "list"`, `scope: "files"`.

| Path | What it is |
|---|---|
| `repo/README.md` | Setup, build, run and sideload steps |
| `repo/CLAUDE.md` | Ground rules for working in this repo (read first) |
| `repo/HANDOFF.md` | This file |
| `repo/EXPLORATION.md` | What the fēnix 8 Pro lets apps do, with sources and confidence markers |
| `repo/designs/DESIGNS.md` | Five ranked designs: layouts, always-on variants, data sources, risks |
| `repo/designs/mockups.py` | Regenerates the mockups (`python3 designs/mockups.py`) |
| `repo/designs/svg/*.svg` | 10 mockups at 454×454 (faces: active + always-on; glances: glance + app) |
| `repo/watchface/` | Starter watch face: `manifest.xml`, `monkey.jungle`, `source/*.mc`, `resources/**` (including `launcher_icon.png`) |
| `repo/.gitignore` | Ignores `bin/` and developer keys |

The published page itself (`index.html`) is a generated presentation of the
designs. It is not part of the repository.

## Moving it into the repository

1. Fetch every `repo/` file from the page and write it to the same path in the
   repository, without the `repo/` prefix. Copy the `.png` byte for byte (the
   Artifact read saves it to a local file). Check that the SVGs and the PNG
   survived intact.
2. Commit, e.g. "Import garmin-widgets: exploration, designs, starter watch
   face". The original history was two commits (exploration + starter face,
   then designs). It doesn't need to be preserved.
3. Run `python3 designs/mockups.py` and confirm it regenerates the same 10 SVGs.

## State

- **Done:**
  - the platform exploration (`EXPLORATION.md`)
  - five designs with mockups (`designs/`)
  - a starter always-on-aware watch face (`watchface/`)
- **Never compiled.** The Connect IQ SDK couldn't be downloaded because the
  cloud environment blocked `developer.garmin.com`. To build in a cloud
  session, add that host under Allowed domains in the environment's Network
  access settings; otherwise build locally.
- **Unverified:** the device ID `fenix8pro47mm`, memory limits, API level, and
  the APIs marked ⚠️ in `EXPLORATION.md` and `designs/DESIGNS.md`.

## Rules

- **Self-contained project.** It has nothing to do with Artisan
  (`AllenBW/artisan`) or any other repository. Don't add references to or
  integrations with other projects.
- Never commit developer keys (`*.der`, `*.pem`).

## Next steps

1. Install SDK 9.3.x and the fēnix 8 Pro device files. Confirm the device ID,
   API level and memory limits in `compiler.json`, and update `manifest.xml`
   and `EXPLORATION.md` §9.
2. Compile `watchface/` and fix whatever the compiler reports. Check the
   always-on mode and peak memory in the simulator.
3. Restructure into `apps/<name>/` plus a shared `lib/` barrel (see "Shared
   building blocks" in `designs/DESIGNS.md`). Turn the starter into
   `apps/field/` and build **Field** (design #1).
4. Then **Battery Planner** (#2). Before starting **Readiness** (#4), check
   which complications the SDK actually exposes.
