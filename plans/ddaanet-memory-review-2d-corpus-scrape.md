# ddaanet memory review — entry 2d · the corpus scrape

Part of [ddaanet memory review](ddaanet-memory-review.md), continuing
[2c](ddaanet-memory-review-2c-deny-and-decisions.md). The measurements the two
open decisions were waiting on, and the calls taken on them: **`git:*`** for the
exclusion, and a **relaxed `cwd-safety`** that always allows a `cd`-prefixed
composite and keeps only the drift block.

Measured 2026-08-16 over 1,194 session transcripts under
`~/.claude/projects` touched in the last 45 days — **20,481 unique Bash calls**
(deduplicated by `tool_use` id; 20,897 blocks before dedup). Scripts
`cdscrape.py` and `drift.py`, written to the session scratchpad and not kept.
Segment splitting is a
regex approximation of the tree-sitter walk; the shapes that decide anything
(`cd X &&`, `( cd X`, `git -C`) are matched on the raw command string, where the
approximation would lie.

**The transcript records the agent-authored command, not the hook rewrite.**
Verified against this session: `cwd-safety` wrapped `cd … && sed …` in a
subshell and reported doing so, and the `tool_use` input in the JSONL still
holds the unwrapped form. So every count below is authored intent, and the
`( cd … )` figure is the agent adopting the form the hook advertises rather than
the hook's own output.

Baseline: **83.5% of all Bash calls are compound**, and 6.5% already carry
`dangerouslyDisableSandbox`.

## How the working directory is actually reached

| shape | calls | share of all Bash |
|---|---|---|
| any `cd`/`pushd`/`popd` segment | 4,245 | 20.7% |
| leading `cd X && …` | 2,380 | 11.6% |
| `( cd X … )` subshell | 1,615 | 7.9% |
| `cd` elsewhere in the call | 240 | 1.2% |
| leading `cd X ; …` | 18 | 0.1% |
| bare `cd X` alone | 2 | 0.0% |
| `git -C <path>` | 2,142 | 10.5% |

`cd` targets are overwhelmingly absolute (2,120 of 2,400 leading forms), against
172 relative, 72 `~` and 35 `$VAR`. What follows a leading `cd X &&`: `git`
(465), `grep` (327), `echo` (312), `just` (141), `python3` (123), `sed` (98).

**The `( cd … )` row is the finding that stands on its own.** The agent issues
that form 1,615 times — 7.9% of all Bash traffic — and every one of them is
pushed whole as a single `node.text` segment by `U0`, so it matches no exclusion
entry and stays sandboxed; it separately forfeits read-only status via `B2f`.
The hook advertising that form is therefore paying twice, and the ledger's
proposal to stop advertising it is supported without needing either open
decision resolved.

`git -C` is not a fringe form: **2,142 calls, 31.6% of all git-bearing calls**,
split evenly between relative (957) and absolute (939) targets with 225 `$VAR`.
Its subcommands are dominated by reads — `log` 767, `status` 537, `diff` 226,
`rev-parse` 140, `show` 104 — i.e. exactly the traffic a `git status:*` or
`git log:*` prefix entry structurally cannot reach, confirming the 2b argument
with a firmer number.

## Decision 1 — the evidence

**What the question actually is.** An exclusion changes exactly one thing:
whether the command runs in the sandbox. It does not change gating — 2c's `hUf`
finding. So the only reason to exclude anything is that the sandbox **silently
corrupts the output**, via the 22 phantom `/dev/null` masks in 2b. The question
is therefore *which git commands are corrupted, and can an `excludedCommands`
entry name them* — a coverage question, which is what the corpus was scraped to
answer. It is not a cost question.

The set that must leave the sandbox is `status`, `ls-files --others`, `add`
(stages character devices, strands the lock) and `commit` (surfaces the
misleading lock error). `log`, `diff`, `show`, `rev-parse`, `ls-tree` and
`rev-list` read history and tracked content, so no mask touches them — but
excluding them costs nothing either, which is why the *needed set* does not
determine the *entry form*. The entry form is decided by what a prefix can
express, and that is the next section.

**6,786 git-bearing calls, 33.1% of all Bash.** Of those:

| | calls | share of git |
|---|---|---|
| compound | 5,392 | 79.5% |
| every git segment is a read subcommand | 4,991 | 73.5% |
| forfeit the read-only auto-allow | 4,418 | 65.1% |
| all-read **and** no disqualifier — the free shape | 1,655 | **24.4%** |

Disqualifiers, calls hitting several counted once each: `git -C` 2,082 (30.7%),
subshell or command substitution 1,900 (28.0%), a `cd` in the same call 1,390
(20.5%), `$VAR` expansion 1,044 (15.4%), `--git-dir`/`--work-tree`/`--bare` 292
(4.3%), `git -c` 47 (0.7%).

**What the read-only column does and does not measure.** For a read-only
command the classifier is skipped either way — sandboxed it takes the `hUf`
shortcut, unsandboxed it takes the `Read-only command is allowed` branch — so
excluding `git log` is cost-free and *not* excluding it is cost-free too. The
column is not an argument on either side for that class.

Where it does bite is the other 65.1%. A non-read-only git call that stays
sandboxed is auto-allowed by `hUf` with no classifier call; excluded, it falls
through to the classifier. So a broad `git:*` moves roughly **4,418 calls into
classifier evaluation** that skip it today. 2c judges that a safety gain as
much as a cost — the classifier is the gate that understands git risk — but it
is a real latency delta, and it lands almost entirely on commands no mask
corrupts.

**The neighbour argument is defence-in-depth, not a gating hole.** At 79.5%
compound a `git:*` entry unsandboxes the neighbours in 5,392 calls — but
`git log && rm foo` fails the read-only test on the `rm` segment and reaches the
classifier whether or not it is sandboxed. What exclusion removes is
containment, not the gate. Neighbours riding in a git compound, with the subset
where every git segment is a read:

Counted after stripping heredoc bodies and quoted strings — see "Heredocs
contaminate a regex segmenter" below for why that pass is required and what it
changes.

| neighbour | any git | all-read git |
|---|---|---|
| `echo` | 3,176 | 2,501 |
| `head` | 1,518 | 1,376 |
| `cd` | 1,357 | 1,101 |
| `grep` | 768 | 656 |
| `tail` | 672 | 268 |
| `ls` | 566 | 491 |
| `cat` | 362 | 285 |
| `rm` | 212 | **74** |
| `just` | 114 | 79 |
| `mkdir` | 111 | 18 |
| `printf` | 105 | 49 |
| `set` | 83 | 10 |

The `rm` row is the largest concrete instance: 212 calls where a `git:*` entry
would leave an `rm` uncontained, 138 of them alongside a git write. Every one
still faces the classifier, so this sizes the defence-in-depth loss rather than
naming an escape.

Git subcommand totals, for sizing the narrow set: `log` 2,963, `status` 2,910,
`diff` 1,626, `commit` 991, `add` 835, `show` 704, `rev-parse` 476, `config`
303, `checkout` 177, `submodule` 176, `ls-files` 143.

## Decision 1 — **taken: `git:*`**

The narrow set has no case once the axes are separated:

- **Writing git calls must be unsandboxed** or they fail in git's confusing
  style — `add`/`commit` strand `.git/index.lock` and the message names a
  concurrent git process that does not exist.
- **Mask-sensitive git calls must be unsandboxed** or they return silently
  corrupt output.
- **`git add -A`/`.` is prohibited on its own merit**, not as a sandbox measure,
  and prohibiting it does not remove the exclusion need — an explicit pathspec
  strands the lock too.
- **A narrow entry cannot match `git -C`.** The prefix form anchors at the start
  of the segment, so `git status:*` misses all 2,142 `git -C` calls (31.6% of
  git traffic), including 537 `git -C … status`. `git:*` matches them, because
  `git -C /path status` starts with `git` plus a space. Coverage is the whole
  question and only the broad form answers it.
- **Read-only git is short-circuited whether or not it is sandboxed**, so
  sweeping `log`/`diff`/`show` into the exclusion costs nothing.

The classifier delta is not a counter-argument. The 4,418 non-read-only git
calls that move into classifier evaluation are exactly the writes and
mask-sensitive reads that had to leave the sandbox anyway, and 2c judges the
classifier the better gate for git risk — a push to a foreign repo is something
it understands and the sandbox does not.

**What this accepts.** A git segment appears in 33.1% of all Bash calls, and
79.5% of those are compound, so a third of Bash traffic runs unsandboxed with
its neighbours along for the ride — 212 `rm` calls among them — and nothing in
the transcript records that it did. Every one still faces deny rules and the
classifier; what is given up is containment, not gating.

**The residual `git:*` does not close.** `U0` does not descend into `( … )`,
`$( … )` or `sh -c '…'`, so a mask-sensitive git command inside one is unmatched
and stays sandboxed. Measured: of 3,042 calls carrying a mask-sensitive git
command, **2,733 (89.8%) are reachable** as a top-level segment and **309
(10.2%) are not** — 297 `( … )` subshells, 7 `$( )`/backtick, 5 `sh -c`. The
subshell share is agent-authored adoption of the form `cwd-safety` advertises,
so retiring that advice shrinks it toward the ~12 genuine cases. Shapes like
`echo "[$(git -C memory/ddaanet ls-files X)]"` are what remains.

### `` !`cmd` `` expansion runs through the ordinary Bash path

Decompiled 2026-08-16 from the same 2.1.233 bundle, settling the residue of
change (d).

Extraction is `cWo(body)`, which collects both forms — ```` ```! ```` fenced
blocks via `` Qub = /```!\s*\n?([\s\S]*?)\n?```/g `` and the inline form via
`` edb = /(?<=^|\s)!`([^`]+)`/gm ``. Execution is `mLe(body, ctx, name, shell)`,
shared by slash commands (`getPromptForCommand` passes `` `/${name}` ``) and
skills (`isSkillMode`). For each extracted command it does:

```js
let u = await IR(i, {command: a}, t, sx({content:[]}), "");   // permission check
if (u.behavior !== "allow") throw new $Ce(...)
let {data: d} = await i.call({command: a}, c);                 // ordinary tool call
```

`i` is the Bash tool. The input is a bare `{command}` — **no
`dangerouslyDisableSandbox` field** — and the tool's own `call` computes the
sandbox decision from its input, the same convention visible in the PowerShell
tool (`let i = Wsi(e)`, where `Wsi(e) = TV({command: e.command,
dangerouslyDisableSandbox: e.dangerouslyDisableSandbox, shellType:"powershell"})`)
and in the Monitor tool (`rDe(e, signal, "bash", {shouldUseSandbox: TV({command:
e}), …})`).

So `TV` runs, `W_S(command)` runs, and **an exclusion entry applies to a
`` !`cmd` `` expansion exactly as to a typed Bash call**. `git:*` therefore does
fix the `## Context` corruption, and change (d)'s proposed `UserPromptSubmit`
warning hook is unnecessary — (d) reduces to naming the mechanism in the memory.

Two adjacent facts from the same read: the permission check is `IR`, so an
expansion the frontmatter's `allowed-tools` does not cover throws rather than
prompting; and when shell execution is disabled (`disableSkillShellExecution`),
`IVo` neutralises the markers in place rather than executing them.

**Confirmed live**, 2026-08-16, against the standing user-scope entry
`"excludedCommands": ["git status"]` with no settings change. `${TMPDIR-UNSET}`
is the discriminator throughout — `/tmp/claude-1000` sandboxed, `UNSET` not.

| expansion | result | reading |
|---|---|---|
| `` !`echo "A=${TMPDIR-UNSET}"` `` | `/tmp/claude-1000` | expansion is sandboxed by default |
| `` !`git status; echo …` `` | `UNSET` | the exact entry matched — **the exclusion applies** |
| `` !`true && git status --porcelain; echo …` `` | `/tmp/claude-1000` | no exact match, stayed sandboxed |

The third row does double duty: `unsandbox-git-status` matches
`git status --porcelain` on its best-effort matcher, so had the hook fired on
this path that row would also have been `UNSET`. It was not. **PreToolUse hooks
do not run on the `` !`cmd` `` path** — consistent with `mLe` calling `IR` for
permission rather than the hook pipeline.

An excluded expansion also sees the real tree: `git status` run through the
exclusion reported the 7 genuine untracked paths and none of the 22 masks, on
three separate invocations.

**`mLe` runs the extracted commands concurrently** — the call is
`await Promise.all(cWo(e).map(async ({raw, command}, l) => …))` — so a body with
several `` !` `` blocks executes them in parallel, some sandboxed and some not,
in an order the author does not control.

*Open anomaly, not reproduced.* The first run of the three-block probe returned
the full phantom-mask listing from its **unsandboxed** row while a long-lived
sandboxed background task was live. Three later runs were clean, including one
with a concurrent sandboxed `Promise.all` sibling and one with a sandboxed
background task deliberately running. Neither hypothesis reproduced it and no
mechanism is established. It matters because it is the difference between an
exclusion delivering clean output always and delivering it usually; whoever
picks this up should treat `sandbox-effects`' existing "real while ANY agent's
sandbox is live" line as unconfirmed in its causal form rather than as the
explanation.

## Decision 2 — the `cwd-safety` re-scope · **decided**

**Taken: always allow a `cd`-prefixed composite, and keep the drift block with
an updated message.** Read against the hook as it stands
(`scripts/cwd-safety.py`, rules 1–5c), this is a pure relaxation — it removes
denials and rewrites, and adds none:

| rule today | today's behaviour | after |
|---|---|---|
| 2 · `cd <root> && …` | allow | unchanged |
| 3 · leading `cd <subdir> && …` at root | **rewrite to `( … )`**, `permissionDecision: allow` | allow as written, no decision |
| 3 · leading `cd` while drifted | **block** | allow as written |
| 1 · embedded `cd` after a separator | **block** | allow as written |
| 5c · `set -e` script with an embedded `cd` | **rewrite to `( … )`** | allow as written |
| 4 · non-`cd` command while cwd ≠ root | block | **unchanged**, message updated |

The drift block is not new; it is rule 4, already in force. What changes is that
cwd can now actually drift, so rule 4 fires in cases that previously could not
arise — the hook used to make drift impossible by rewriting or blocking every
path to it.

**This is also what makes decision 1 work.** Finding 3 in 2c: `U0` does not
descend into a subshell, so today's rewritten `(cd sub && git status)` is one
opaque segment that matches no exclusion entry and stays sandboxed. Unwrapped,
`cd sub && git status` is two segments and a `git status:*` entry reaches it.
The rewrite was actively defeating the mechanism the ledger is moving to.

### What the replay measured, and what it does not

The rule replayed against the corpus in order, per session, with the simulated
cwd starting at the session root: a leading `cd <dir> && …` is permitted and cwd
drifts; a command not starting with `cd` is blocked when cwd ≠ root; a bare
`cd <root>` restores for free.

| outcome | calls | share |
|---|---|---|
| leading `cd …` — permitted, cwd drifts | 2,400 | 11.7% |
| … of which land back on root | 22 | 0.1% |
| … of which issued while already drifted | 1,908 | 9.3% |
| non-`cd` command at root — permitted | 9,111 | 44.5% |
| **non-`cd` command while drifted — blocked** | **8,973** | **43.8%** |
| leading `( cd …` — no drift | 1,303 | 6.4% |

The 43.8% is **not** a predicted block rate. It replays a rule against a command
stream shaped by the opposite rule: under today's hook cwd never drifts, so the
agent re-states `cd X &&` on every call needing another directory — which is
exactly why 1,908 `cd`s are issued from an already-drifted simulated cwd and
why only 22 return to root. The simulation strands cwd where the real agent
would have restated it.

Read it as an upper bound with a one-turn remedy: every blocked call is
recoverable by the rule-2 form `cd <root> && <cmd>`, which is allowed today and
after. The adapted stream is `cd <dir> && <cmd>` on everything, which the rule
permits unconditionally — and which is the segmentable form decision 1 needs.

One durable finding survives the caveat and lands on the message rather than the
rule: **the agent has essentially never written a bare restore** — 2 bare `cd`
calls in 20,481. The rule-4 message must therefore name the restore form
explicitly rather than assume it, and should prefer `cd <root> && <cmd>` over a
bare `cd <root>`, since the composite costs the same turn and does the work.
That is the "updated message" the decision calls for.

## Heredocs contaminate a regex segmenter

The first pass segmented on `&&`/`||`/`;`/`|`/`&`/newline, which walks straight
into a heredoc body and counts its lines as commands. **1,339 calls (6.5%) carry
a heredoc**, and the delimiters are not only `EOF` (640) but `PY` (355), `JSON`
(219), `MSG` (91) and `PYEOF` (41) — so a tally keyed on `EOF` both invents
segments and misses most heredocs.

Re-running the neighbour tally with heredoc bodies and quoted strings removed
separates the artifacts from the real segments:

| row | raw | real | inflation |
|---|---|---|---|
| `EOF` · `the` · `The` · `MSG` · `and` · `)"` | 300 · 201 · 186 · 85 · 82 · 163 | 0 | 100% |
| `just` | 158 | 114 | 28% |
| `}` | 92 | 68 | 26% |
| `for` | 220 | 165 | 20% |
| `printf` · `set` | 133 · 95 | 105 · 83 | 12% |
| `bash` | 87 | 78 | 10% |
| `wc` | 311 | 282 | 9% |
| **`rm`** | **229** | **212** | **3%** |
| `echo` · `head` · `cd` · `grep` · `ls` | — | — | ≤2% |

The load-bearing row survives: `rm` was inflated by 3%, so the decision-1
argument stands on 212 calls rather than 229. The rows that were pure artifact
are prose and delimiter lines from heredoc bodies. Git-bearing calls drop from
6,786 to 6,704 under the corrected segmenter, and **408 of them carry a
heredoc** — that is the real figure the bogus `EOF` row was standing in for.

## Heredocs cost the native mechanism nothing

A heredoc splits one Bash call into commands the shell executes and **data the
shell hands to a program**. Every check in this design tells them apart
correctly, so heredocs impose no constraint on the direction the ledger has
taken — which is removing hooks so the native permission system operates.

**The exclusion matcher fails closed.** `U0` descends only into
`program`/`list`/`pipeline`/`redirected_statement`, and for a
`redirected_statement` only into children whose type does not end in
`_redirect`. Body text can therefore never *trigger* an exclusion.
`git status && python3 - <<'PY' … PY` is unsandboxed because the `git status`
segment matched, exactly as `git status && rm -rf ~` is; the heredoc contributes
nothing the decoy problem in 2b does not already own.

**A heredoc cannot smuggle a side effect into a read-only-looking command.** The
capability comes from the command word, not the channel, and `isReadOnly`
requires every segment to pass the table. Every write-capable heredoc consumer
fails it independently: `git apply`, `git commit -F -`, `git update-ref --stdin`
and `git hash-object` are outside the read subcommand set, and
`bash`/`sh`/`python3` are outside the plain-command allowlist. The read-only
commands that do accept stdin — `cat`, `wc`, `git cat-file --batch` — write
nothing whatever they are fed.

*The adjacent vector is `>`, not `<<`, and it is taken as settled.* `verb > file`
is not classified read-only — the `ls` regex in 2c is
`/^ls(?:\s+[^<>()$`|{}&;\n\r]*)?$/`, which bars `<` and `>` outright, and the
classifier would be trivially broken otherwise. Either way the write there is
the redirect: `cat > file` smuggles it identically with no heredoc.

## A caveat for anyone who later writes a command-matching hook

No hook in the current design needs this: `cwd-safety` matches a *leading* `cd`
so a body cannot reach it, the `prohibitions` exclusion check reads settings
rather than commands, and change (d)'s hook greps a markdown file. It applies
only if change (a)'s read-only-inspection rule is implemented as a PreToolUse
command matcher — and that one permits rather than denies, so a misfire costs a
wasted unsandboxing.

Recorded because the cost is measurable and the mistake is easy. A regex
segmenter reads heredoc bodies as commands. Over the same corpus, of 1,333 calls
carrying a heredoc body, **100 (8%) contain a sensitive literal only in the
body**, never as a command.

| literal | only in the body | genuinely issued |
|---|---|---|
| `git add` | 35 | 163 |
| `git status` | 24 | 93 |
| `git checkout`/`reset` | **23** | **11** |
| `git commit` | 21 | 365 |
| `find` | 18 | 2 |
| `claude -p` | 7 | 2 |
| `git ls-files` | 6 | 0 |
| `ls -a`/`-A` · `ls .claude` · `ps`/`pgrep` | 3 · 2 · 2 | 7 · 8 · 0 |

Four rows have **more false positives than true ones**, and three have no true
positives at all. The sources are ordinary work in this repo:

- `git commit -F - <<'EOF'` whose commit message *discusses* `git ls-files` — a
  commit denied for what it says about a command;
- `cat > probe.bats <<'EOF'` writing a fixture whose body contains
  `git add -A; … git commit` — 35 and 21 of the misfires;
- `handoff-checkpoint <<'JSON'` whose payload names a `.claude/` path;
- a heredoc writing a design doc that rejects `claude --print`.

**The rule, if that hook is ever written: strip heredoc bodies before matching,
or use a real parser.** The neighbour table above is the same lesson paid for by
accident — the first pass was exactly that naive matcher, and it read 300 `EOF`
delimiter lines and 201 instances of the word `the` as commands.

Not heredoc-specific, and therefore not a finding: a command *inside* a heredoc
fed to an interpreter is invisible to a segment-matched deny rule. So is
`bash -c '…'`, and so is a base64 pipe. The deny rule's limit is that it matches
segments, not that heredocs exist.

## What did not need the scrape

`( cd … )` should stop being advertised regardless of how either decision goes:
it is 7.9% of all Bash calls, it defeats the exclusion matcher, and it forfeits
read-only status — three costs and no benefit now that finding 3 in 2c has
removed the reason it was suggested.
