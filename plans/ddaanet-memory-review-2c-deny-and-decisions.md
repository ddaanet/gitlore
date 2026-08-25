# ddaanet memory review — entry 2c · the deny predicate, the remaining changes, and the decisions

Part of [ddaanet memory review](ddaanet-memory-review.md), continuing
[2b](ddaanet-memory-review-2b-exclusion-scope.md). The deny predicate, proposed
changes (a-bis) through (f), the permission pipeline, and what is taken versus
open.

### The deny predicate: silent corruption, not failure

The distinction that makes the list small is whether the agent can *tell*. A
sandbox failure that raises an error is self-correcting — the agent sees it and
retries. Only silently wrong output needs blocking.

Silent, and worth denying:

- the `git status` family, `git ls-files --others`, `git add -A`/`.` — the masks
  appear as untracked paths, and `add` tries to stage character devices;
- `ls` / `find` / recursive `grep` **when scoped to the project root or
  `.claude/`** — not the targeted majority tallied in
  [2b](ddaanet-memory-review-2b-exclusion-scope.md);
- `ps` / `pgrep` — measured this session at **5 lines sandboxed against 141
  real**, so background tasks are simply invisible;
- `claude -p` — `sandbox-effects` already records that it silently drops every
  `SessionStart` hook.

Loud, and not worth denying: network commands, `git` write locks, sibling
worktree `Read-only file system`, `Device or resource busy` on `.git/config`.
These already announce themselves.

**Mask scope is this session's project root only.** `find -maxdepth 1 -type c`
returns zero in `/Users/david/code/handoff`, `/micro` and `/edify`, so
cross-repo commands are not affected by them.

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

`unsandbox-git-status` does the second.
`hooks/require-unsandboxed-git-status.sh` segments the command only to *detect*
`git status`, then re-emits `.tool_input` verbatim with one field flipped,
alongside `permissionDecision: "allow"`. So any command containing a
`git status` segment runs wholly unsandboxed and pre-approved —
`git status && <anything>`. Confirmed live: `true && git status --porcelain` was
rewritten. Report this to that repo.

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
  pattern** — `git [-C <path>] (status|add|commit|checkout|reset)`,
  `ls .claude`, `ls -A`, `ps`, `claude` — with the denial message naming the
  retry. Costs one extra call per sensitive command, no context overhead. This
  is the only slice that covers the **silent** failures: a sandboxed
  `git status` returns phantom dotfiles with exit 0 and no error, so nothing
  downstream can detect it.
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

Confirmed live: an `ls` of an unrelated repo failed with `apply-seccomp:
unshare(CLONE_NEWUSER): Invalid argument`, and the identical command retried
unchanged succeeded. The transient reading holds, and escaping the sandbox on
first sight gives it up for nothing.

**(b) Demote "Strict sandbox mode blocks the escape".** Technically correct and
currently over-salient: unsandboxed-fallback plus auto mode is what ddaanet
repos are actually configured with, so a reader hitting `Read-only file system`
weighs the rare case first. Compress to a short paragraph, and state the usual
configuration as the baseline the rest of the file assumes.

**(c) `.claude/settings.json` writes go through the built-in `update-config`
skill.** Verified in the CC 2.1.233 bundle: `name:"update-config"`,
`menuDescription:"Change settings: hooks, permissions, environment variables"`,
"Use this skill to configure the Claude Code harness via settings.json". The
file currently says the `Edit` tool *can* write that path. Whether
`update-config` also clears the `enabledPlugins` classifier denial is
**untested**; record it as open rather than asserting either way.

**Add rather than replace.** The `Edit` sentence states a mechanical contrast —
the command sandbox blocks a raw git unlink of the path, and a harness tool is
not under that sandbox — which nothing here refutes; the bundle read establishes
only that `update-config` exists and is sanctioned, not that `Edit` fails.
Naming the skill as the route and keeping the contrast costs a clause. Both are
unverified in this pass, and probing the `Edit` half means writing user config,
so neither gets asserted harder than it is.

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
multi-fact reference file. See the reopened entry 1 note in the
[ledger](ddaanet-memory-review.md).

**Adjacent, outside the four options:** sandboxed `claude -p` failing every
`SessionStart` hook on `EROFS … session-env/<id>` is a Claude Code bug, not
memory work.

### The permission pipeline, and what it costs to leave the sandbox

Decompiled 2026-08-16 from the same CC 2.1.233 bundle. Three findings; the first
two overturn verdicts recorded in
[2b](ddaanet-memory-review-2b-exclusion-scope.md).

**(1) A read-only command is auto-allowed ahead of the classifier, sandboxed or
not.** The bash evaluator ends with

```js
if (hp.isReadOnly(e) && !H_S(e,n) && !i.some(…))
  return {behavior:"allow", decisionReason:{type:"other", reason:whn}}
```

with `whn = "Read-only command is allowed"`. Nothing on that path consults
sandbox state — unlike `hUf` and `R_S`, the two sandbox shortcuts, which both
bail on `!TV(e)`. So `git log`, `git diff`, `git show`, `ls -a`, `find .` cost
no classifier call whether or not they run in the sandbox, and excluding them is
free on the cost axis.

`isReadOnly(e)` is `U2f(e, S3r(e.command)).behavior === "allow"`. `U2f`
tree-sitter-parses the command and requires **every** segment to pass a
flag-aware table — `git diff|log|show|shortlog|reflog|stash list|ls-remote|
status|blame|ls-files|config --get|remote show|remote|merge-base|rev-parse|
rev-list|describe|cat-file|for-each-ref|grep|stash show|worktree list|tag|
branch`, the `gh …` set, `docker logs|inspect` — plus a plain-command allowlist
(`cat head tail wc stat du df diff readlink pgrep …`) and regex forms, among
them
`/^ls(?:\s+[^<>()$`|{}&;\n\r]*)?$/` (so `ls -a` qualifies) and a `find` regex
excluding only `-delete -exec -execdir -ok -okdir -fprint/-fprint0 -fls
-fprintf -files0-from`.

The disqualifiers matter more than the table:

- **any subshell or `compound_statement` anywhere** — `B2f` recurses the whole
  tree; **any `&`** — `F2f`;
- **any unquoted variable expansion**, and any `$` inside a git argument;
- **a `cd` anywhere in a call that also contains git** —
  `if ((t || o.commands.some(gJe)) && a) return passthrough`, where
  `t = S3r(cmd)` is "some segment starts with `cd`/`pushd`/`popd`/`chdir`";
- **git segments when `isSandboxingEnabled()` and cwd ≠ the original cwd** —
  keyed on the global setting, so `dangerouslyDisableSandbox` does not exempt
  it;
- **`git -C`, `-c`, `--git-dir`, `--work-tree`** — `A4p` scans leading git
  global options and returns false outright on any member of `Omv` — `-c`, `-C`,
  `--exec-path`, `--config-env`, `--git-dir`, `--work-tree`, `--bare`,
  `--attr-source`, `--help`, `-h`, `--shallow-file`. Options outside that set
  (`--no-pager`) pass. The table key is built as `git <sub> <sub2>` with a
  fallback to `git <sub>`, which is how `git config --get` and `git stash list`
  resolve.

So the only cheap shape is a bare `git <subcommand>` from the original cwd, with
no `cd`, no `-C`, no subshell and no `$VAR`. Every mechanism for reaching a
subdirectory — `cd &&`, `(cd …)`, `git -C` — forfeits it.

**(2) Hook position: `updatedInput` alone defers, `permissionDecision`
settles.** PreToolUse hooks run before any permission evaluation. When a hook
returns `updatedInput` with no decision, `HRn` yields
`{type:"hookUpdatedInput"}` and the caller assigns `v = ae.updatedInput`,
replacing the working input; `PDb` then takes

```js
if (e?.behavior !== "allow" && e?.behavior !== "ask")
  return {decision: await o(t, r, n, i, s), input: r}
```

— the full pipeline, on the rewritten input. With `permissionDecision: "allow"`
the only re-check is `rIt`, which returns non-null solely for a matching deny
rule, a matching ask rule, or two narrow ask reasons; a `passthrough` from
`checkPermissions` yields `null` and the hook's allow stands. That is the exact
difference between a safe rewrite hook and one that circumvents the gate.
`updatedInput` is schema-validated against the tool's `inputSchema`, and a
failure converts to a deny. `permissionDecision: "defer"` exists but is
print-mode-only and solo-tool-only.

**(3) A subshell defeats the exclusion matcher, not the AST classifier.**
`U0` recurses only into `KGs = new Set(["program","list","pipeline",
"redirected_statement"])`, so `(cd sub && git status)` is pushed whole as one
`node.text` segment and matches no `git:*` entry — it stays sandboxed and still
shows the phantom dotfiles. It is *not* "too-complex", though: `hge` has a
dedicated `if (e.type === "subshell")` branch that descends and collects the
inner commands, so `hUf` is still reached and a sandboxed subshell is
auto-allowed cheaply. Read-only status is lost separately, via `B2f`.

### Decisions taken from this, and what is still open

**Taken.**

- Add sandbox exclusions rather than a hook. `find:*` (100% hit rate) and `ls:*`
  are in; `claude:*` is in, because a sandboxed `claude -p` returns a normal
  reply while silently dropping every `SessionStart` hook — the strictest silent
  failure in the file. `claude -p` is not read-only (only `claude -h`/`--help`
  are), so it takes a classifier call, negligible against spawning an agent. It
  covers direct invocations only: `just evals` and `just release` reach
  `claude -p` inside a recipe, where the token is never a top-level segment.
- Retire `unsandbox-git-status`, sequenced *after* the exclusions are in and
  verified — it carries 97% of `git status` traffic today. It lives in another
  repo, so the removal needs a brief and an explicit go-ahead.
- `cwd-safety` loses its `permissionDecision: "allow"`, which circumvented the
  permission system. With the subshell rewrite dead (finding 3), the `allow` has
  nothing left to serve, so FR5a, FR5b and FR5c collapse together and the hook
  returns to exit-0/exit-2 with no `updatedInput` and no decision at all.
  Re-scope: permit `cd <dir> && …` and let cwd drift, block a non-`cd`-prefixed
  command when cwd ≠ root, and allow a bare `cd <E>` as the restore (`cd` is
  read-only, so the restore is free). Do not advertise `(cd … && …)` — it breaks
  the exclusion. Blocking always costs a turn; allowing costs one only when a
  later command actually needs root.
- A `SessionStart` check for missing exclusions belongs in `prohibitions`, not
  gitlore: `excludedCommands` is user-scope (`~/.claude/settings.json`), so the
  check fires in every repo. The agent cannot write that file — the classifier
  denies self-config — so the paired skill goes through the built-in
  `update-config` skill, or prints the `/sandbox` action; the native writer is
  `KVs`, telemetry `sandbox_exclude_command`. Caveat: a sandboxed `claude -p`
  drops `SessionStart` hooks, so the check silently will not run there.

**Corrected in the reasoning across 2a–2c.** The loud-versus-silent split used
to pick the deny set is the wrong axis; the question is whether the error leads
to a correct recovery. Three classes: *silently wrong* (the `git status` family,
`ls -a`, `find`, `ps`/`pgrep`, dropped `SessionStart` hooks);
*misleadingly wrong* (`index.lock` — the message names a concurrent git process
that does not exist, so the agent deletes a lockfile that is not there and then
hunts for a cause, which is worse than silence); *correctly diagnosable*
(`Device or resource busy` on `.git/config`, sibling-worktree
`Read-only file system`, zellij "no active session"). Only the third class is
safe to leave sandboxed. That puts `git add:*` and `git commit:*` in the
exclusion set on their own merits — `add` strands the lock, `commit` is where
the misleading error surfaces — and banning `git add -A`/`.` does not remove the
need, since an explicit pathspec strands it too. Also corrected: a classifier
call is one model call over cached context with no generation, so it is cheaper
than an agent turn; batching `cd <E> && git status` into one call beats
splitting it, and the cd+git rule is a cost to note rather than a shape to
avoid.

### Verification of the exclusions, once written

Written to user-scope `~/.claude/settings.json` through the built-in
`update-config` skill, using `Edit`; the classifier did not refuse it, so the
route works for `sandbox.excludedCommands`. Whether it also clears the
`enabledPlugins` denial stays untested. The superseded `"git status"` exact
entry was dropped in the same edit — `git:*` strictly covers it.

`${TMPDIR-UNSET}` as the discriminator, each probe its own call:

| probe | result |
|---|---|
| `echo` alone (control) | `/tmp/claude-1000` — still sandboxed |
| `git log -1 --oneline; echo …` | `UNSET` |
| `ls -a; echo …` | `UNSET`, and the listing carries none of the 22 masks |
| `find . -maxdepth 1 -type c; echo …` | `UNSET`, zero masks |
| `claude --version` | ran; **not** discriminated, see below |

Three of the four are confirmed unsandboxed by direct reading. `claude:*` rests
on the same matcher rather than on its own measurement, because every form
carrying the discriminator was denied.

**The observed cost: unsandboxed commands reach the classifier, and it denies
benign compounds unpredictably.** `ls -a | wc -l; echo "…${TMPDIR-UNSET}"`,
`find … | wc -l; echo …` and `claude --version; echo …` were each refused, while
`ls -a; echo …`, `find …; echo …`, `git log …; echo …` and a bare
`claude --version` passed. No stable rule separates them — the pipe is not it,
since the `claude` denial carries none. This is judgement, not a predicate, and
it matches the idiosyncrasy `classifier-denied-self-config` already records.

Before the exclusions these calls were auto-allowed by
`autoAllowBashIfSandboxed` with no classifier involvement, so the denials are
new. That is the price of the containment decision taken above, now observed
rather than predicted, and it lands hardest on `git:*` — a third of Bash
traffic. The mitigation is shape rather than settings: keep an excluded command
in its own call instead of appending a compound to it. Carry this into the
memory pass; no existing fact states it.

**Both settled.** The corpus scrape is in
[2d](ddaanet-memory-review-2d-corpus-scrape.md); my human partner has taken
both calls on the evidence there.

1. **Settled — `git:*`, see 2d.** The narrow set cannot match `git -C` (2,142
   calls, 31.6% of git traffic), and coverage is the whole question: writes must
   be unsandboxed or they strand the lock, mask-sensitive reads must be or they
   corrupt, and read-only git is short-circuited either way so sweeping it in
   costs nothing. `git add -A` is prohibited on its own merit, separately. What
   the decision accepts is containment, not gating: a third of Bash traffic runs
   unsandboxed with its neighbours, all still classifier-gated.
2. **Settled — see 2d.** `cwd-safety` always allows a `cd`-prefixed composite
   and keeps the rule-4 drift block with an updated message. Read against the
   hook as it stands this is a pure relaxation: rules 3, 1 and 5c stop blocking
   and stop rewriting, rule 4 is unchanged. It also unblocks decision 1, since
   the subshell rewrite it removes was the thing making `(cd sub && git status)`
   unmatchable by any exclusion entry.

**Memory.** Finding (1) is **applied**: the `excludedCommands` bullet in
`sandbox-effects` said an excluded command is evaluated by the auto-mode
classifier, which is false for the read-only class. It now names the
sandbox-independent read-only auto-allow, its disqualifier list, and the cheap
shape. The index line is deliberately unchanged — its existing literals already
route a reader here, and the index is over budget.

Finding (2), the hook-decision semantics (`updatedInput` alone defers to the
full pipeline, `permissionDecision` settles it), is **deferred to the end of the
pass**. No existing fact owns it: `hook-output-channels` owns the channels and
`hook-cannot-inject-tool-calls` owns `updatedInput`'s existence, but neither
owns its gating effect. My human partner leans toward **combining the
hook-related memories** rather than adding a fourth — out of scope until the
pass reaches them.
