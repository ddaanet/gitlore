# ddaanet memory review — entry 2b · what an exclusion covers and costs

Part of [ddaanet memory review](ddaanet-memory-review.md), continuing [2a](ddaanet-memory-review-2a-exclusion-mechanism.md). What the sandbox actually breaks, what the corpus says it touches, and which entries are the wrong shape. Continues in [2c](ddaanet-memory-review-2c-deny-and-decisions.md).

### Excluding `git` outright, or read subcommands only

**Overturned — see "The permission pipeline" in
[2c](ddaanet-memory-review-2c-deny-and-decisions.md).** The verdict recorded here
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
it, see "The permission pipeline" in
[2c](ddaanet-memory-review-2c-deny-and-decisions.md): a read-only command is
auto-allowed
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
