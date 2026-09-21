#!/usr/bin/env python3
"""Hygiene gate over the `docs/` graph: pointers resolve, decisions are stubbed.

`docs/design.md` is the hub and `docs/decisions.md` its decisions index. Each
decision's argument lives in a node under `docs/references/`, reachable from the
hub, and a one-line statement of its conclusion sits in the index, ahead of that
argument. That shape is only safe while the crosslinking holds: a reader who
cannot see that a decision was made re-litigates it, and a pointer that stops
resolving strands the argument — both silently.

A cluster that has become a subsystem takes one index entry rather than one per
sub-decision, and its node opens with its own summary of them. The index says so
in prose — `(D29–D31, D34–D37) in [name](references/x.md)` — and only that
delegation lets the node's summary stand in for an index bullet: a node
summarizing itself unasked is how a conclusion goes missing unnoticed.

Nine checks. Eight are blocking, because each has a single legitimate reading:

- `broken-link`         a relative pointer whose target is not on disk
- `unstubbed-decision`  an argument with no conclusion line anywhere ahead of it
- `stub-without-body`   an index bullet whose argument lives nowhere
- `duplicate-decision`  one number argued in two nodes, or twice in one
- `duplicate-conclusion` one number concluded twice in the index
- `undefined-decision`  a `D<n>` citation with no decision behind it
- `enumeration-drift`   a node's heading and its bodies disagree
- `delegation-drift`    the index delegates a number to a node that does not conclude it
- `oversized-file`      a file past the line cap a node has to read in one go

The line cap is 400. Tokens are not gated: counting them calls the API, and the
80-column hard wrap `format-docs` applies bounds a line at roughly 23 tokens,
so 400 lines is under 10k tokens and the line count is the binding limit.

`orphan-reference` warns rather than blocks: a node reachable only from a
memory file or a plan is unusual, not wrong.

Prose is read with fenced blocks and inline code spans blanked out. A composed
index line quoted as `- [A](a.md) — hook` is a fixture being described, not a
pointer, and `D77` inside backticks is a fixture name rather than a citation.
A line carrying `<!-- hygiene-ok -->` is exempt from every check.

Repo-local by design (D22): it gates this repository's own documentation and
ships nothing.
"""

from __future__ import annotations

import argparse
import os
import re
import sys

from check_common import git_toplevel, read_text
from check_docs_decisions import (
    DECISIONS,
    check_citations,
    check_coverage,
    check_enumeration,
    collect_bodies,
    collect_conclusions,
    collect_delegations,
    collect_summaries,
    prose_lines,
)

HUB = os.path.join("docs", "design.md")

MAX_LINES = 400

NODE_DIR = os.path.join("docs", "references")

# Where a pointer to a node can legitimately come from. `docs/` is the graph
# itself; the rest cite a node as evidence — a memory fact naming the
# instrumentation trail behind it, a skill naming the reference it implements.
# Nothing here is a *pointer* the graph depends on, so the roots exist only to
# keep the orphan warning honest.
CITATION_ROOTS = (
    "docs",
    "memory",
    "plans",
    "skills",
    "agents",
    "commands",
    "scripts",
    "hooks",
    "CLAUDE.md",
    "README.md",
)

# Both spellings: `[text](target)` and the angle-bracket form a target with a
# space has to use.
LINK = re.compile(r"\[[^\]]*\]\((<[^>]*>|[^)\s]*)\)")

NOT_A_PATH = ("http://", "https://", "mailto:", "#")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--root", help="repository root (default: the git toplevel)")
    args = ap.parse_args()

    root = args.root or git_toplevel()
    if root is None:
        print("check-docs-links: not a git repository and no --root", file=sys.stderr)
        return 2

    docs_dir = os.path.join(root, "docs")
    if not os.path.isdir(docs_dir):
        print(f"check-docs-links: no docs tree at {docs_dir}", file=sys.stderr)
        return 2

    hub = os.path.join(root, HUB)
    if not os.path.isfile(hub):
        print(f"check-docs-links: no hub at {hub}", file=sys.stderr)
        return 2
    decisions = os.path.join(root, DECISIONS)
    if not os.path.isfile(decisions):
        print(f"check-docs-links: no decisions index at {decisions}", file=sys.stderr)
        return 2

    docs = discover(docs_dir)
    nodes = [p for p in docs if os.path.dirname(p) == os.path.join(root, NODE_DIR)]

    findings = []
    for path in docs:
        findings += check_links(path, root)
        findings += check_size(path, root)

    conclusions, stubs, findings_index = collect_conclusions(decisions, root)
    findings += findings_index

    delegated, findings_delegated = collect_delegations(decisions, root, conclusions)
    findings += findings_delegated

    bodies, findings_bodies = collect_bodies(nodes, root)
    findings += findings_bodies

    summaries = collect_summaries(nodes, root)
    findings += check_coverage(conclusions, stubs, bodies, summaries, delegated)
    findings += check_citations([hub, decisions] + nodes, root, conclusions, bodies)
    for path in nodes:
        findings += check_enumeration(path, root, bodies)
    findings += check_orphans(nodes, root)

    return report(findings, len(conclusions | set(bodies)), len(docs))


def discover(docs_dir: str) -> list[str]:
    found = []
    for dirpath, dirnames, filenames in os.walk(docs_dir):
        dirnames[:] = [d for d in dirnames if d != ".git"]
        for name in filenames:
            if name.endswith(".md"):
                found.append(os.path.join(dirpath, name))
    return sorted(found)


def check_links(path: str, root: str) -> list[tuple]:
    rel = os.path.relpath(path, root)
    base = os.path.dirname(path)
    findings = []
    for lineno, line in enumerate(prose_lines(path), 1):
        for target in link_targets(line):
            if not os.path.exists(os.path.join(base, target)):
                findings.append(("BLOCK", "broken-link", rel, lineno, target))
    return findings


def link_targets(line: str) -> list[str]:
    """The relative file paths a prose line links to."""
    targets = []
    for target in LINK.findall(line):
        if target.startswith("<") and target.endswith(">"):
            target = target[1:-1]
        if not target or target.startswith(NOT_A_PATH):
            continue
        # A fragment addresses a place inside the target, not another file.
        target = target.split("#", 1)[0]
        if target:
            targets.append(target)
    return targets


def check_size(path: str, root: str) -> list[tuple]:
    """A file long enough that reading it costs a node's whole budget. Split it
    along a need-time seam rather than raising the cap: the graph is only
    cheaper than one document while each node is readable on its own."""
    text = read_text(path)
    if text is None:
        return []
    count = len(text.splitlines())
    if count <= MAX_LINES:
        return []
    return [("BLOCK", "oversized-file", os.path.relpath(path, root), count,
             f"{count} lines, over the {MAX_LINES}-line cap")]


def check_orphans(nodes: list[str], root: str) -> list[tuple]:
    """A node nothing cites. The scan is repo-wide rather than docs-only: a
    node whose only reader is a memory fact is reachable, just not from the
    graph. Nodes link each other by bare basename (`[b](b.md)`), which the
    repo-wide substring scan cannot see, so sibling links are resolved as
    paths instead."""
    findings = []
    for path in nodes:
        needle = f"references/{os.path.basename(path)}"
        if cited_anywhere(needle, root, exclude=path):
            continue
        if linked_from_sibling(path, nodes):
            continue
        findings.append(
            ("WARN", "orphan-reference", os.path.relpath(path, root), 1,
             "no file points at it")
        )
    return findings


def linked_from_sibling(path: str, nodes: list[str]) -> bool:
    for sibling in nodes:
        if sibling == path:
            continue
        base = os.path.dirname(sibling)
        for line in prose_lines(sibling):
            for target in link_targets(line):
                if os.path.normpath(os.path.join(base, target)) == path:
                    return True
    return False


def cited_anywhere(needle: str, root: str, exclude: str) -> bool:
    for entry in CITATION_ROOTS:
        target = os.path.join(root, entry)
        if os.path.isfile(target):
            text = read_text(target)
            if text and needle in text:
                return True
            continue
        if not os.path.isdir(target):
            continue
        for dirpath, dirnames, filenames in os.walk(target):
            dirnames[:] = [d for d in dirnames if d != ".git"]
            for name in filenames:
                candidate = os.path.join(dirpath, name)
                if candidate == exclude or os.path.islink(candidate):
                    continue
                text = read_text(candidate)
                if text and needle in text:
                    return True
    return False


BLOCKING_CHECKS = (
    "broken-link",
    "unstubbed-decision",
    "stub-without-body",
    "duplicate-decision",
    "duplicate-conclusion",
    "undefined-decision",
    "enumeration-drift",
    "delegation-drift",
    "oversized-file",
)
WARNING_CHECKS = ("orphan-reference",)


def report(findings: list[tuple], n_decisions: int, n_files: int) -> int:
    for level, check, rel, lineno, detail in sorted(findings, key=lambda f: (f[0], f[2], f[3])):
        print(f"{level:<5} {check:<20} {rel}:{lineno}: {detail}")

    counts = {c: 0 for c in BLOCKING_CHECKS + WARNING_CHECKS}
    for _, check, _, _, _ in findings:
        counts[check] += 1
    blocking = sum(counts[c] for c in BLOCKING_CHECKS)

    if findings:
        print()
    print(
        f"check-docs-links: {n_decisions} decision{'' if n_decisions == 1 else 's'}, "
        f"{n_files} file{'' if n_files == 1 else 's'} scanned"
    )
    # Every blocking check is named whether or not it fired: a check that
    # printed nothing must not look like a check that never ran.
    for check in BLOCKING_CHECKS:
        print(f"  {check:<20} {counts[check]}")
    for check in WARNING_CHECKS:
        if counts[check]:
            print(f"  {check:<20} {counts[check]} (warn)")

    return 1 if blocking else 0


if __name__ == "__main__":
    sys.exit(main())
