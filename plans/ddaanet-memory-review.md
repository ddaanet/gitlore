# ddaanet memory review

Working ledger for a pass over all 100 `memory/ddaanet/` facts, ordered by index
line size, largest first. Each entry records the verdict against the
`memory-writing` rubric and my human partner's decision.

Index at start of pass: 26,219 B across 101 lines (100 ddaanet + 0 project),
against Claude Code's 24.4 KB loader cap. 100 ddaanet fact files.

Verdict vocabulary: **keep** (save as written) · **update** (edit body or index
line) · **merge** (fold into another fact) · **retire** (delete) · **relocate**
(to `shared-claude.md` or a repo `CLAUDE.md`) · **plugin** (becomes a skill,
feature request or bug report).

| # | Bytes | Fact | Verdict | Decided |
|---|-------|------|---------|---------|
| 1 | 867 | `memory-writing` | keep | done — skill question deferred to end of pass |
| 2 | 760 | `sandbox-effects` | update (relocate + merge out) | pending |

---

## 1 · `memory-writing` — 867 B

Largest line in the store, 3.3% of the index.

**Rubric.** Incident: yes, several quoted corrections. Reader-unaided: no.
Reconstructable: model-inference class, failure silent — carry it. Moment: one
— about to write, review, merge or retire a fact; the file already absorbed
three by-topic splits into that single moment. Tier: correct. Strip: clean —
present tense, no deictics, the two first-person quotes are attributed
corrections and already carry `hygiene-ok` markers. Index line: carries four
distinct trigger sets (what to cut · new-file-vs-merge · which tier · routing a
fact up); not compressible without dropping one whole.

**Verdict: keep as written.**

**Deferred: ship it as a `gitlore:memory-writing` skill instead.** gitlore ships
`merge`, `push`, `recall`, `resolve` — nothing owns authoring. This file is a
procedure with a mechanical, detectable trigger (a write under `memory/`), which
is the skill-not-command case, and its own doctrine says a fact whose body
reduces to "when writing a memory, do X" belongs in the skill that fires at that
moment. Converting it frees 867 B of capped index and moves the text to a budget
that is not silently truncated. Raised once at the end of the pass, together
with the other guide-shaped facts that pose the same question.

## 2 · `sandbox-effects` — 760 B

**Rubric.** Incident: yes, every section dated and reproduced. Owner: none —
these are undocumented harness behaviours. Reader-unaided: no.
Reconstructable: no. Tier: correct, the mechanism is the harness, not this repo.
Index line: 760 B of pure WHEN literals (`index.lock`, `Device or resource
busy`, `apply-seccomp: unshare(CLONE_NEWUSER)`, …), all load-bearing.

Six changes.

**(a) The read-only-inspection default goes to the `prohibitions` plugin, not
to `shared-claude.md`.** The paragraph granting standing permission to call
`dangerouslyDisableSandbox` on `git status`/`log`/`diff`/`show`/`branch`/
`rev-parse`/`ls-files`/`blame` and adjacent file reads is acted-inline: it fires
while *composing* the command, with no symptom and no lookup step, and it
inverts the Bash tool's own instruction not to set that flag unless a command
has already failed. Relocation to always-on prose is the wrong lever when the
condition is mechanically detectable — `prohibitions` exists precisely to pay
for such a rule at the moment of action instead of in every session's context.

**Every noisy case folds into command-pattern matching except one.** Matching on
error text is a drift surface with a silent failure mode — the same objection
`git-stderr-and-parsing` already records against git's parenthesized push
reasons — and the matcher stops firing without anyone noticing. Walking the
symptoms back to the command that produced each:

| symptom | producing command | foldable |
|---|---|---|
| `Unable to create '.git/index.lock'` | `git add`, `git commit` | yes |
| `Device or resource busy` / `Read-only file system` on config paths | `git checkout`, `reset --hard`, `branch -d`, `merge` | yes |
| sibling-worktree `Read-only file system` | `git -C <outside>`, `git worktree remove`, `cp`/`mv` out of tree | yes, by path scope |
| `No conversation found with session ID` | `claude --print --resume` | yes |
| dropped `SessionStart` hooks (silent) | `claude -p` | yes, and must be PreToolUse |
| `$TMPDIR` expands empty | any **unsandboxed** call using `$TMPDIR` | yes, on the tool input itself |
| `There is no active session!` | `zellij run`/`action` | yes |
| `apply-seccomp: unshare(CLONE_NEWUSER)` | any command at all | **no** |

`$TMPDIR` is the clearest gain: matching `dangerouslyDisableSandbox: true`
together with `$TMPDIR` in the command string is a structural test on the tool
input, where the alternative was matching `/foo.log: Permission denied`.

`apply-seccomp` resists folding because it attaches to no command class — a
plain `grep` raises it. It also needs no hook, per the retry finding below.

**The harness already has the mechanism: `sandbox.excludedCommands`.** A real
settings key, and my human partner already runs
`"sandbox": {"enabled": true, "autoAllowBashIfSandboxed": true,
"excludedCommands": ["git status"]}`. Strict mode's own description is "All bash
commands invoked by the model must run in the sandbox unless they are explicitly
listed in excludedCommands", so the list is honoured even there; docs at
`code.claude.com/docs/en/sandboxing#configure-sandboxing`. Whether it matches a
compound command is **unverified** — the `unsandbox-git-status` hook fires first
and masks the experiment. Settle it by adding a compound to the list and
observing, not by reasoning.

A hook can also read `sandbox.enabled` from the settings chain directly, since
hooks run outside the sandbox. So "only block when sandboxing is on" is
available either way.

### The test that settles `excludedCommands` semantics

Four implementations are possible and the choice between them decides everything
downstream: **(a) whole-command match** — a compound never matches, so the
exclusion is useless in the dominant case; **(b) any-segment match** — one
excluded segment unsandboxes the whole call, which is the same scope hole
`unsandbox-git-status` has; **(c) all-segments match** — a compound is excluded
only when every segment is; **(d) per-segment** — excluded segments run
unsandboxed and the rest stay sandboxed within one call, so
`ls -d ~/.claude/ide && dangerous` runs `ls` free and `dangerous` contained.

(d) needs no command parsing at all — only that the sandbox be overridable at
`exec` time, with the enforcement layer checking argv against the list as each
program is launched. The mechanism is undetermined and the test does not depend
on knowing it.

**Discriminator:** `${TMPDIR-UNSET}`. Verified 2026-08-15 — a sandboxed call has
`TMPDIR=/tmp/claude-1000`, and an unsandboxed one has it unset, which this file
already records under the escape's costs. Zero side effects, reads the per-call
state directly.

**Probe with `ls`, never `git`** — the existing `git status` entry and the
`unsandbox-git-status` hook would both confound a git probe.

**Configured.** `~/.claude/settings.json` `sandbox.excludedCommands` now reads
`["git status", "ls -d /Users/david/.claude/ide"]`. The entry is the exact probe
string rather than a bare `ls`, so nothing an agent runs incidentally is
unsandboxed while it sits there — under (b) a bare `ls` entry would unsandbox
every compound containing one. **Remove the second entry once the reading is
taken.**

Run each row as its own Bash call, in a session started after the settings
change, with no `dangerouslyDisableSandbox` anywhere:

| # | probe | reading |
|---|---|---|
| 0 | `printf '%s\n' "${TMPDIR-UNSET}"` | control — must print `/tmp/claude-1000` |
| 1 | `ls -d /Users/david/.claude/ide/` | trailing slash, so it cannot match the entry — must **fail**, which is what proves the discriminator works |
| 2 | `ls -d /Users/david/.claude/ide` | succeeds ⟹ the list matches on argv, not just the command name |
| 3 | `ls -d /Users/david/.claude/ide && printf '%s\n' "${TMPDIR-UNSET}"` | fails at `ls` ⟹ (a) or (c) · succeeds + `UNSET` ⟹ (b) · succeeds + a path ⟹ **(d)** |
| 4 | `ls -d /Users/david/.claude/ide && ls -d /Users/david/.claude/ide` | only if row 3 said (a)/(c): succeeds ⟹ (c), fails ⟹ (a) |
| 5 | `sh -c 'ls -d /Users/david/.claude/ide'` | only if (d): succeeds ⟹ the exclusion reaches descendants, fails ⟹ top-level `exec` only |

Row 1 failing and row 2 succeeding is the pair that makes the rest meaningful:
together they show the read-deny is live *and* the entry is being matched. If
row 2 also fails, matching is by command name only — widen the entry to `"ls"`,
re-run, and remove it immediately afterwards.

Row 3 is what separates (d) from everything else: it reads the excluded and the
unexcluded command's sandbox state in the same call, which no single-state probe
can do.

The descendant probe matters because it decides how far an exclusion reaches. If
exclusions apply only at the top-level `exec`, then excluding `git` leaves
everything git spawns — pager, alias, hook, filter — sandboxed and separately
evaluated, which contains `git -c core.pager='sh -c …'` on its own. If
exclusions are inherited, that containment is gone and a bare `git` entry is
much harder to justify.

### Excluding `git` outright, or read subcommands only

**Contingent on the result above.** Under (b), exclude nothing: `git status &&
curl … | sh` would run unsandboxed, reproducing the plugin's hole natively, and
a deny hook is the only safe slice. Under (a) or (c), exclude `git` **outright**.

Every sandbox failure this file documents is on a *write* subcommand — the
`index.lock` stranding is `add`/`commit`, `Device or resource busy` on
`.claude/settings.json` and `.git/config` is `checkout`/`reset --hard`/`branch
-d`, `unable to unlink old 'hooks/hooks.json'` is `merge`. A read-only exclusion
fixes none of them, which is the whole reason the escape keeps being needed.
Unsandboxed is not unchecked: it moves git under the classifier, the gate that
actually understands git risk such as a push to a foreign repo. And a
per-subcommand allowlist is one more matcher to maintain, which is the drift
objection already raised against error-string matching.

**Permission ordering: hooks first, and the rest is the hook author's choice.**
The decision strings in the 2.1.233 bundle run `Auto-allowed with sandbox
(autoAllowBashIfSandboxed enabled)` · `Read-only command is allowed` ·
`bashCommandClamp: no clamp rule matches this command` · `Classifier
unavailable` · `Auto mode could not evaluate this action and is blocking it for
safety`. Sandboxed commands are auto-allowed *without* the classifier, so
removing the sandbox moves a command **into** classifier evaluation rather than
around it. Therefore:

- `updatedInput` alone → falls through to permission evaluation; the command is
  no longer sandboxed, `autoAllowBashIfSandboxed` no longer applies, the
  classifier weighs it. **Safe** — this is the construction to use.
- `updatedInput` **plus** `permissionDecision: "allow"` → the gate is bypassed
  by the hook's own decision. **Unsafe for compounds.**

`unsandbox-git-status` does the second. `hooks/require-unsandboxed-git-status.sh`
segments the command only to *detect* `git status`, then re-emits
`.tool_input` verbatim with one field flipped, alongside
`permissionDecision: "allow"`. So any command containing a `git status` segment
runs wholly unsandboxed and pre-approved — `git status && <anything>`. Confirmed
live: `true && git status --porcelain` was rewritten. Report this to that repo.

That settles rewrite-vs-deny in favour of **deny** for compounds: composite
commands are the common shape, and rewriting them is precisely the unsafe case.
The single read-only command is better served by native `excludedCommands` than
by any hook.

**Correction to the memory.** It states the plugin's notice "goes to
`systemMessage` (user channel, not model context), so the agent may never learn
a command was auto-unsandboxed". Stale — the hook now emits `additionalContext`
as well, and it arrived in this session's tool results. Fix the line rather than
repeating it.

**Deny is not the only PreToolUse verb.** `updatedInput` can flip
`dangerouslyDisableSandbox` in place, which is what `unsandbox-git-status`
already does and why it costs no extra call. The real objection to it is scope:
it unsandboxes the whole command around the `git status`. That is fixable by
keying on command *shape* rather than substring:

- command is solely sensitive **read-only** ops → `updatedInput` flips the flag,
  no extra call, and a `additionalContext` note so the agent does not read the
  clean result as evidence the sandbox is clean;
- command mixes a sensitive op with anything else → deny, message says split it;
- command is a sensitive **mutating** op (`commit`, `checkout`, `reset`) → deny
  with the retry instruction, never a silent unsandbox of a write;
- unsandboxed command referencing `$TMPDIR` → deny, naming the scratchpad path.

Three slices, and they are not equivalent:

- **`PreToolUse` deny on a sandboxed Bash call matching a sandbox-sensitive
  pattern** — `git [-C <path>] (status|add|commit|checkout|reset)`, `ls .claude`,
  `ls -A`, `ps`, `claude` — with the denial message naming the retry. Costs one
  extra call per sensitive command, no context overhead. This is the only slice
  that covers the **silent** failures: a sandboxed `git status` returns phantom
  dotfiles with exit 0 and no error, so nothing downstream can detect it.
- **`PostToolUse` match on the known error strings** (`Unable to create
  '.git/index.lock'`, `Device or resource busy`, `Read-only file system`,
  `apply-seccomp: unshare(CLONE_NEWUSER)`, `No conversation found with session
  ID`) injecting the recovery. Free on the happy path, but only reaches
  failures that announce themselves.
- **Rewriting the call in place**, which is what `unsandbox-git-status` does
  today. Narrower detection than either of the above and it unsandboxes the
  whole command around the `git status`, which is more than the rule asks for.

Recommended split: `PreToolUse` deny for the silent set, `PostToolUse`
directions for the noisy set, and retire the in-place rewrite. The memory keeps
the paragraph until a replacement ships, then shrinks to the mechanism and
points at the hook.

**(a-bis) `apply-seccomp` — the remedy is a plain retry, not an unsandboxed
one.** The section currently treats the error string as sufficient evidence to
escape the sandbox, which encodes a permanent-failure reading. Measured on this
box: `kernel.unprivileged_userns_clone = 1` and `user.max_user_namespaces =
2147483647`, so the standing-policy cause — the one that would make retrying
pointless — does not obtain. `unshare(2)` returns `EINVAL` for `CLONE_NEWUSER`
in a multithreaded caller, which is a per-invocation condition, and the box OOMs
at ~2 GB, so a transient failure at namespace setup is the live hypothesis. The
cause is not established; the rule that follows either way is: **retry the
identical command once, unchanged.** If it fails the same way immediately, then
escape. That costs at most one call and keeps the sandbox in the transient case,
where the current advice gives it up on first sight.

**(b) Demote "Strict sandbox mode blocks the escape".** Technically correct and
currently over-salient: unsandboxed-fallback plus auto mode is what ddaanet
repos are actually configured with, so a reader hitting `Read-only file system`
weighs the rare case first. Compress to a short paragraph, and state the usual
configuration as the baseline the rest of the file assumes.

**(c) `.claude/settings.json` writes go through the built-in `update-config`
skill.** Verified in the CC 2.1.233 bundle: `name:"update-config"`,
`menuDescription:"Change settings: hooks, permissions, environment variables"`,
"Use this skill to configure the Claude Code harness via settings.json". The
file currently says the `Edit` tool *can* write that path — replace with the
skill, which is the sanctioned writer and an owner in the memory-writing sense.
Whether `update-config` also clears the `enabledPlugins` classifier denial is
**untested**; record it as open rather than asserting either way.

**(d) Name the mechanism in the slash-command section.** The `## Context`
injection is `` !`cmd` `` expansion in the command body, not a special harness
behaviour — verified in `commit-commands/commands/commit.md`, which carries
`- Current git status: !\`git status\``. It runs sandboxed before the agent
acts. No in-place fix exists, but a `UserPromptSubmit` hook can resolve the
named command file, grep it for `` !` `` blocks holding sandbox-sensitive
commands, and inject a warning — the hook sees the command *name*, not the
expansion, so it has to read the file. A fourth `prohibitions` feature request.

**(e) Merge "Cross-repo push needs `/add-dir`" into
`classifier-denied-self-config`.** Its own heading says "classifier, not
sandbox", and the other file already owns the denial and the `/add-dir`
resolution. Two files each answer half of "why was my cross-repo push denied?".
`sandbox-effects`' index line never advertised `/add-dir`, so the cut loses no
route. Two residues must travel rather than be dropped: the verdict string
*external repo outside the trusted source control org*, and the fact that
removing `Bash(git push:*)` **ask** directives does not help, because ask rules
control prompting only and their absence is not authorization — with an explicit
`allow` rule as the alternative to `/add-dir`. That adds ~50 B to the
`classifier-denied-self-config` line; a merge for routing, not for headroom.

**(f) Restructure.** The file is ordered by discovery rather than by symptom,
which is backwards for a 386-line WHEN reference an agent enters holding an
error string. Concretely:

- One symptom, `Unable to create '.git/index.lock': File exists`, is split
  across two sections describing three cases, with the discriminator only in the
  second. It is one section with one decision procedure: mask (vanishes
  unsandboxed) · stranded (unsandboxed retry succeeds) · genuinely stale
  (persists unsandboxed, `rm` it).
- `dangerouslyDisableSandbox` availability is discussed in four places — strict
  mode, the phantom-dotfile how-to-apply, the read-only default, and the
  `$TMPDIR` cost. One section on the escape and what it costs, referenced from
  the symptom sections.
- `$TMPDIR` unset is a cost *of the escape*, not a sandbox effect; it belongs in
  that section.
- Add a lead symptom → section map, the in-file equivalent of what the index
  line does for the store.

The dated evidence in each remaining section grounds a claim and stays.

**Feeds back into `memory-writing`:** it has no guidance on structuring a
multi-fact reference file. See the reopened entry 1 note below.

**Adjacent, outside the four options:** sandboxed `claude -p` failing every
`SessionStart` hook on `EROFS … session-env/<id>` is a Claude Code bug, not
memory work.

## 1b · `memory-writing` — reopened

`memory-writing` governs what a fact says and which file it lands in.
`index-compaction-triggers` governs the line pointing at it. Neither says how to
organise the file itself once it holds a dozen independent facts under one
trigger — which is the shape every merged reference in this store converges on.
Proposed addition, drawn from what went wrong in `sandbox-effects`:

- Order sections by the literal a reader arrives holding, never by discovery
  order.
- One section per symptom. A symptom whose cases differ gets one section with a
  discriminator, not one section per case.
- Discuss a shared remedy in one place and reference it; a remedy restated in
  four sections drifts in four directions.
- Past roughly a screen of sections, lead with a symptom → section map.
- A fact that is a *cost of the remedy* files under the remedy, not under the
  symptom that led you to it.
