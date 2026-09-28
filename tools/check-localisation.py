#!/usr/bin/env python3
"""Every user-facing string needs a translator comment.

A bare `Text("...")` is a string a translator cannot place. `Text(verbatim:)`
is the escape hatch for things that are not language — a separator, a handle,
a number already formatted. The comment may sit on a following line, so this
reads the call rather than the line (docs/12 §4).
"""
import pathlib
import re
import sys

ROOTS = [
    "Packages/AlohaModels/Sources", "Packages/AlohaNetwork/Sources",
    "Packages/AlohaStore/Sources", "Packages/AlohaMedia/Sources",
    "Packages/AlohaIntelligence/Sources", "Packages/AlohaDesign/Sources",
    "Packages/AlohaUI/Sources", "AlohaSocial", "AlohaSocialWatch",
    "AlohaSocialTV", "AlohaWidgets", "AlohaShareExtension",
]

CALL = re.compile(r'\bText\(\s*"')
offenders = []

for root in ROOTS:
    base = pathlib.Path(root)
    if not base.exists():
        continue
    for file in base.rglob("*.swift"):
        lines = file.read_text().splitlines()
        for index, line in enumerate(lines):
            if line.lstrip().startswith("//"):
                continue
            if not CALL.search(line):
                continue
            # The call may wrap; look ahead until its closing paren.
            window = "\n".join(lines[index:index + 4])
            if "comment:" in window or "verbatim:" in window:
                continue
            offenders.append(f"{file}:{index + 1}: {line.strip()}")

if offenders:
    print("Strings without a translator comment:")
    print("\n".join(offenders))
    sys.exit(1)

print("localisation gate: clean")
