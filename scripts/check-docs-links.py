#!/usr/bin/env python3
"""Hygiene gate over the `docs/` graph: pointers resolve, decisions are stubbed.

`docs/design.md` is the hub. Each decision's argument lives in a node under
`docs/references/`, reachable from the hub, and a one-line statement of its
conclusion sits ahead of that argument. That shape is only safe while the
crosslinking holds: a reader who cannot see that a decision was made
re-litigates it, and a pointer that stops resolving strands the argument — both
silently.

A cluster that has become a subsystem takes one hub entry rather than one per
sub-decision, and its node opens with its own summary of them. So a conclusion
counts wherever it is reachable before the argument: in the hub, or in the
summary of the node doing the arguing.

Eight checks. Seven are blocking, because each has a single legitimate reading:

- `broken-link`         a relative pointer whose target is not on disk
- `unstubbed-decision`  an argument with no conclusion line anywhere ahead of it
- `stub-without-body`   a hub bullet whose argument lives nowhere
- `duplicate-decision`  one number argued in two nodes, or twice in one
- `duplicate-conclusion` one number concluded twice in the hub
- `undefined-decision`  a `D<n>` citation with no decision behind it
- `enumeration-drift`   a node's heading and its bodies disagree
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
import subprocess
import sys

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

# An argument's own heading, in a node or in the hub: `**D9 — Title**`. Anchored
# at line start, which is what separates it from the inline `**D26**` citations
# a node's own summary bullets are made of.
DEF_LINE = re.compile(r"^\*\*D(\d+) — ")

# A hub conclusion bullet: `- **D9** — one line`. Its argument lives elsewhere,
# so a number in this shape and nowhere else is a dangling pointer.
STUB_LINE = re.compile(r"^- \*\*D(\d+)\*\* — ")

# A conclusion inside a bulleted summary: the hub's `- **D9** — one line`, and
# the same shape in a cluster node's opening list, where several ride one
# bullet (`- Composition — **D29** … · **D30** …`).
SUMMARY_BULLET = re.compile(r"^- ")

SUMMARY_ITEM = re.compile(r"\*\*D(\d+)\*\*")

CITATION = re.compile(r"\bD(\d+)\b")

# Both spellings: `[text](target)` and the angle-bracket form a target with a
# space has to use.
LINK = re.compile(r"\[[^\]]*\]\((<[^>]*>|[^)\s]*)\)")

NOT_A_PATH = ("http://", "https://", "mailto:", "#")

# A node's heading claims what it holds: `# The commit gate — decisions D4, D8`
# or `## Decisions — D5, D10`. Matching on the word rather than on the heading
# level is what lets a node put the enumeration wherever it reads best.
ENUM_HEADING = re.compile(r"^#{1,6} .*\bdecisions?\b", re.I)

# `D26–D44` in a heading covers every number between. En dash, em dash and
# hyphen all spell it in prose here.
ENUM_RANGE = re.compile(r"\bD(\d+)\s*[–—-]\s*D?(\d+)\b")

SUPPRESS = "<!-- hygiene-ok"

FENCE = re.compile(r"^\s*(```|~~~)")

CODE_SPAN = re.compile(r"`[^`]*`")


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

    docs = discover(docs_dir)
    nodes = [p for p in docs if os.path.dirname(p) == os.path.join(root, NODE_DIR)]

    findings = []
    for path in docs:
        findings += check_links(path, root)
        findings += check_size(path, root)

    conclusions, stubs, findings_hub = collect_conclusions(hub, root)
    findings += findings_hub

    bodies, findings_bodies = collect_bodies(nodes, root)
    findings += findings_bodies

    summaries = collect_summaries(nodes, root)
    findings += check_coverage(conclusions, stubs, bodies, summaries)
    findings += check_citations([hub] + nodes, root, conclusions, bodies)
    for path in nodes:
        findings += check_enumeration(path, root, bodies)
    findings += check_orphans(nodes, root)

    return report(findings, len(conclusions | set(bodies)), len(docs))


def git_toplevel() -> str | None:
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, check=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return None
    return out.stdout.strip() or None


def discover(docs_dir: str) -> list[str]:
    found = []
    for dirpath, dirnames, filenames in os.walk(docs_dir):
        dirnames[:] = [d for d in dirnames if d != ".git"]
        for name in filenames:
            if name.endswith(".md"):
                found.append(os.path.join(dirpath, name))
    return sorted(found)


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


def prose_lines(path: str) -> list[str]:
    """The file's lines with fenced blocks and code spans blanked, numbering
    kept, and suppressed lines cleared whole."""
    text = read_text(path)
    if text is None:
        return []
    out = []
    in_fence = False
    for line in text.splitlines():
        if FENCE.match(line):
            in_fence = not in_fence
            out.append("")
            continue
        if in_fence or SUPPRESS in line:
            out.append("")
            continue
        out.append(CODE_SPAN.sub(lambda m: " " * len(m.group(0)), line))
    return out


def check_links(path: str, root: str) -> list[tuple]:
    rel = os.path.relpath(path, root)
    base = os.path.dirname(path)
    findings = []
    for lineno, line in enumerate(prose_lines(path), 1):
        for target in LINK.findall(line):
            if target.startswith("<") and target.endswith(">"):
                target = target[1:-1]
            if not target or target.startswith(NOT_A_PATH):
                continue
            # A fragment addresses a place inside the target, not another file.
            target = target.split("#", 1)[0]
            if not target:
                continue
            if not os.path.exists(os.path.join(base, target)):
                findings.append(("BLOCK", "broken-link", rel, lineno, target))
    return findings


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


def collect_conclusions(hub: str, root: str) -> tuple[set[int], set[int], list[tuple]]:
    """Decision numbers the hub states a conclusion for, either as a bullet
    pointing at a node or as an argument stated in full. The bullets come back
    separately: only they need an argument to point at."""
    rel = os.path.relpath(hub, root)
    seen: dict[int, int] = {}
    stubs: set[int] = set()
    findings = []
    for lineno, line in enumerate(prose_lines(hub), 1):
        match = STUB_LINE.match(line) or DEF_LINE.match(line)
        if not match:
            continue
        number = int(match.group(1))
        if number in seen:
            findings.append(
                ("BLOCK", "duplicate-conclusion", rel, lineno,
                 f"D{number} also concluded at line {seen[number]}")
            )
            continue
        seen[number] = lineno
        if STUB_LINE.match(line):
            stubs.add(number)
    return set(seen), stubs, findings


def collect_bodies(nodes: list[str], root: str) -> tuple[dict[int, str], list[tuple]]:
    """Map each decision number to the node arguing it, flagging any argued
    twice — two arguments for one number is two decisions wearing one name."""
    bodies: dict[int, str] = {}
    findings = []
    for path in nodes:
        rel = os.path.relpath(path, root)
        for lineno, line in enumerate(prose_lines(path), 1):
            match = DEF_LINE.match(line)
            if not match:
                continue
            number = int(match.group(1))
            if number in bodies:
                findings.append(
                    ("BLOCK", "duplicate-decision", rel, lineno,
                     f"D{number} also argued in {bodies[number]}")
                )
                continue
            bodies[number] = rel
    return bodies, findings


def collect_summaries(nodes: list[str], root: str) -> dict[int, set[str]]:
    """Decision numbers each node states a one-line conclusion for, ahead of
    the arguments themselves."""
    summaries: dict[int, set[str]] = {}
    for path in nodes:
        rel = os.path.relpath(path, root)
        for item in bullet_items(prose_lines(path)):
            for number in SUMMARY_ITEM.findall(item):
                summaries.setdefault(int(number), set()).add(rel)
    return summaries


def bullet_items(lines: list[str]) -> list[str]:
    """Each `- ` bullet joined with its wrapped continuation lines — the
    indented ones that follow it — so a cluster summary reads as one item
    however `format-docs` broke it across lines."""
    items: list[str] = []
    for line in lines:
        if SUMMARY_BULLET.match(line):
            items.append(line)
        elif items and line.strip() and line[0].isspace():
            items[-1] += " " + line.strip()
        else:
            items.append("")
    return [item for item in items if item]


def check_coverage(
    conclusions: set[int],
    stubs: set[int],
    bodies: dict[int, str],
    summaries: dict[int, set[str]],
) -> list[tuple]:
    """Both directions of the hub/node contract."""
    findings = []
    for number in sorted(set(bodies) - conclusions):
        if bodies[number] in summaries.get(number, set()):
            continue
        findings.append(
            ("BLOCK", "unstubbed-decision", bodies[number], 1,
             f"D{number} argued here, concluded neither in {HUB} nor in this node's summary")
        )
    for number in sorted(stubs - set(bodies)):
        findings.append(
            ("BLOCK", "stub-without-body", HUB, 1,
             f"D{number} concluded here, argued in no node")
        )
    return findings


def check_citations(
    files: list[str], root: str, conclusions: set[int], bodies: dict[int, str]
) -> list[tuple]:
    """A citation resolves to a decision that exists somewhere in the graph."""
    known = conclusions | set(bodies)
    findings = []
    for path in files:
        rel = os.path.relpath(path, root)
        for lineno, line in enumerate(prose_lines(path), 1):
            for number in {int(n) for n in CITATION.findall(line)}:
                if number not in known:
                    findings.append(
                        ("BLOCK", "undefined-decision", rel, lineno, f"D{number}")
                    )
    return findings


def check_enumeration(path: str, root: str, bodies: dict[int, str]) -> list[tuple]:
    """A node's heading enumerates what it holds. Re-derive it from the bodies
    rather than trusting the list: a stale enumeration reads as coverage."""
    rel = os.path.relpath(path, root)
    lines = prose_lines(path)
    claimed: set[int] = set()
    heading_line = 0
    for lineno, line in enumerate(lines, 1):
        if not ENUM_HEADING.match(line):
            continue
        heading_line = lineno
        rest = line
        for lo, hi in ENUM_RANGE.findall(rest):
            claimed |= set(range(int(lo), int(hi) + 1))
        rest = ENUM_RANGE.sub(" ", rest)
        claimed |= {int(n) for n in CITATION.findall(rest)}
    if not heading_line:
        return []
    present = {n for n, owner in bodies.items() if owner == rel}
    findings = []
    for number in sorted(claimed - present):
        findings.append(
            ("BLOCK", "enumeration-drift", rel, heading_line,
             f"D{number} claimed in the heading, argued nowhere here")
        )
    for number in sorted(present - claimed):
        findings.append(
            ("BLOCK", "enumeration-drift", rel, heading_line,
             f"D{number} argued here, missing from the heading")
        )
    return findings


def check_orphans(nodes: list[str], root: str) -> list[tuple]:
    """A node nothing cites. The scan is repo-wide rather than docs-only: a
    node whose only reader is a memory fact is reachable, just not from the
    graph."""
    findings = []
    for path in nodes:
        needle = f"references/{os.path.basename(path)}"
        if cited_anywhere(needle, root, exclude=path):
            continue
        findings.append(
            ("WARN", "orphan-reference", os.path.relpath(path, root), 1,
             "no file points at it")
        )
    return findings


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
