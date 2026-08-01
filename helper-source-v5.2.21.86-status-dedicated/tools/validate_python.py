#!/usr/bin/env python3
"""Compile package Python files and parse package JSON without writing bytecode."""

import json
import pathlib
import sys


def main() -> int:
    root = pathlib.Path(sys.argv[1]).resolve()
    for path in root.rglob("*.py"):
        compile(path.read_text(encoding="utf-8"), str(path), "exec")
    for path in root.rglob("*.json"):
        json.loads(path.read_text(encoding="utf-8"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
