#!/usr/bin/env python3
"""Count how memory fact bodies reach sessions, over the local transcript corpus.

Walks every JSONL under ~/.claude/projects/-Users-david-code-*/ (main sessions,
subagents/, archived/) and classifies each delivery of a memory fact body:

  harness      attachment.type == "relevant_memories" (CC >= 2.1.258 native recall)
  spontaneous  model Read after a Skill(gitlore:recall) call earlier in the same user turn
  manual       model Read where the user's prompt names recall or the file, or the
               turn is a /gitlore:recall command, or an @memory/... mention attachment
  active       any other model-issued Read
  bash         a Bash command that cats/seds/heads/tails a memory file (folded into
               the per-file counts, with the same turn-based sub-classification)
  reattach     attachment.type == "file" of a memory path with no @mention in the
               prompt (post-compaction re-attachment; not a recall)

Also flags, without making a class of it, the 2.1.209 recall-Read shape: a memory
Read that is the turn's first tool_use and whose message has no thinking text.

Usage: python3 plans/2026-09-02-recall-log-analysis.py [--top N] [--store DIR]
"""

import argparse
import collections
import datetime as dt
import json
import os
import re
import sys
from pathlib import Path

PROJECTS = Path.home() / ".claude" / "projects"
CODE = "/Users/david/code/"

# absolute or relative memory path; group 1 = repo (abs only), group 2 = rel path
MEM_RE = re.compile(
    r"(?:" + re.escape(CODE) + r"([\w.-]+)/|(?<![\w./-]))memory/((?:[\w.-]+/)*[\w.-]+\.md)"
)
READER_RE = re.compile(r"(?<![\w-])(cat|sed|head|tail|bat|less|awk)(?![\w-])")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--top", type=int, default=7)
    ap.add_argument("--store", default=os.path.join(CODE, "gitlore", "memory"))
    args = ap.parse_args()

    files = sorted(
        p for d in PROJECTS.glob("-Users-david-code-*") for p in d.rglob("*.jsonl")
    )
    st = Stats()
    for p in files:
        repo = p.relative_to(PROJECTS).parts[0][len("-Users-david-code-"):]
        scan(p, repo, st)
    report(st, files, args)


class Stats:
    def __init__(self) -> None:
        self.events: list[tuple[str, str, str, str, bool]] = []  # class, fact, ts, version, subagent
        self.bash_other = collections.Counter()  # fact -> non-reader bash mentions
        self.harness_shape = collections.Counter()  # version -> 2.1.209-shape reads
        self.attach_types = collections.Counter()
        self.turns = 0
        self.recall_skill_turns = 0
        self.files = 0
        self.bad_lines = 0


def scan(path: Path, repo: str, st: Stats) -> None:
    st.files += 1
    subagent = "subagents" in path.parts
    prompt = ""  # lowercased text of the current user turn
    recall = False  # Skill(gitlore:recall) seen this turn
    first_tool = True  # no tool_use yet this turn
    seen_tool_ids: set[str] = set()
    with path.open(encoding="utf-8", errors="replace") as fh:
        for line in fh:
            try:
                e = json.loads(line)
            except ValueError:
                st.bad_lines += 1
                continue
            if not isinstance(e, dict):
                st.bad_lines += 1
                continue
            ts = e.get("timestamp", "")
            ver = e.get("version", "?")
            kind = e.get("type")
            if kind == "user":
                text = user_text(e)
                if text is None:
                    continue  # tool_result carrier, not a turn
                st.turns += 1
                prompt = text.lower()
                recall = "<command-name>/gitlore:recall</command-name>" in text
                if recall:
                    st.recall_skill_turns += 1
                first_tool = True
            elif kind == "assistant":
                msg = e.get("message") or {}
                content = msg.get("content")
                if not isinstance(content, list):
                    continue
                has_thinking = any(
                    b.get("type") == "thinking" and (b.get("thinking") or "").strip()
                    for b in content
                    if isinstance(b, dict)
                )
                for b in content:
                    if not isinstance(b, dict) or b.get("type") != "tool_use":
                        continue
                    tid = b.get("id")
                    if tid in seen_tool_ids:
                        continue
                    seen_tool_ids.add(tid)
                    name = b.get("name")
                    inp = b.get("input") or {}
                    if name == "Skill" and inp.get("skill") == "gitlore:recall":
                        if not recall:
                            st.recall_skill_turns += 1
                        recall = True
                    elif name == "Read":
                        fact = fact_key(str(inp.get("file_path", "")), repo)
                        if fact:
                            cls = classify(fact, prompt, recall)
                            if cls == "active" and first_tool and not has_thinking:
                                st.harness_shape[ver] += 1
                            st.events.append((cls, fact, ts, ver, subagent))
                    elif name == "Bash":
                        cmd = str(inp.get("command", ""))
                        facts = {f for f in (fact_key(m, repo) for m in mem_paths(cmd)) if f}
                        if facts:
                            reader = bool(READER_RE.search(cmd))
                            for fact in facts:
                                if reader:
                                    cls = "bash-" + classify(fact, prompt, recall)
                                    st.events.append((cls, fact, ts, ver, subagent))
                                else:
                                    st.bash_other[fact] += 1
                    first_tool = False
            elif kind == "attachment":
                a = e.get("attachment") or {}
                at = a.get("type")
                st.attach_types[at] += 1
                if at == "relevant_memories":
                    for m in a.get("memories") or []:
                        fact = fact_key(str(m.get("path", "")), repo) or str(m.get("path"))
                        st.events.append(("harness", fact, ts, ver, subagent))
                elif at == "file":
                    fact = fact_key(str(a.get("filename") or a.get("path") or ""), repo)
                    if fact:
                        cls = "manual" if "@memory/" in prompt else "reattach"
                        st.events.append((cls, fact, ts, ver, subagent))


def user_text(e: dict) -> str | None:
    """Text of a user turn, or None when the entry is a tool_result carrier."""
    if e.get("isMeta"):
        return None
    if e.get("isCompactSummary"):
        return ""  # a turn boundary, but not a prompt the user wrote
    msg = e.get("message") or {}
    content = msg.get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        texts = [b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text"]
        if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in content):
            return None
        return "\n".join(texts)
    return None


def mem_paths(cmd: str) -> list[str]:
    return [m.group(0) for m in MEM_RE.finditer(cmd)]


def fact_key(path: str, repo: str) -> str | None:
    m = MEM_RE.search(path)
    if not m:
        return None
    rel = m.group(2)
    if rel.rsplit("/", 1)[-1] == "MEMORY.md":
        return None
    r = m.group(1) or repo
    if rel.startswith("ddaanet/"):
        return rel
    return f"{r}:{rel}"


def classify(fact: str, prompt: str, recall: bool) -> str:
    if recall:
        return "spontaneous"
    rel = fact.split(":", 1)[-1]
    stem = rel.rsplit("/", 1)[-1][: -len(".md")]
    if "recall" in prompt or stem.lower() in prompt or rel.lower() in prompt:
        return "manual"
    return "active"


def report(st: Stats, files: list[Path], args: argparse.Namespace) -> None:
    ev = st.events
    print(f"corpus: {len(files)} transcripts, {st.turns} user turns, "
          f"{st.recall_skill_turns} turns with a recall skill call, "
          f"{st.bad_lines} unparsable lines")
    print(f"attachments seen: relevant_memories={st.attach_types['relevant_memories']} "
          f"file={st.attach_types['file']} nested_memory={st.attach_types['nested_memory']}")
    print(f"2.1.209 recall-Read shape (first tool_use, no thinking) among active reads, by version: "
          f"{dict(sorted(st.harness_shape.items()))}")
    print()

    by_class = collections.Counter(c for c, *_ in ev)
    print("class totals")
    for c, n in sorted(by_class.items(), key=lambda kv: -kv[1]):
        sub = sum(1 for cc, _f, _t, _v, s in ev if cc == c and s)
        print(f"  {c:<18} {n:5d}   (in subagents: {sub})")
    print(f"  {'bash-other':<18} {sum(st.bash_other.values()):5d}   (grep/ls/git/etc. naming a fact; not counted as reads)")
    print()

    print("class totals by ISO week")
    weeks = collections.defaultdict(collections.Counter)
    for c, _f, ts, _v, _s in ev:
        if not ts:
            continue
        d = dt.datetime.fromisoformat(ts.replace("Z", "+00:00")).date()
        weeks[d.isocalendar()[:2]][base(c)] += 1
    cols = ["harness", "spontaneous", "manual", "active", "reattach"]
    print("  week      " + "".join(f"{c:>12}" for c in cols) + "   total")
    for wk in sorted(weeks):
        row = weeks[wk]
        print(f"  {wk[0]}-W{wk[1]:02d}" + "".join(f"{row[c]:12d}" for c in cols) + f"{sum(row.values()):8d}")
    print()

    per_fact = collections.defaultdict(collections.Counter)
    for c, f, _t, _v, _s in ev:
        per_fact[f][base(c)] += 1
        per_fact[f]["total"] += 1

    def show(rows):
        print("  " + f"{'fact':<52}" + "".join(f"{c:>12}" for c in cols) + "   total")
        for f, cnt in rows:
            print("  " + f"{f:<52}" + "".join(f"{cnt[c]:12d}" for c in cols) + f"{cnt['total']:8d}")

    ranked = sorted(per_fact.items(), key=lambda kv: (-kv[1]["total"], kv[0]))
    print(f"top {args.top} most-read facts")
    show(ranked[: args.top])
    print()

    store = Path(args.store)
    current = set()
    for p in store.rglob("*.md"):
        rel = p.relative_to(store).as_posix()
        if p.name == "MEMORY.md" or "/.git" in rel:
            continue
        current.add(rel if rel.startswith("ddaanet/") else f"gitlore:{rel}")
    read_current = [(f, per_fact[f]) for f in current if f in per_fact]
    never = sorted(f for f in current if f not in per_fact)
    least = sorted(read_current, key=lambda kv: (kv[1]["total"], kv[0]))[: args.top]
    print(f"{args.top} least-read facts among the {len(current)} in {store} that were read at all")
    show(least)
    print()
    print(f"never read ({len(never)} of {len(current)} current facts):")
    for f in never:
        print(f"  {f}")


def base(cls: str) -> str:
    return cls[len("bash-"):] if cls.startswith("bash-") else cls


if __name__ == "__main__":
    sys.exit(main())
