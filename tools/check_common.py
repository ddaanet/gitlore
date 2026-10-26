"""Helpers shared verbatim by `check-memory-hygiene.py` and `check-docs-links.py`:
finding the repo root, reading a file as text, and the fence/code-span/suppress
vocabulary both checkers' prose scans use.
"""

from __future__ import annotations

import os
import re
import subprocess


def git_toplevel() -> str | None:
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, check=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return None
    return out.stdout.strip() or None


def read_text(path: str) -> str | None:
    """Return the file's text, or None when it is not text at all."""
    try:
        with open(path, "rb") as fh:
            raw = fh.read()
    except OSError:
        return None
    if b"\0" in raw:
        return None
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        return None


# A line carrying this is exempt from every check both scripts run.
SUPPRESS = "<!-- hygiene-ok"

FENCE = re.compile(r"^\s*(```|~~~)")

CODE_SPAN = re.compile(r"`[^`]*`")
