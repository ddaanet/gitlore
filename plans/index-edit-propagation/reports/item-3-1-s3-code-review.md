# Item 3.1, slice 3 — code review (GREEN phase)

Scope: `scripts/cc-hooks/session-start.sh`. `tests/cc_hook_session_start.bats`
read but never written. Nothing committed, no `just` recipe run, tree left dirty
and unstaged.

Verdict: **two fixes applied, both to the shipped comment-and-call site.** One is
a real defect this slice introduced — a bare drain in a hook whose contract is
that it always finishes — measured, fixed, and re-measured. The other is the
`plans/` citation. The fold's shape (placement, guard, both channels, blank-line
join) is otherwise correct and matches the committed precedent.

## Concern 1 — the bare drain could abort SessionStart. Defect, fixed.

`scripts/cc-hooks/session-start.sh:2` is `set -euo pipefail` — read, not assumed.
The submitted code called `gitlore_relay_drain "$mempath"` bare, as a simple
command in no condition context, so errexit was live inside the whole function
body.

**Measured, not reasoned.** A probe built the suite's own fixture
(`setup_tmp_repo` + `make_parent_with_memory`), staged a marker with
`gitlore_relay_write memory a1 …`, `chmod 0200` on it, and ran the hook:

```
=== rc=2
=== stdout: []
=== stderr tail:
awk: cannot open ".../gitlore-relay-a1" (Permission denied)
=== marker still present: yes
```

`find -maxdepth 1 -type f` matches a mode-0200 regular file; `_gitlore_relay_sysblock`'s
`awk` then exits 2 on the open failure; the command substitution's status becomes
the assignment's status; errexit kills the shell inside the function. The blast
radius is larger than a lost relay: **exit code 2 with empty stdout**. SessionStart
emits no JSON at all, so the session loses the standing commit-protocol
`additionalContext` (FR11), the launcher notice, the divergence and tier notices —
every notice accumulated above the fold — and CC reads exit 2 on a hook as a
blocking error. The marker is not removed either, so the same unreadable file
kills the next session too. Same call is benign in a PostToolBatch hook, which is
why the committed `index-compose.sh` fold is not affected; it is not benign here.

**Fix, on the caller's side only** (`scripts/lib/index-sync.sh` untouched):

```bash
gitlore_relay_drain "$mempath" || true
```

`|| true` puts the call in an AND-OR list, which suspends errexit for the call
*and* for the function body it enters, so the drain runs to completion: the
unreadable marker yields an empty block, gets framed, and is removed. That is the
same degrade-don't-abort trade `gitlore_relay_write` already documents for the
marker it cannot read. `|| true` over `relay_rc=$?` because nothing here has a use
for the status, and the file already carries `|| true` at `:154`.

Re-measured on the identical fixture after the fix:

```
=== rc=0
=== stdout: {"systemMessage":"gitlore: memory ready (detached at live).\n\n--- gitlore-relay agent a1 ---\n\n", ... full additionalContext ...}
=== marker still present: no
```

The hook finishes, every accumulated notice survives, and the user sees a framing
line around an empty body — a visible if terse signal that a relay was found and
could not be read.

**The fix is unpinned, and that is a finding for slice 4, not a silent addition.**
No frozen test creates an unreadable marker; mutation `ME` below (the `|| true`
removed) leaves both slice-3 cases green. Slice 4 owns the drain's `-type f`
hole and should pin the caller-side survival in the same case: assert the hook
exits 0 and its `additionalContext` still carries the commit-protocol text when a
mode-0200 marker is present. The residual after the fix — the staged report's
body is lost, only the framing line reaches the user — is also slice 4's to close;
it cannot be closed from this side without touching `index-sync.sh`.

## Concern 2 — `Item 3.1/D` citation. Fixed.

`(Item 3.1/D)` named `plans/index-edit-propagation/runbook.md`, a prospective
artifact that gets swept — the same class slice 1's and slice 2's reviews stripped
out of shipped source. Removed; the sentence stands without it. No replacement
citation was substituted: the comment makes no empirical claim needing one. The
`(measured under CC 2.1.261)` placeholder the committed helpers carry belongs to
the *subagent-channel-confinement* claim, which this comment does not make — that
claim is already cited at `gitlore_relay_marker_file` in `scripts/lib/index-sync.sh`,
where Item 4.1 will back-fill its `D<n>`.

The rest of the diff was swept for anything that will not survive: no other
`plans/`, `memory/`, runbook or slice reference in the added lines.

**Also fixed in the same pass, same rot class:** the comment cited the two early
exits by line number, `(:202, :207)`. Nothing else in this 400-line file cites a
line number, and the two would drift on any edit above them — silently, since a
stale line number still reads as authoritative. Replaced with the durable names:
"the diverged and ff-failure early exits above".

**Reported, not fixed — out of scope.** `tests/cc_hook_session_start.bats:353`
carries the same `(Item 3.1/D)` citation in case 1's comment. The test file is
frozen and reviewed; flagging it for whoever unfreezes it.

## Concern 3 — ordering. Correct, verified.

Nothing between the fold and `emit_session_json` but the emit comment; `grep` over
everything after the fold finds no further read of `sysmsg` or `protocol_ctx`.
`emit_session_json` reads both once, so the fold's two appends are the last
mutations and cannot be disturbed.

Composing before draining is right. `gitlore_compose`'s own report — a partial
write, a refusal, or the capped dangling-pointer notice — is about *this* store and
what the user must repair in it; the relayed block is a subagent's report about
work already done. Draining first would interleave a framed foreign block between
the compose notice's `systemMessage` and the matching `additionalContext` the
dangling branch pairs it with. Draining last keeps every locally-generated notice
contiguous and puts the relay at the end of both channels, which is also where
`index-compose.sh`'s fold puts it relative to that hook's own report.

## Concern 4 — `set -u`. Safe, verified.

`gitlore_relay_drain` sets `GITLORE_RELAY_SYSMSG=""` and `GITLORE_RELAY_CTX=""` as
the first two statements of its body, before the `rev-parse` that is its only
early `return`. With errexit now suspended for the call, the body always runs to
completion, so there is no path on which the guard reads either variable unset —
strictly safer than before the fix, where an abort mid-body was possible (though
an abort left nothing to read anyway).

The one remaining shape that would trip `set -u` is `gitlore_relay_drain` not
being defined, which `|| true` would swallow where the bare call reported it. It
is unreachable: `source "$PLUGIN_ROOT/scripts/lib/index-sync.sh"` at `:13` is bare
under `set -e`, so a load failure kills the hook 360 lines earlier. Left as a bare
`$GITLORE_RELAY_SYSMSG` rather than `${GITLORE_RELAY_SYSMSG:-}` for that reason,
and to match the committed `index-compose.sh` fold — a `:-` there would imply a
doubt the drain's contract does not support.

## Concern 5 — stdout discipline. Clean, verified.

Nothing the fold runs can reach fd 3. `gitlore_relay_drain` writes to stdout
nowhere: both `awk` readers are inside command substitutions, `find` is inside a
process substitution, `rm -f` and `sort` are silent. Doubly safe in any case —
`exec 3>&1 1>&2` at `:49` means fd 1 is already stderr by the time the fold runs,
so even an accidental `echo` would land on stderr rather than in the JSON channel.
The probe confirms it empirically: stdout held exactly one JSON object and the
`awk` permission error was on stderr.

A drain diagnostic on stderr is harmless here, and in fact is the only place it
could go — SessionStart's stderr is invisible to the user outside `--verbose`
(the file says so at `:30-34`), which is precisely why the framing-around-empty-body
on the user channel matters as the visible signal.

## Concern 6 — style. Conforms.

- Comment density matches the surrounding notices, which run 6-14 comment lines
  per code block in this file; the fold's three paragraphs are in range for a
  block carrying a design call, a portability trade and a maintenance warning.
- Citation idiom now matches: `D14`, `D17`, `FR11`, `(measured under CC 2.1.261)`
  are the file's vocabulary; nothing under `plans/` or `memory/` is referenced.
- "Entry points first, definitions after their users": the fold defines nothing
  and introduces no constant. It sits at the point of use, immediately before the
  emit that consumes what it appends.
- The `protocol_ctx` blank-line join matches all four other appends to that
  variable in this file (`:91`, `:276`, `:352`, `:372`).
- `shellcheck -s bash` and `scripts/lint-shell.sh` both clean.

## Mutation round

Each mutation was written **in place** into `scripts/cc-hooks/session-start.sh`
from a saved pristine copy, run, and the file restored — the test file was never
edited or relocated. Case 1 = `session-start drains a stranded relay marker`,
case 2 = `session-start with no marker emits no relay framing`. Line numbers are
in `tests/cc_hook_session_start.bats`.

| # | Mutation | Case 1 | Case 2 | First red |
|---|---|---|---|---|
| M0 | the implementation as it now stands | pass | pass | — (must be green) |
| M1a | no `-n` guard: unconditional `add_sysmsg` + ctx join | pass | pass | nothing — Finding 1 |
| M1b | framing synthesized unconditionally, both channels | pass | red | `:397` `[[ "$sysmsg" != *"$RELAY_FRAMING"* ]]` |
| M2 | appends to `sysmsg`, not `protocol_ctx` | red | pass | `:375` `[[ "$ctx" == *"STRANDED CTX BODY"* ]]` |
| M3 | appends to `protocol_ctx`, not `sysmsg` | red | pass | `:373` `[[ "$sysmsg" == *"STRANDED SYSMSG BODY"* ]]` |
| M4 | correct fold moved **after** `emit_session_json` | red | pass | `:373` sysmsg body |
| M5 | folds both channels but the marker is put back | red | pass | `:377` `[ ! -f "$marker" ]` |
| M6 | appends to `tier_guidance`, already consumed | red | pass | `:373` sysmsg body |
| M8 | fold nested inside `[ -n "$sysmsg" ]` | pass | pass | nothing — Finding 2 |
| M9 | strips the framing line from `sysmsg` | red | pass | `:374` `[[ "$sysmsg" == *"$RELAY_FRAMING a1 ---"* ]]` |
| M10 | framing line only, empty body on both channels | red | pass | `:373` sysmsg body |
| M11 | strips the framing line from `ctx` | red | pass | `:376` `[[ "$ctx" == *"$RELAY_FRAMING a1 ---"* ]]` |
| M12 | unconditional framing, `ctx` only | red | red | `:373` / `:398` |
| M13 | `sysmsg=""` after the fold, so `systemMessage` is omitted | red | red | `:373` / `:395` `[ "$sysmsg" != "null" ]` |
| M14 | `emit_session_json` emits no `additionalContext` key | red | red | `:375` / `:396` `[ "$ctx" != "null" ]` |
| **MA** | **fold hoisted above the `gitlore_memory_dirty` block, so it precedes both early exits** | **pass** | **pass** | **nothing — Finding 3** |
| **MB** | **`protocol_ctx` append joined with a single newline, not a blank line** | **pass** | **pass** | **nothing — Finding 4** |
| **MC** | **channel swap: `add_sysmsg "$GITLORE_RELAY_CTX"`, ctx append takes `$GITLORE_RELAY_SYSMSG`** | **red** | **pass** | **`:373` sysmsg body** |
| **MD** | **guard changed to `[ -n "$GITLORE_RELAY_CTX" ]`** | **pass** | **pass** | **nothing — Finding 5** |
| **ME** | **the `|| true` removed — a bare drain under this file's `set -e`** | **pass** | **pass** | **nothing — Finding 1 of concern 1** |

M0 through M14 reproduce the test-review's table exactly, with one correction:
M14 reds case 1 at `:375`, not `:373`. Dropping only the `additionalContext` key
leaves `systemMessage` intact, so case 1 survives both sysmsg assertions and dies
on the first ctx one. It does not change M14's coverage claim — `:396` is still
the assertion it proves non-vacuous.

### What the new mutations establish

**MA — the tests do not catch the hoist. Stated plainly, no coverage implied.**
Both slice-3 cases pass under MA, and so does the *whole* 23-test
`cc_hook_session_start.bats` file — measured, 23 passed, 0 failed. Neither
slice-3 case reaches the diverged or ff-failure paths, and no other case in the
file stages a marker, so nothing anywhere in the suite distinguishes the chosen
placement from the hoisted one. That is a coverage gap and not a defect: both
early exits do call `emit_session_json`, so MA would still *emit* the relay — the
behavioural difference is only that a subagent's report would interleave with a
divergence notice the user is trying to act on, and that the marker would be
consumed on a session the user must restart anyway. The runbook's placement is
the deliberate call and the comment states it; the point here is that the tests
are not the thing holding it in place, so a future edit could move it silently.

**MB — the blank-line join is unpinned.** Formatting only: the ctx body would
open on the line immediately after the tier-guidance block instead of after a
blank line. The implementation matches all four other `protocol_ctx` appends in
the file, so it is right; nothing tests it, and pinning it would mean asserting
message formatting, which this slice does not do.

**MC — the channel swap is caught**, at case 1's first content assertion. The two
fixture bodies are distinct strings, which is what makes the swap visible; this
is the assertion pair doing exactly the job the test review claimed.

**MD — behaviour-identical, correctly unpinned.** `gitlore_relay_drain` frames
*both* channels for every marker it finds, appending a framing line to each on
every iteration, so `GITLORE_RELAY_CTX` is non-empty exactly when
`GITLORE_RELAY_SYSMSG` is. Guarding on either is the same program. Not a defect
and not worth a test; `GITLORE_RELAY_SYSMSG` is the better choice only because it
matches the committed `index-compose.sh` fold.

**ME — the concern-1 fix is unpinned.** See concern 1 above; slice 4's finding.

## Findings

1. **The `|| true` that keeps SessionStart alive on an unreadable marker is not
   pinned by any frozen test (ME).** Explicitly reported rather than added
   silently. Slice 4, which owns the drain's `-type f` hole, should assert
   hook exit 0 and an intact `additionalContext` against a mode-0200 marker. The
   residual it leaves — body lost, framing line only — is closable only in
   `scripts/lib/index-sync.sh`, which is out of scope here.
2. **A fold nested inside `[ -n "$sysmsg" ]` is still indistinguishable from
   correct (M8).** Unchanged from the test review; the comment at the fold site
   is the whole defence, and it is present.
3. **Fold placement relative to the two early exits is untested by the entire
   suite (MA).** Coverage gap, not a defect. Whether to pin it is slice 4's or a
   later item's call; a case would have to stage a marker on a diverged store and
   assert the marker survives.
4. **The blank-line join on the ctx append is unpinned (MB).** Formatting;
   correct as written, matching the file's four other appends.
5. **The guard channel is a free choice (MD).** Behaviour-identical either way
   given the drain's contract; no action.
6. **`tests/cc_hook_session_start.bats:353` cites `(Item 3.1/D)`** — the same
   `plans/` reference stripped from the source here. Frozen file, reported only.

## Checks that passed, by name

- Probe: mode-0200 marker + full hook run, **before** the fix — rc 2, empty
  stdout, marker left on disk. The defect reproduced.
- Probe: same fixture, **after** the fix — rc 0, complete JSON on fd 3 with every
  accumulated notice, marker removed. The fix verified.
- Mutation matrix — 20 mutations run in place against the frozen tests, SUT
  restored from a saved pristine copy after each; full table above.
- Full-suite run under MA — `bats tests/cc_hook_session_start.bats`, 23 passed,
  0 failed, establishing the hoist is caught by nothing in the file.
- `scripts/run-bats.sh tests/cc_hook_session_start.bats` — 23 passed, 0 failed.
- `scripts/run-bats.sh tests/cc_hook_worktree_remove.bats tests/merge_memory.bats tests/push_rejection_discriminator.bats tests/tier_discovery.bats tests/tier_divergence.bats`
  — 81 passed, 0 failed.
- `shellcheck -s bash scripts/cc-hooks/session-start.sh` — clean.
- `scripts/lint-shell.sh` — 137 files clean.
- SUT restored before the final runs, proven: `git diff --stat --
  scripts/cc-hooks/session-start.sh` is the slice's own 33-line addition and
  nothing else, and its sha matches the pristine copy taken before the first
  mutation (`70729b745544e9008c09228128a704a4a24c2957`).
- `git status --porcelain` — `scripts/cc-hooks/session-start.sh` and
  `tests/cc_hook_session_start.bats` modified (the latter by RED, untouched
  here), plus the untracked slice reports. Nothing staged, nothing committed.
- All measurement scratch removed from `$TMPDIR`; no `just` recipe run, no
  background task awaited.
