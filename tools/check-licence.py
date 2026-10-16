#!/usr/bin/env python3
"""Licence and dependency gate.

Asserts the two claims the specification makes about the source tree
(docs/12 §6):

1. every Swift source file carries an `SPDX-License-Identifier: MIT` first
   line, and
2. no SPM dependency has been added — the eight packages are `path:`
   siblings and there is no third-party code.

A pull request that adds a `.package(url:)` does not merge, and neither does
one that adds a file without a licence header.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

SPDX = "// SPDX-License-Identifier: MIT"


def root() -> Path:
    return Path(__file__).resolve().parent.parent


def swift_files(base: Path) -> list[Path]:
    files = list(base.rglob("*.swift"))
    # The package build directory holds SwiftPM's own checkouts; it is not
    # this repository's source.
    return [f for f in files if ".build" not in f.parts and ".swiftpm" not in f.parts]


def check_licence(root_dir: Path) -> list[str]:
    """Every source file carries the licence header; manifests keep their
    tools-version first, because SwiftPM requires that line to come before any
    other content, and the header belongs among the first few either way."""
    problems = []
    for path in swift_files(root_dir):
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except (UnicodeDecodeError, OSError) as error:
            problems.append(f"{path.relative_to(root_dir)}: could not be read ({error})")
            continue

        if path.name == "Package.swift" and lines and "// swift-tools-version:" in lines[0]:
            head = [line.strip() for line in lines[:3]]
            if SPDX not in head:
                problems.append(
                    f"{path.relative_to(root_dir)}: missing '{SPDX}' among the first lines")
            continue

        if not lines or lines[0].strip() != SPDX:
            problems.append(f"{path.relative_to(root_dir)}: missing '{SPDX}' first line")
    return problems


def check_dependencies(root_dir: Path) -> list[str]:
    problems = []
    url_dependency = re.compile(r"\.package\(\s*(url:|path:\s*\"url)", re.IGNORECASE)
    for manifest in root_dir.rglob("Package.swift"):
        if ".build" in manifest.parts:
            continue
        for number, line in enumerate(manifest.read_text(encoding="utf-8").splitlines(), 1):
            if url_dependency.search(line):
                problems.append(
                    f"{manifest.relative_to(root_dir)}:{number}: an external package "
                    "dependency is not allowed — the packages are path siblings."
                )
    return problems


def main() -> int:
    root_dir = root()
    problems = check_licence(root_dir) + check_dependencies(root_dir)
    if problems:
        print("Licence gate failed:")
        for problem in problems:
            print(f"  - {problem}")
        return 1
    print(f"Licence gate passed: {len(swift_files(root_dir))} files, all with SPDX headers.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
