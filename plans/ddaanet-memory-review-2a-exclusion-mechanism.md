# ddaanet memory review — entry 2a · the exclusion mechanism

Part of [ddaanet memory review](ddaanet-memory-review.md). Entry 2 is
`sandbox-effects`; this part holds the rubric, change (a), and the decompiled
`excludedCommands` matcher. Continues in
[2b](ddaanet-memory-review-2b-exclusion-scope.md).

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

**Superseded by the exclusions taken in
[2c](ddaanet-memory-review-2c-deny-and-decisions.md).** `git:*`, `ls:*`,
`find:*` and `claude:*` discharge the paragraph's whole enumeration — every git
verb it lists, and `ls .claude/` — automatically and with no flag. What survives
is narrow: `cat`/`head` of a masked path, which returns empty because the mask
is `/dev/null`; and the standing permission itself, which still has work to do
wherever the matcher fails closed (a subshell, `$( … )`, `sh -c`, a quoted
argument, a double space).

That residue is no longer acted-inline. Pre-exclusions the paragraph fired while
*composing* a command, with no symptom to arrive on — the property that made it
wrong for a memory. Post-exclusions it fires only after a sandboxed command has
already returned something odd, which is a lookup with a symptom. So the
resolution is to **shrink it in place**, not to relocate it to `prohibitions`,
and the `prohibitions` feature request for it is withdrawn.

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
plain `grep` raises it. It also needs no hook, per the retry finding
under (a-bis) in [2c](ddaanet-memory-review-2c-deny-and-decisions.md).

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

**The mechanism, in one sentence.** The command string is parsed by
tree-sitter-bash into a list of simple commands; each one is expanded into a
closure of normalised variants; if any variant of any segment matches any list
entry, the **entire call** runs unsandboxed, including segments that match
nothing.

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

- recurse **only** into node types `program`, `list`, `pipeline` (the set
  `uWs`);
- skip the operator tokens `&&` `||` `|` `;` `&` `|&` newline (`npd`), and
  `comment`;
- for `redirected_statement`, recurse into children whose type does not end in
  `_redirect` — this is why a trailing redirection is invisible to the match and
  an interleaved one is not;
- **anything else** — subshell, `if`/`while`, function definition, command
  substitution — is pushed whole as `node.text`, a raw source slice.

Bail-outs return the entire string as one segment: empty input, a command longer
than `$Fe`, or a parse failure.

Two consequences. Every construct that is not a plain list or pipeline
**fails closed**: `( … )`, `$( … )`, `if …; fi` and `sh -c '…'` are pushed as
one blob that will not match, so they stay sandboxed. And because the segment is
`node.text`, the comparison sees source text, not re-rendered argv — which is
why double spaces and quotes defeat it.

**Normalise.** Each segment seeds a worklist expanded to a fixpoint; every
derived string is fed through both functions again, and *all* variants are match
candidates:

- `bHi(s, /^(LD_|DYLD_|PATH$)/)` — repeatedly strip leading `VAR=value`
  assignments, **stopping** at any name matching `LD_*`, `DYLD_*` or `PATH`.
- `q_e(s)` — drop comment lines, unquote the first token, and strip leading
  wrapper commands: `timeout [opts] N[smhd]`, `time`, `nice [-n N]`, `stdbuf
  -[ioe]X`, `nohup`, `command [-p]`, `builtin`, `noglob`. It also strips
  assignments, but only for names in an allowlist `F3n` (`GOOS`, `NODE_ENV`,
  `TZ`, `LANG`, `CI`, `ANTHROPIC_API_KEY`, …).

**Match — entries are permission-rule patterns, not plain strings.** `B4o`
parses each entry, and `xUf` applies it:

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
`permissions.deny`. The ledger's earlier instruction to probe only from a
session started after the settings change is unnecessary.

Two smaller notes. The read-deny discriminator the original probe table leaned
on does not exist — `ls -d /Users/david/.claude/ide/` **succeeded** sandboxed,
because `ls -d` only stats the path and the sandbox's read-deny does not cover
that; `${TMPDIR-UNSET}` carried the whole reading instead. And
`apply-seccomp: unshare(CLONE_NEWUSER): Invalid argument` hit one probe while
the byte-identical retry succeeded, confirming the retry-once-unchanged remedy
proposed for that entry.

The descendant question — how far an exclusion reaches — is moot under (b): the
exclusion already covers everything in the call, and no nesting construct is
matched into, so there is no narrower containment left to preserve.
