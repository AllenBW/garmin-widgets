#!/usr/bin/env python3
"""The watches every app is built for, and a tool that writes them into
each manifest.

    python3 -I scripts/devices.py          # rewrite the product lists
    python3 -I scripts/devices.py --check  # exit 1 if a manifest differs

The list is every round AMOLED Connect IQ 5.1+ watch that has vector
fonts (the layouts size their text as a fraction of the screen, which
needs them). Left out: the Venu 2 family, D2 Air X10, vívoactive 5,
Approach S50, Descent G2 and the Instinct 3 AMOLEDs (no vector fonts, so
every scaled word would fall back to a fixed system font), the Venu X1
(rectangular) and the MIP watches (64 colours, no always-on rules).
Sound Level needs a microphone (Toybox.Audio), so it gets only the
watches that have one.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# The fēnix 8 family the apps were built on
FENIX8 = ["fenix8pro47mm", "fenix843mm", "fenix847mm"]
# API 6.0, five buttons, the fēnix 8's fonts
FULL = ["fenix943mm", "fenix947mm", "fenix9pro43mm", "fenix9pro47mm", "fenix9pro51mm", "fenixe", "marq3",
        "d2mach2", "d2mach2pro"]
# API 6.0, two buttons, touch
TWO_BUTTON = ["venu445mm", "venu441mm", "vivoactive6", "approachs7243mm", "approachs7247mm"]
# API 6.0, five buttons, Roboto Condensed but no Bionic
FORERUNNER_6 = ["fr57042mm", "fr57047mm", "fr970", "fr170", "fr170m", "fr70"]
# API 5.1 and 5.2, five buttons, Roboto Condensed and Bionic Bold
FIVE_BUTTON_5 = ["fr165", "fr165m", "fr265", "fr265s", "fr965", "epix2", "epix2pro42mm", "epix2pro47mm",
                 "epix2pro51mm", "marq2", "marq2aviator", "d2mach1", "descentmk343mm", "descentmk351mm"]
# API 5.1, three buttons
THREE_BUTTON_5 = ["approachs7042mm", "approachs7047mm"]
# API 5.2, three buttons, Yantramanav and Roboto Regular only
VENU3 = ["venu3", "venu3s"]

ALL = FENIX8 + FULL + TWO_BUTTON + FORERUNNER_6 + FIVE_BUTTON_5 + THREE_BUTTON_5 + VENU3
# Toybox.Audio's supported devices among ALL (SDK 9.3 doc: Toybox.Audio)
MICROPHONE = FENIX8 + FULL + TWO_BUTTON + FORERUNNER_6

# The faces made on 2026-11-08 (Blocks, Wall, Lockup, Clack) were built and
# submitted for the fenix 8 and the Venu 4 41 mm; they get the wider list
# once they have been through the same checks as the others.
NEW_FACES = FENIX8 + ["venu441mm"]
PER_APP = {"sound": MICROPHONE, "blocks": NEW_FACES, "wall": NEW_FACES, "lockup": NEW_FACES, "clack": NEW_FACES}


def products(app):
    return PER_APP.get(app, ALL)


def rewrite(path, devices, check):
    text = path.read_text()
    m = re.search(r"(\s*)<iq:products>.*?</iq:products>", text, flags=re.S)
    indent = m.group(1)
    inner = indent + "    "
    block = f'{indent}<iq:products>' + "".join(f'{inner}<iq:product id="{d}"/>' for d in devices) + f'{indent}</iq:products>'
    new = text[:m.start()] + block + text[m.end():]
    if new != text:
        if check:
            print(f"{path.relative_to(ROOT)}: product list differs from scripts/devices.py")
            return False
        path.write_text(new)
        print(f"{path.relative_to(ROOT)}: {len(devices)} devices")
    return True


def main():
    check = "--check" in sys.argv
    ok = rewrite(ROOT / "lib" / "manifest.xml", ALL, check)
    for app in sorted(p.name for p in (ROOT / "apps").iterdir() if (p / "manifest.xml").exists()):
        ok = rewrite(ROOT / "apps" / app / "manifest.xml", products(app), check) and ok
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
