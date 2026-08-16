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

### Reading taken — the answer is (b), any-segment

Measured 2026-08-15 against CC 2.1.233, with
`"excludedCommands": ["git status", "ls -d /Users/david/.claude/ide"]`, each row
its own Bash call and no `dangerouslyDisableSandbox` anywhere. The probe entry
has since been removed from `~/.claude/settings.json`. `${TMPDIR-UNSET}` is the
discriminator throughout: `/tmp/claude-1000` sandboxed, `UNSET` not.

**The mechanism, in one sentence.** The command string is parsed by tree-sitter-bash
into a list of simple commands; each one is expanded into a closure of normalised
variants; if any variant of any segment matches any list entry, the **entire call**
runs unsandboxed, including segments that match nothing.

### The algorithm, decompiled from the 2.1.233 bundle

Sandboxing is decided once per call, by a function returning a single boolean —
whole-call granularity is the design, not an oversight:

```js
function TV(e){                                  // "should this run sandboxed?"
  if (U$() && DFe()) return true;                // forced-sandbox contexts
  if (!ei.isSandboxingEnabled()) return false;
  if (shellType==="bash" && windows && no shell) return false;
  if (e.dangerouslyDisableSandbox && ei.areUnsandboxedCommandsAllowed()) return false;
  if (!e.command) return false;
  if (W_S(e.command)) return false;              // ← the exclusion check
  return true;
}
```

`W_S` splits, normalises, then matches.

**Split — `U0(cmd)`.** A real tree-sitter-bash parse, walked as follows:

- recurse **only** into node types `program`, `list`, `pipeline` (the set `uWs`);
- skip the operator tokens `&&` `||` `|` `;` `&` `|&` newline (`npd`), and `comment`;
- for `redirected_statement`, recurse into children whose type does not end in
  `_redirect` — this is why a trailing redirection is invisible to the match and
  an interleaved one is not;
- **anything else** — subshell, `if`/`while`, function definition, command
  substitution — is pushed whole as `node.text`, a raw source slice.

Bail-outs return the entire string as one segment: empty input, a command longer
than `$Fe`, or a parse failure.

Two consequences. Every construct that is not a plain list or pipeline **fails
closed**: `( … )`, `$( … )`, `if …; fi` and `sh -c '…'` are pushed as one blob
that will not match, so they stay sandboxed. And because the segment is
`node.text`, the comparison sees source text, not re-rendered argv — which is why
double spaces and quotes defeat it.

**Normalise.** Each segment seeds a worklist expanded to a fixpoint; every derived
string is fed through both functions again, and *all* variants are match
candidates:

- `bHi(s, /^(LD_|DYLD_|PATH$)/)` — repeatedly strip leading `VAR=value`
  assignments, **stopping** at any name matching `LD_*`, `DYLD_*` or `PATH`.
- `q_e(s)` — drop comment lines, unquote the first token, and strip leading
  wrapper commands: `timeout [opts] N[smhd]`, `time`, `nice [-n N]`, `stdbuf
  -[ioe]X`, `nohup`, `command [-p]`, `builtin`, `noglob`. It also strips
  assignments, but only for names in an allowlist `F3n` (`GOOS`, `NODE_ENV`,
  `TZ`, `LANG`, `CI`, `ANTHROPIC_API_KEY`, …).

**Match — entries are permission-rule patterns, not plain strings.** `B4o` parses
each entry, and `xUf` applies it:

| entry form | type | matches |
|---|---|---|
| `foo bar:*` | prefix | `foo bar`, or anything starting `foo bar` + **a space** |
| `foo *` (unescaped `*`) | wildcard | glob |
| `foo bar` | exact | only `foo bar` |

The prefix form requires a space boundary, so `…/probe:*` matches
`ls -d …/probe /tmp` but **not** `ls -d …/probe-anything`.

Four predictions from the decompilation, all confirmed live: `timeout 5 ls -d
…/ide` matched (wrapper stripped); `TZ=UTC ls -d …/ide` matched (allowlisted
assignment stripped); `LD_PRELOAD=… ls -d …/ide` did **not** match (guard held);
and the `:*` prefix form behaved exactly as `xUf` specifies.

**A strict matcher exists and is not used for bash.** `y5p` runs the same entry
match but first rejects any command containing `[;|&`$(){}<>#\n\r]` — i.e. it
refuses to honour an exclusion inside a compound at all. Its only caller is
`f5p`, on the Windows PowerShell path. The bash path uses the permissive `W_S`.

Twenty probes plus the four predictions, all consistent.

*What splits the command into comparable segments:*

| separator | matched | note |
|---|---|---|
| `&&` · `\|\|` · `;` · `\|` · `&` · newline | yes | the full set of list/pipeline separators |
| `( … )` subshell | **no** | not descended into |
| `$( … )` substitution | **no** | not descended into |
| `sh -c '…'` | **no** | the inner string is an argument, never a segment |
| `if … ; then … ; fi` | **no** | the segment reads `if ls -d …`, so the keyword defeats it |

*What the comparison tolerates, and what defeats it:*

| variation | matched | reading |
|---|---|---|
| leading whitespace · extra whitespace before the operator | yes | the span is trimmed |
| `FOO=1 ls -d …` | yes | leading assignments are excluded from the span |
| `ls -d … > /dev/null` | yes | a redirection *after* the last word is outside the span |
| `ls  -d …` (double space) | **no** | internal whitespace is not normalised |
| `ls -d "…"` (quoted argument) | **no** | quotes are not stripped |
| `ls -d … -l` (extra word) | **no** | equality, not prefix |
| `/bin/ls -d …` | **no** | no `PATH` resolution |
| `D=…; ls -d $D/ide` | **no** | compared before expansion |
| `ls -d > /dev/null …` (redirection *between* words) | **no** | the redirect falls inside the span ⟹ it is a source slice, not a re-render of tokens |
| the literal inside a quoted argument | **no** | word position matters; not a substring search |

Two findings carry beyond the mechanism:

**The decision is static.** `false && ls -d …/ide` — where the excluded command
provably never runs — still unsandboxes the call. Reachability is not consulted,
so the excluded command can be a decoy that never executes while the payload
does: `false && git status; <payload>` frees the whole call and runs only the
payload. (`false && git status && <payload>` does not, because the `&&` chain
short-circuits the payload as well — the decoy has to be detached from it.)

**Settings reload live.** Confirmed in both directions, mid-session and with no
restart, on three keys — `excludedCommands`, `autoAllowBashIfSandboxed` and
`permissions.deny`. The ledger's earlier instruction to probe only from a session
started after the settings change is unnecessary.

Two smaller notes. The read-deny discriminator the original probe table leaned on
does not exist — `ls -d /Users/david/.claude/ide/` **succeeded** sandboxed,
because `ls -d` only stats the path and the sandbox's read-deny does not cover
that; `${TMPDIR-UNSET}` carried the whole reading instead. And
`apply-seccomp: unshare(CLONE_NEWUSER): Invalid argument` hit one probe while the
byte-identical retry succeeded, confirming the retry-once-unchanged remedy
proposed for that entry.

The descendant question — how far an exclusion reaches — is moot under (b): the
exclusion already covers everything in the call, and no nesting construct is
matched into, so there is no narrower containment left to preserve.

### Excluding `git` outright, or read subcommands only

**Overturned — see "The permission pipeline" below.** The verdict recorded here
rested on the cost of leaving the sandbox, which the read-only auto-allow makes
near-zero for the commands at issue. The security objection in the next
paragraph is untouched and remains the live argument.

Under (b), a bare `git` entry means `git status && curl … | sh` runs entirely
unsandboxed, reproducing the `unsandbox-git-status` hole natively.

The same finding indicts the entry already in the settings file: `"git status"`
unsandboxes any compound holding that exact segment, so `git status && <anything>`
is already free today — and so is `false && git status; <anything>`, where the
decoy never even runs. It is narrower than the plugin's version — literal equality,
no substring match, no descent into `sh -c` — but it is the same class of hole,
and the plugin and the entry are redundant with each other. Whether to keep
either is a separate call for my human partner.

### What an excluded call still passes through

**`permissions.deny` outranks both sandbox auto-allow and exclusion.** With
`"Bash(sudo:*)"` temporarily in the deny list, `sudo -n true` was refused in all
three configurations: sandboxed with `autoAllowBashIfSandboxed` on, sandboxed
with it off, and carrying an excluded segment. The refusal names the *whole*
command string, so the rule is matched against the full call rather than the
segment.

That is the one substantive difference from the `unsandbox-git-status` plugin.
The plugin returns `permissionDecision: allow` alongside its `updatedInput`, so a
matching command is unsandboxed **and** pre-approved. The native key only
unsandboxes; the permission pipeline still runs. A deny rule is therefore a
usable backstop for `excludedCommands` in a way it is not for the plugin.

**Classifier engagement could not be isolated by probing — but the code settles
it, see "The permission pipeline" below: a read-only command is auto-allowed
ahead of the classifier whether or not it is sandboxed, so for that class
"unsandboxed is not unchecked" is simply false.** No command available to probe
safely was ever
denied by the classifier: `curl -s http://127.0.0.1:1/ | sh`, `sudo -n true`
before the deny rule existed, `rm -f` against a path under `~/.claude`, and a
heredoc writing into `.git/` all ran. They ran sandboxed, they ran unsandboxed
via an excluded segment, and they ran with `autoAllowBashIfSandboxed: false` —
the last being the strongest of the three, because switching the short-circuit
off leaves the classifier as the only gate, and a classifier that objected to
those shapes would have blocked them there.

This is weak evidence of absence, not evidence the classifier is skipped. The
classifier reads conversation context, and every one of those commands was
explicitly sanctioned probing in a session about sandbox behaviour — precisely
the exemption `classifier-denied-self-config` already records as *INCIDENTAL
writes only, not user-named ones*. Establishing the classifier's role needs a
payload that is classifier-hostile in a context where the user did not ask for
it, which is not constructible from inside a session that just asked for it.

**The transcript cannot settle it retroactively.** A Bash `toolUseResult` carries
only `interrupted` · `isImage` · `noOutputExpected` · `stderr` · `stdout`; no
permission decision, reason string, or sandbox flag is recorded anywhere in the
session JSONL. The decision strings quoted from the bundle are never persisted.

All probe state has been reverted: the `ls -d …/ide` and `…/probe:*` exclusion
entries, the `Bash(sudo:*)` deny rule, the `autoAllowBashIfSandboxed` flip, and a
stray `.git/gitlore-probe-zzz`. Verified by re-reading the settings file and by
re-running the canonical probe, which is sandboxed again.

### Naming the regression precisely

`excludedCommands` does not auto-approve. It sets one boolean — *sandboxed or
not* — and an unsandboxed call loses the `Auto-allowed with sandbox
(autoAllowBashIfSandboxed enabled)` shortcut by definition, which is why the
`Bash(sudo:*)` deny rule still fired on it. Auto-approval is the *plugin's*
regression, from its `permissionDecision: allow`.

The native regression is different and narrower: **a decoy segment silently
unsandboxes its neighbours.** `timeout 5 git status; <payload>` runs the payload
outside the sandbox, and nothing in the transcript records that it did.

**The safe approach my human partner describes is already a supported mode.**
`sandbox.allowUnsandboxedCommands` — the `/sandbox` menu's *Allow unsandboxed
fallback*, against *Strict sandbox mode* — is precisely "when a command fails due
to sandbox restrictions, Claude can retry with `dangerouslyDisableSandbox`
(falling back to default permissions)". Under that mode the retry is per-command,
visible, and re-enters the permission pipeline, where `excludedCommands` is a
blanket standing exemption evaluated before anything sees it. That reframes
`excludedCommands` as strict mode's escape valve rather than the general
mechanism, and is the strongest argument for dropping the `git status` entry
rather than widening it to `git status:*`.

### What the sandbox actually breaks: the phantom masks

Measured 2026-08-15 by diffing sandboxed listings against unsandboxed ones
obtained through the `git status` decoy.

The sandbox bind-mounts **`/dev/null` over 22 paths** in the project root — they
stat as `crw-rw-rw- nobody nogroup 1, 3`. The set is every file a repository
could use to hijack execution:

```
.bash_profile .bashrc .gitconfig .idea .mcp.json .profile .ripgreprc
.vscode .zprofile .zshrc
.claude/agents .claude/commands .claude/hooks .claude/launch.json
.claude/loop.md .claude/output-styles .claude/routines
.claude/scheduled_tasks.json .claude/skills .claude/workflows
.git/config.lock .git/config.worktree
```

**Scope is the project root, not the cwd**, and it reaches into `.claude/` and
`.git/`. A listing of `scripts/` is clean even with the cwd set there, and so are
`~`, `/tmp` and the parent directory. The last two entries explain the
`Device or resource busy` failures on `.git/config` that `sandbox-effects`
already records under `checkout`/`reset --hard`.

**The corruption is silent and large.** Sandboxed, `git ls-files --others
--exclude-standard` reports 19 untracked paths in this repo; the truth is 3. An
agent reading that sees `.claude/skills`, `.claude/hooks` and `.mcp.json` as
untracked additions and reasons from it. Nothing in the output marks them as
artefacts.

### Corpus: what commands this actually touches

Tallied across 1,190 session transcripts from the last 45 days — 20,736 Bash
calls (`scratchpad/tally.py`, `scratchpad/status_forms.py`).

| command | calls | affected because |
|---|---|---|
| `git status` (all forms) | 3,043 segments in 2,549 calls | phantoms appear as untracked |
| `ls` | 2,910 | phantoms listed in the root |
| `git add` | 728 | `-A`/`.` tries to add character devices |
| `find` | 627 | traverses the masked paths |
| `grep` | 8,541 | only the recursive-from-root subset |

**An exact `git status` entry covers 2.8% of the real traffic** — 84 segments out
of 3,043. The actual distribution is `git status --short` (741),
`git status --porcelain` (477), `git -C <path> status --short` (186),
`git status --porcelain=v1` (145), and a long tail.

That is the case against `excludedCommands` for this job, independent of the
security argument: **it structurally cannot express "any git status"**. The
prefix form anchors at the start of the segment, so `git status:*` still misses
every `git -C <path> status` and every `git -c k=v … status` — roughly a fifth of
the traffic — and a wildcard entry broad enough to catch them would be far too
broad to be safe. The plugin's best-effort matcher has been carrying that 97%,
which is why removing it without a replacement would regress accuracy sharply.

This supports my human partner's design directly: **deny rather than exclude, and
let the agent retry unsandboxed**. A denial is explicit, per-command, visible in
the transcript, and re-enters the permission pipeline; it cannot silently
unsandbox a neighbouring segment the way an exclusion match does.

### Exclusion does not grant approval — the code, not a probe

`hUf` is the sandbox auto-allow entry point:

```js
function hUf(e,t,r,n){
  if (!ei.isSandboxingEnabled() || !ei.isAutoAllowBashIfSandboxedEnabled()
      || !TV(e) || HIr(t)) return null;      // ← !TV(e) is exactly the excluded case
  let o = P_S(e,t,r); ...
```

`!TV(e)` returns `null`, so an excluded command never reaches the shortcut and
falls through to the ordinary permission pipeline — deny/ask rules, then the
auto-mode classifier. `P_S` itself checks deny rules first, and re-checks them
**per segment** for a compound, which is why the `Bash(sudo:*)` probe was refused
even behind a decoy.

So an exclusion is equivalent in gating to an agent-declared
`dangerouslyDisableSandbox`, minus the round-trip. The residual difference is
only defence-in-depth: the sandbox no longer contains a command the classifier
waves through.

Even the sandboxed shortcut is guarded — `hUf` also refuses to auto-allow when a
non-allowlisted env var is set, when a redirect targets `/dev/tcp` or `/dev/udp`,
or when a `cd` and an `rm` appear in the same call.

### Why a broad `git:*` entry is the wrong shape

Of 6,836 calls containing a `git` segment, **5,187 — 75.9% — are compound**. A
`git:*` prefix entry would therefore run three quarters of all git work
completely unsandboxed, neighbours included. What rides alongside git in those
compounds, by frequency: `echo` (3,272), `head` (1,548), `cd` (1,396), `grep`
(820), `tail` (701), `ls` (571), `cat` (391), `rm` (232), `mkdir` (123), `bash`
(90). The `rm` and `bash` rows are the point — the entry cannot distinguish them
from the git segment that justified it.

The premise also over-reaches: roughly half of git traffic is unaffected by the
masks. History and tracked-content reads — `log` (2,383), `diff` (1,460), `show`
(618), `rev-parse` (294), `ls-tree` (77), `rev-list` (51) — never consult
untracked state and never take a lock. The affected half is `status` (2,401),
`commit` (901), `add` (781), `ls-files` (127), `checkout` (121), `stash` (69).
(About 1,400 calls use `git -C <path>` and have their subcommand hidden behind
the path operand, so these counts are approximate.)

### Listing and search commands mostly do not point at the root

The masks sit in the project root, `.claude/` and `.git/`. Most scanning traffic
points elsewhere, so a blanket `ls:*` / `find:*` / `grep:*` entry would unsandbox
thousands of calls to fix a few hundred:

| command | root-scoped (affected) | targeted elsewhere |
|---|---|---|
| `ls` | 114 cwd + 189 inside `.claude` | 1,060 absolute · 749 subdir · 621 named |
| `find` | 133 explicit `.` | 311 absolute · 71 named · 48 subdir |
| `grep` | 126 explicit `.` + 29 `.claude` | 2,970 named file · 876 subdir · 446 absolute |

The 4,024 `grep` calls classified "implicit cwd" are grep reading **stdin** from
a pipe, not scanning the filesystem — unaffected either way.

### Only hidden-inclusive enumeration is corrupted

Every one of the 22 masked names begins with a dot, which narrows the blast
radius sharply. Measured in this repo, sandboxed: plain `ls` shows **none** of
them, `ls -a` shows them; `rg --files` shows **none** (ripgrep skips hidden by
default); `grep -r` finds nothing in them (a `/dev/null` mask reads as immediate
EOF); `find` **does** list them.

Tallied over the same 45-day corpus, by whether the invocation can see dotfiles
at all:

| command | total segments | hidden-inclusive |
|---|---|---|
| `grep` | 8,626 | 1,595 (`-r`/`-R`, but harmless — masks read as empty) |
| `ls` | 2,941 | **891** (`-a`/`-A`) |
| `find` | 634 | **634** (always) |
| `rg` | 243 | **2** (`--hidden`) |
| `du` | 30 | 30 |
| `tree` | 8 | 8 |
| `head` · `tail` · `sed` · `cat` · `wc` · `cp` · `rm` · `sort` | 6,125 · 3,388 · 2,463 · 2,303 · 1,404 · 639 · 586 · 696 | 0 — all path-targeted |

`rg` is barely used (243 against grep's 8,626) and is immune by default, so it is
not worth a rule; it is also the cleanest workaround for anyone who wants one.

**Exclusion hit-rates**, i.e. how much of what an entry would unsandbox actually
needs it: `find:*` is **100%** (634/634), `du:*` and `tree:*` are 100% but
negligible, `ls:*` is **30%** (891/2,941), and `grep:*`/`rg:*` are near zero.
`find:*` is therefore the best-targeted entry available; `ls:*` is the judgement
call; grep and rg need nothing.

### The deny predicate: silent corruption, not failure

The distinction that makes the list small is whether the agent can *tell*. A
sandbox failure that raises an error is self-correcting — the agent sees it and
retries. Only silently wrong output needs blocking.

Silent, and worth denying:

- the `git status` family, `git ls-files --others`, `git add -A`/`.` — the masks
  appear as untracked paths, and `add` tries to stage character devices;
- `ls` / `find` / recursive `grep` **when scoped to the project root or
  `.claude/`** — not the targeted majority above;
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

### The permission pipeline, and what it costs to leave the sandbox

Decompiled 2026-08-16 from the same CC 2.1.233 bundle. Three findings; the first
two overturn verdicts recorded above.

**(1) A read-only command is auto-allowed ahead of the classifier, sandboxed or
not.** The bash evaluator ends with

```js
if (hp.isReadOnly(e) && !H_S(e,n) && !i.some(…))
  return {behavior:"allow", decisionReason:{type:"other", reason:whn}}
```

with `whn = "Read-only command is allowed"`. Nothing on that path consults
sandbox state — unlike `hUf` and `R_S`, the two sandbox shortcuts, which both
bail on `!TV(e)`. So `git log`, `git diff`, `git show`, `ls -a`, `find .` cost no
classifier call whether or not they run in the sandbox, and excluding them is
free on the cost axis.

`isReadOnly(e)` is `U2f(e, S3r(e.command)).behavior === "allow"`. `U2f`
tree-sitter-parses the command and requires **every** segment to pass a
flag-aware table — `git diff|log|show|shortlog|reflog|stash list|ls-remote|
status|blame|ls-files|config --get|remote show|remote|merge-base|rev-parse|
rev-list|describe|cat-file|for-each-ref|grep|stash show|worktree list|tag|
branch`, the `gh …` set, `docker logs|inspect` — plus a plain-command allowlist
(`cat head tail wc stat du df diff readlink pgrep …`) and regex forms, among them
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
  keyed on the global setting, so `dangerouslyDisableSandbox` does not exempt it;
- **`git -C`, `-c`, `--git-dir`, `--work-tree`** — `A4p` scans leading git global
  options and returns false outright on any member of
  `Omv = {-c, -C, --exec-path, --config-env, --git-dir, --work-tree, --bare,
  --attr-source, --help, -h, --shallow-file}`. Options outside that set
  (`--no-pager`) pass. The table key is built as `git <sub> <sub2>` with a
  fallback to `git <sub>`, which is how `git config --get` and `git stash list`
  resolve.

So the only cheap shape is a bare `git <subcommand>` from the original cwd, with
no `cd`, no `-C`, no subshell and no `$VAR`. Every mechanism for reaching a
subdirectory — `cd &&`, `(cd …)`, `git -C` — forfeits it.

**(2) Hook position: `updatedInput` alone defers, `permissionDecision` settles.**
PreToolUse hooks run before any permission evaluation. When a hook returns
`updatedInput` with no decision, `HRn` yields `{type:"hookUpdatedInput"}` and the
caller assigns `v = ae.updatedInput`, replacing the working input; `PDb` then
takes

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

**Corrected in the reasoning above.** The loud-versus-silent split used to pick
the deny set is the wrong axis; the question is whether the error leads to a
correct recovery. Three classes: *silently wrong* (the `git status` family,
`ls -a`, `find`, `ps`/`pgrep`, dropped `SessionStart` hooks); *misleadingly
wrong* (`index.lock` — the message names a concurrent git process that does not
exist, so the agent deletes a lockfile that is not there and then hunts for a
cause, which is worse than silence); *correctly diagnosable* (`Device or
resource busy` on `.git/config`, sibling-worktree `Read-only file system`,
zellij "no active session"). Only the third class is safe to leave sandboxed.
That puts `git add:*` and `git commit:*` in the exclusion set on their own
merits — `add` strands the lock, `commit` is where the misleading error
surfaces — and banning `git add -A`/`.` does not remove the need, since an
explicit pathspec strands it too. Also corrected: a classifier call is one model
call over cached context with no generation, so it is cheaper than an agent
turn; batching `cd <E> && git status` into one call beats splitting it, and the
cd+git rule is a cost to note rather than a shape to avoid.

**Open, both waiting on a corpus scrape (next session).**

1. `git:*` versus narrow entries. The narrow set has converged on `status`,
   `add`, `commit`, `ls-files` — most of the write half plus the noisy read — so
   `git:*` may be the honest answer. Against it: it unsandboxes ~6,836 calls, a
   third of all Bash traffic, and since 75.9% of git-bearing calls are compound
   it frees the neighbours too (`rm` 232, `bash` 90). The scrape settles whether
   protecting `log`/`diff`/`show` earns the extra entries.
2. How often `cd <dir> && …` is actually issued. This is load-bearing for the
   `cwd-safety` re-scope and is currently speculation.

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
