"""The decisions-index checks read by `check-docs-links.py`: matching each
argument in a `docs/references/` node against its one-line conclusion in
`docs/decisions.md`, resolving delegated clusters, and checking a node's
heading enumeration against the bodies it actually argues.

`prose_lines` lives here too, not in `check_common.py`: it is not identical
to `check-memory-hygiene.py`'s `strip_code` (it takes a path and blanks
`SUPPRESS` lines itself, where `strip_code` takes text and leaves `SUPPRESS`
to each caller), and every function below needs it. `check-docs-links.py`
imports it back from here rather than duplicating it, since only this module
is ever imported by that one.
"""

from __future__ import annotations

import os
import re

from check_common import CODE_SPAN, FENCE, SUPPRESS, read_text

# Every conclusion line and every delegation is read from here, not from the
# hub: the hub says what the system is, the index says what was decided.
DECISIONS = os.path.join("docs", "decisions.md")


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


# An argument's own heading, in a node or in the hub: `**D9 — Title**`. Anchored
# at line start, which is what separates it from the inline `**D26**` citations
# a node's own summary bullets are made of.
DEF_LINE = re.compile(r"^\*\*D(\d+) — ")

# A hub conclusion bullet: `- **D9** — one line`. Its argument lives elsewhere,
# so a number in this shape and nowhere else is a dangling pointer.
STUB_LINE = re.compile(r"^- \*\*D(\d+)\*\* — ")


def collect_conclusions(index: str, root: str) -> tuple[set[int], set[int], list[tuple]]:
    """Decision numbers the index states a conclusion for, either as a bullet
    pointing at a node or as an argument stated in full. The bullets come back
    separately: only they need an argument to point at."""
    rel = os.path.relpath(index, root)
    seen: dict[int, int] = {}
    stubs: set[int] = set()
    findings = []
    for lineno, line in enumerate(prose_lines(index), 1):
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


# The hub handing a cluster's sub-decisions to the node whose summary concludes
# them: `(D26–D28, D32, D33) in [name](references/x.md)`. Matched on a joined
# paragraph, since `format-docs` wraps the enumeration across lines.
DELEGATION = re.compile(r"\(([^()]*\bD\d+[^()]*)\)\s+in\s+\[[^\]]*\]\(([^)\s]+)\)")


def collect_delegations(
    index: str, root: str, conclusions: set[int]
) -> tuple[dict[int, str], list[tuple]]:
    """Map each decision number the index delegates to the node it names. A
    number the index also concludes itself is concluded twice."""
    rel = os.path.relpath(index, root)
    base = os.path.dirname(index)
    delegated: dict[int, str] = {}
    findings = []
    for lineno, paragraph in paragraphs(prose_lines(index)):
        for enum, target in DELEGATION.findall(paragraph):
            node = os.path.relpath(os.path.normpath(os.path.join(base, target)), root)
            for number in enumerated(enum):
                if number in conclusions:
                    findings.append(
                        ("BLOCK", "duplicate-conclusion", rel, lineno,
                         f"D{number} delegated to {node} and concluded here")
                    )
                    continue
                delegated[number] = node
    return delegated, findings


def paragraphs(lines: list[str]) -> list[tuple[int, str]]:
    """Runs of non-blank lines joined with a space, each with the number of
    its first line."""
    out: list[tuple[int, str]] = []
    start = 0
    run: list[str] = []
    for lineno, line in enumerate(lines, 1):
        if line.strip():
            if not run:
                start = lineno
            run.append(line.strip())
        elif run:
            out.append((start, " ".join(run)))
            run = []
    if run:
        out.append((start, " ".join(run)))
    return out


# `D26–D44` in a heading covers every number between. En dash, em dash and
# hyphen all spell it in prose here.
ENUM_RANGE = re.compile(r"\bD(\d+)\s*[–—-]\s*D?(\d+)\b")

CITATION = re.compile(r"\bD(\d+)\b")


def enumerated(text: str) -> set[int]:
    """Every number a `D9, D12–D14` enumeration names."""
    numbers: set[int] = set()
    for lo, hi in ENUM_RANGE.findall(text):
        numbers |= set(range(int(lo), int(hi) + 1))
    numbers |= {int(n) for n in CITATION.findall(ENUM_RANGE.sub(" ", text))}
    return numbers


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


# A conclusion inside a bulleted summary: the hub's `- **D9** — one line`, and
# the same shape in a cluster node's opening list, where several ride one
# bullet (`- Composition — **D29** … · **D30** …`).
SUMMARY_ITEM = re.compile(r"\*\*D(\d+)\*\*")


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


SUMMARY_BULLET = re.compile(r"^- ")


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
    delegated: dict[int, str],
) -> list[tuple]:
    """Both directions of the index/node contract, and the delegations that
    stand in for index bullets."""
    findings = []
    for number in sorted(set(bodies) - conclusions):
        owner = bodies[number]
        if delegated.get(number) == owner and owner in summaries.get(number, set()):
            continue
        findings.append(
            ("BLOCK", "unstubbed-decision", owner, 1,
             f"D{number} argued here, concluded neither in {DECISIONS} nor by a delegated summary")
        )
    for number in sorted(stubs - set(bodies)):
        findings.append(
            ("BLOCK", "stub-without-body", DECISIONS, 1,
             f"D{number} concluded here, argued in no node")
        )
    for number in sorted(delegated):
        node = delegated[number]
        if bodies.get(number) != node:
            findings.append(
                ("BLOCK", "delegation-drift", DECISIONS, 1,
                 f"D{number} delegated to {node}, argued in {bodies.get(number, 'no node')}")
            )
        elif node not in summaries.get(number, set()):
            findings.append(
                ("BLOCK", "delegation-drift", node, 1,
                 f"D{number} delegated here, missing from this node's summary")
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


# A node's heading claims what it holds: `# The commit gate — decisions D4, D8`
# or `## Decisions — D5, D10`. Matching on the word rather than on the heading
# level is what lets a node put the enumeration wherever it reads best.
ENUM_HEADING = re.compile(r"^#{1,6} .*\bdecisions?\b", re.I)


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
        claimed |= enumerated(line)
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
