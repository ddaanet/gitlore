#!/usr/bin/env python3
"""Cache keys for `lint-shell.sh`: one per shell file, over everything its
shellcheck verdict can depend on.

Reads the discovered files NUL-delimited on stdin, takes the tool's version
text as its one argument, and writes `<key>\\0<path>\\0` per file.

A verdict under `shellcheck -x` depends on the file and on every file it
sources, however indirectly. shellcheck follows a `source` only through a
literal path or a `# shellcheck source=` directive, and either spells the
target's basename in the sourcing file — so "mentions the basename of another
discovered file" over-approximates "sources it", and the closure of that
relation over-approximates what `-x` reads. Over-approximating costs a relint;
under-approximating would keep a stale pass, which is why nothing here tries to
parse a `source` line.

Python, not shell: a transitive closure over a cyclic graph, keyed by path, in
bash 3.2 — no associative arrays — is more mechanism than the cache is worth.

Residual: a file sourced from outside the discovered set (an ignored file,
`memory/`, the system) is not in any key.
"""

from __future__ import annotations

import hashlib
import os
import sys


def main() -> int:
    tool_version = sys.argv[1].encode()
    paths = [p for p in sys.stdin.buffer.read().split(b"\0") if p]
    contents = {p: open(p, "rb").read() for p in paths}
    mentions = direct_mentions(contents)
    out = sys.stdout.buffer
    for path in paths:
        digest = hashlib.sha256(tool_version)
        for dep in sorted(closure(path, mentions)):
            body = contents[dep]
            # Length-prefixed, so no name or body can run into the next.
            digest.update(b"%d:%s%d:" % (len(dep), dep, len(body)))
            digest.update(body)
        out.write(digest.hexdigest().encode() + b"\0" + path + b"\0")
    return 0


def direct_mentions(contents: dict[bytes, bytes]) -> dict[bytes, set[bytes]]:
    by_basename: dict[bytes, set[bytes]] = {}
    for path in contents:
        by_basename.setdefault(os.path.basename(path), set()).add(path)
    return {
        path: {
            target
            for name, targets in by_basename.items()
            if name in body
            for target in targets
        }
        for path, body in contents.items()
    }


def closure(start: bytes, mentions: dict[bytes, set[bytes]]) -> set[bytes]:
    seen = {start}
    todo = [start]
    while todo:
        for dep in mentions[todo.pop()]:
            if dep not in seen:
                seen.add(dep)
                todo.append(dep)
    return seen


if __name__ == "__main__":
    sys.exit(main())
