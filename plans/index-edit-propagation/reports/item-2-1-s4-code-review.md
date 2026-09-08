# Item 2.1 slice 4 — code review

Scope reviewed: the GREEN commit `e26a7ef` — `scripts/cc-hooks/index-compose.sh`
(the payload capture at `:23` and the keyed resolution at `:31-38`) and
`scripts/cc-hooks/add-tier-batch.sh` (the drain at `:38`, the `agent_id` read,
the keyed `rm -f` at `:79`) — plus every pre-existing comment in both files that
the change could falsify. Read-only for judgement: `scripts/lib/index-sync.sh`,
`scripts/cc-hooks/index-sync-pre.sh`, `index-sync-post.sh`, `hooks/hooks.json`,
`tests/cc_hook_index_compose.bats`, `tests/cc_hook_add_tier.bats`,
`tests/helpers/setup.bash`, `tests/helpers/fixtures.bash`, the runbook's Item
2.1 (slice 4 at `runbook.md:648`), this slice's RED / test-review / GREEN
reports, slices 1-3's code reviews, `docs/references/index-authoring-sync.md`,
`docs/references/tiered-memory.md`, `CLAUDE.md` and
`memory/ddaanet/shared-claude.md`.

**Three major, two minor. All five fixed.** No critical. The keying itself — the
two lines the slice exists for — is correct as written and was not touched. The
findings are all in what the payload capture brought with it: a comment the
runbook explicitly named and GREEN missed, and an abort path the discarded
payload could not have.

## Verdict — the keying itself

Correct and complete in both files. Every site that resolves, reads or removes a
compose stamp goes through one keyed expression:

| site | what it does | keyed? |
| --- | --- | --- |
| `index-compose.sh:45` `gitlore_compose_stamp_file "$mempath" "$agent_id"` | the file's only resolution of the name | yes, this commit |
| `index-compose.sh:46` `[ -f "$stamp" ] \|\| exit 0` | the baseline-present gate | yes, via `$stamp` |
| `index-compose.sh:55` `gitlore_compose_stamp_get "$key" < "$stamp"` | the pre-batch read, once per key | yes |
| `index-compose.sh:63` `rm -f "$stamp"` | the drop at batch end | yes |
| `add-tier-batch.sh:89` `rm -f "$(gitlore_compose_stamp_file "$mempath" "$agent_id")"` | the only stamp site in the file | yes, this commit |

`grep -n 'stamp\|compose_stamp\|gitlore-compose' scripts/cc-hooks/index-compose.sh scripts/cc-hooks/add-tier-batch.sh`
returns exactly those plus prose mentions; no literal stamp path fragment
appears in either file. Repo-wide,
`grep -rn 'gitlore-compose-stamp\|gitlore-index-preimage'` over `scripts/`,
`hooks/`, `docs/` and `tests/` finds the two literals only in
`scripts/lib/index-sync.sh:98,108` (inside the helpers) and in
`tests/index_sync.bats`, which builds the expected names itself. Nothing else in
the plugin hard-codes either path, so no consumer was missed.

`index-compose.sh` has no early exit gated on `agent_id` — a subagent's hook
proceeds identically and differs only in the name it resolves (the M4 shape the
test review measured). The M3 shape (key the lookup, leave `rm -f` bare) cannot
occur in either file: both hold exactly one expression, read by the guard and
the removal alike.

`// empty` with no `agent_type` fallback, matching `index-sync-pre.sh:40` and
`index-sync-post.sh:23` byte for byte, and nothing separates empty from absent —
`_gitlore_agent_suffix` short-circuits on an empty `$1`. Driven, not read: a
payload with `agent_type` and no `agent_id` resolves the unsuffixed name in both
hooks (probe §1-2 and the 28 suite cases, every one of which carries the decoy).

## Major 1 — `add-tier-batch.sh:20` still said the payload is unused

**Applied.** `scripts/cc-hooks/add-tier-batch.sh:20-22`. The header comment as
committed:

```sh
# The intent file IS the signal, so the batch payload is unused.
```

The payload is now read, six lines further down. The runbook named this sentence
by line and by quotation (`runbook.md:562-564`: "Its header comment at line 20 —
'The intent file IS the signal, so the batch payload is unused' — becomes false
with that read and takes the same qualifier as index-compose.sh's"), the test
review flagged it again for GREEN, and GREEN changed `index-compose.sh:23` but
not this one.

The failure it produces is the one slice 3's Major was about: a header block is
where a maintainer looks to learn what the hook depends on, and this one states
the opposite of the truth. Someone widening the hook — or deleting the "unused"
drain as dead weight — reads it as a licence.

Replaced with the qualifier the runbook prescribes:

```sh
# The intent file IS the signal; nothing in the batch payload triggers this
# hook. The payload is read for one field, agent_id, and only to key the
# compose baseline this hook drops below.
```

## Major 2 — a malformed payload aborts both hooks, where the discarded one could not

**Applied.** `scripts/cc-hooks/index-compose.sh:44` and
`scripts/cc-hooks/add-tier-batch.sh:66`, both now
`agent_id=$(jq -r '.agent_id // empty' <<<"$payload") || agent_id=""`.

`jq` exits 5 on an unparseable payload, and under `set -euo pipefail` an
assignment from a failing command substitution ends the script. Both hooks
previously discarded the payload entirely, so no shape of it could stop them.
Measured end to end against `HEAD`'s files (built from
`git show HEAD:scripts/cc-hooks/…`, so the tree was never mutated), in the
suite's own `make_parent_with_memory` fixture:

```
=== HEAD's index-compose.sh, malformed payload ===
  rc=5  stderr=[jq: parse error: Invalid numeric literal at line 1, column 4]
  bare stamp STRANDED (hook aborted before rm)
=== HEAD's add-tier-batch.sh, no intent, malformed payload ===
  rc=5  stderr=[jq: parse error: Invalid numeric literal at line 1, column 4]
=== HEAD's add-tier-batch.sh, intent present, malformed payload ===
  rc=5  stdout=[]
  intent NOT consumed — the mount never ran
```

Both failures are worse than a missed read:

- The stranded compose stamp is exactly the M3 damage the test review measured.
  `index-sync-pre.sh:59`'s `if [ ! -f "$stamp" ]` declines to re-stamp when a
  file is already there, so the surviving stamp becomes the baseline for that
  agent's *next* batch and the compose runs against an ancient index.
- The mount is a one-shot, user-initiated action. Aborting at `:42` (before the
  intent gate — see Major 3) means it never runs, and since a malformed payload
  is not a transient condition, the retry on the next batch fails identically.

The exit is also invisible where it matters: a non-zero exit discards the hook's
stdout JSON (D14), so there is no `systemMessage` to say a mount was skipped.
Only the debug log gets jq's line.

`|| agent_id=""` degrades to the unsuffixed name — the name both hooks resolved
before they read the field at all — which is a keying loss, not a data loss, and
strictly no worse than the pre-slice-4 behaviour. jq's diagnostic still reaches
stderr, so the failure is not swallowed. Same probe against the fixed tree:

```
=== 1. main thread baseline, then compose hook fed MALFORMED payload ===
  rc=0   stderr: jq: parse error: Invalid numeric literal at line 1, column 4
  bare stamp consumed
=== 2. truncated payload ('{"agent_id":"a1"') ===
  rc=0   bare stamp consumed (fell back to unsuffixed)
=== 4. add-tier-batch: malformed payload with an intent present ===
  rc=0   emitted JSON: yes   intent consumed
=== 5. add-tier-batch: no intent + malformed payload ===
  rc=0   stderr=[]  stdout=[]
```

The truncation case (§2) is the realistic trigger: a hook whose writer dies
mid-write gets a prefix of valid JSON, not garbage.

**Not extended to the two sync hooks, and that is not an inconsistency.**
`index-sync-pre.sh:19` reads `.tool_name` and `index-sync-post.sh:22` reads
`.session_id` *before* their `agent_id` read, so a malformed payload already
aborts them one or more lines earlier; guarding the later read there would
change nothing. More to the point, those two hooks cannot decide anything
without parsing the payload — `index-sync-pre.sh` gates its whole body on
`tool_name` — whereas these two do their work from a file on disk and read the
payload for one optional field. The asymmetry tracks that difference.

## Major 3 — `add-tier-batch.sh` read `agent_id` ahead of every early exit

**Applied.** The read moved from `:42` (immediately after the drain) to `:66`,
below `[ -f "$intent" ] || exit 0`.

As committed, the read sat above `gitlore_cd_project_root`,
`gitlore_has_submodule`, the `[ -e "$mempath/.git" ]` guard and the intent gate.
This hook is registered unconditionally on `PostToolBatch`
(`hooks/hooks.json:90`) and fires on every batch of every session in every repo,
gitlore-configured or not; the overwhelming majority exit at one of those four
guards. Two consequences, both removed by the move:

- Major 2's abort fired on **every** batch, in repos that have no memory
  submodule at all — the widest possible blast radius for a defect whose payoff
  is one field used on the rare mount path.
- Every batch paid a `jq` process and a here-string temp file for a value all
  but a handful of runs discard. `index-compose.sh` already placed its read
  after its own early exits; this brings the two into the same shape.

Verified silent and clean on the common path after the move (probe §5: `rc=0`,
empty stdout, empty stderr with a malformed payload and no intent file), and the
mount path still reaches the read (probe §4, and the 13 cases in
`tests/cc_hook_add_tier.bats`).

## Minor 1 — `index-compose.sh:23`'s inline comment contradicted itself

**Applied.** As committed:

```sh
payload=$(cat)   # the contents are still drained, not acted on; only agent_id below steers us
```

`agent_id` *is* the contents, so the clause denies what the rest of the same
sentence asserts. The runbook asked for a qualifier saying "the stamp and not
the payload's contents is the signal stays true of the *trigger*" — the
distinction is trigger versus field, not drained versus read. Now:

```sh
payload=$(cat)   # the stamp is the trigger; the payload is read below for agent_id alone
```

## Minor 2 — the new rationale comments cited a file that carries no rationale

**Applied**, `scripts/cc-hooks/index-compose.sh:35-36` and
`add-tier-batch.sh:56-59`. As committed, `index-compose.sh` ended its
`agent_id`-never-`agent_type` paragraph with "Same contract
index-sync-pre.sh/-post.sh already settled", and `add-tier-batch.sh` with "same
contract as index-compose.sh and the sync hooks".

`index-sync-pre.sh` states no such contract.
`grep -n 'agent_type' scripts/cc-hooks/index-sync-pre.sh` returns nothing —
slice 2's code review deliberately kept the reason in its report rather than the
hook, and slice 3's code review then raised exactly this as its own Major ("a
pointer that reads as a citation and resolves to nothing is a claim made from
the hub rather than the node") and repointed its own comment. The pattern
recurred in this slice, in the half of each pointer naming the pre-hook.

Repointed at what actually resolves, and at the test that pins it — the same
remedy shape slice 3 used, and the reason slice 3 gave for citing a test rather
than a `memory/` node (a tier file arrives through a submodule gitlink and is
not part of what the plugin distributes; the sole in-`scripts/` precedent,
`scripts/lib/util.sh:442`, cites `docs/design.md`):

- `index-compose.sh` → "The contract index-sync-post.sh states at length; pinned
  here by the agent_type decoy every payload in
  `tests/cc_hook_index_compose.bats` carries." Both halves verified:
  `index-sync-post.sh:31-37` carries the full paragraph, and the test review's
  M2 measured seven cases in that file turning red on the fallback.
- `add-tier-batch.sh` → "the contract index-compose.sh states at length … Pinned
  by the main-thread case in `tests/cc_hook_add_tier.bats`, the only one there
  that can see the decoy." M2 measured exactly one red in that file.

## Whitespace and hostile input — run, not read

A spaced gitdir and a hostile agent id driven end to end through both hooks in
the suite's own fixture, with `agent_id='a 1/../../x y'`:

```
  resolved: […/.git/modules/gitlore-memory/gitlore-compose-stamp-a_1_______x_y]
  inside gitdir: yes
  keyed stamp created: yes
  rc=0  stderr: (empty)
  keyed stamp consumed
  strays outside gitdir under TMP_REPO: (none)
```

`find "$TMP_REPO" -name 'gitlore-compose-stamp*' -not -path "$gd/*"` is empty,
so neither the resolution nor the `rm -f` escaped the memory gitdir. Both hooks
pass `"$agent_id"` quoted into the helper and both wrap the result in `"$( )"`,
so a spaced result stays one argument; the sanitisation itself is
`_gitlore_agent_suffix`'s and is pinned by slice 1's boundary case.

Independently, both suites under `TMPDIR="/tmp/claude-1000/space dir"` — the
fixture repo, and therefore the memory gitdir, sits under a path with a space —
**28 passed, 0 failed**, identical to the normal run.

## Assessed, no defect

- **`payload=$(cat)` versus `payload=$(cat || true)`.** The difference is
  inherited, not introduced: `add-tier-batch.sh` drained with
  `cat >/dev/null || true` before this commit and `index-compose.sh` with a bare
  `cat`, and the runbook prescribes preserving each. It is also inert. `cat`
  returns 0 at ordinary EOF; it fails only on a read error, which for a hook
  means a broken stdin, and in that case `payload` is empty either way — `jq` on
  empty input exits 0 with no output, so both spellings yield the unsuffixed
  name. Probed: empty stdin → `agent_id=[]`, rc 0.
- **Command substitution strips trailing newlines.** Irrelevant to a JSON
  document; jq does not care, and `.agent_id` is unaffected.
- **`$(cat)` on binary input.** A NUL byte is dropped by bash inside command
  substitution, which would corrupt the payload — but JSON cannot carry a raw
  NUL (control characters are escaped, a NUL as a six-character sequence), so a
  payload containing one is already malformed, and Major 2's guard now catches
  that case instead of aborting.
- **A very large payload.** `index-compose.sh` now holds the whole batch payload
  — including every `tool_input` — in a shell variable and writes it to a
  here-string temp file, where it previously streamed to `/dev/null`. This is
  the established shape: `index-sync-pre.sh:18` does the same on every `Write`,
  `Edit` and `Bash` call, i.e. more often than per batch. Not worth deviating
  from the runbook's prescribed form (`payload=$(cat)` then a separate jq) to
  save one copy in a third hook, and reading stdin straight into `jq` would
  trade it for a partial drain on a parse error.
- **`add-tier-batch.sh:76-88`, the `rm -f` rationale block.** Checked
  explicitly: it argues that either hook ordering composes exactly once and that
  genuine concurrency is idempotent. Every clause stays true under keying,
  because both hooks now resolve the *same* keyed name for the same batch — the
  argument was never about which name, only about which order.
- **`index-compose.sh:18-22`, the "keyed on the pre-batch stamp" block.** Still
  true: the trigger is the stamp, and `agent_id` selects which stamp, not
  whether there is one.
- **Empty versus absent `agent_id`.** Neither hook branches on `$agent_id`; both
  pass it straight through. `{"agent_id":null}`, `{"agent_id":""}`, `{}` and
  `{"agent_type":"gp"}` all yield the unsuffixed name (probed at the construct,
  and pinned at the consumer by `tests/cc_hook_add_tier.bats:155`).

## Findings deliberately not fixed

- **The rationale duplication, and whether it should move to
  `scripts/lib/index-sync.sh`.** Slice 3's code review predicted this slice as
  the moment to move the `agent_id`-never-`agent_type` paragraph to the headers
  of `gitlore_index_preimage_file` / `gitlore_compose_stamp_file` with the
  consumers pointing there. **Assessed and declined**, for three reasons. (1)
  The helpers never see a payload — they take a string. A comment on
  `gitlore_compose_stamp_file` telling its callers which JSON field to read is
  the helper documenting its callers, which inverts the dependency and is the
  kind of hub-level claim `CLAUDE.md` rules out. (2) The three copies are not
  the same paragraph: each states the same premise and a *different* consequence
  (post: a parent looks for a name only a subagent writes; compose: a parent's
  stamp is keyed under the parent's own id and stranded; add-tier: the wrong
  agent's baseline is dropped). The premise is one sentence; consolidating it
  would leave the consequences in place and buy about three lines. (3) The
  remedy it was proposed against is a pointer that does not resolve, and Minor 2
  fixes that directly and more cheaply. Recorded here so the Phase 2 checkpoint
  can overrule it knowing the argument, rather than finding it undone.
- **`docs/references/index-authoring-sync.md:52`** — "the post-hook drops the
  stash at every batch end … so a pre-image can never become a *second* batch's
  baseline" is now over-general in the same way slice 3's code review found the
  in-code sentence to be: under keying it is a second batch *of the same agent*,
  and a dead subagent's pre-image is consumed by nothing. `tiered-memory.md:154`
  ("drops the compose stamp so the same manifest change is not reported twice in
  one batch") was checked too and stays true. **Flagged, not fixed**: Item 2.1's
  runbook entry assigns no `docs/` work, the whole of Phase 2 changes the same
  paragraph, and a `docs/` edit needs `just format-docs` — the first step of the
  gate this dispatch forbids running. **For the Phase 2 checkpoint.**
- **A subagent's hook output never reaches the parent.** Both hooks reviewed
  here emit `systemMessage` and `additionalContext` that are confined to the
  subagent — so a subagent's compose now runs (correctly) and reports into a
  void. **Belongs to Item 3.1**, whose relay marker is the mechanism; slice 3's
  review flagged the same thing for the budget nudge.
- **The GREEN and RED reports quote comment text this review changed.**
  `item-2-1-s4-green.md:9,34` quote `index-compose.sh:23` and
  `add-tier-batch.sh:38-39` as committed. Reports are records of their phase,
  not living documents; flagged the way slices 3 and 4 flagged the same drift.
- **Pre-existing: a deleted `MEMORY.md` strands the stamp.**
  `index-compose.sh:30`'s `[ -e "$index" ] || exit 0` returns before the stamp
  is resolved, so a stamp survives the index being removed. Unchanged in shape
  by this commit and outside Item 2.1 — the same hazard slice 3 recorded for the
  pre-image.

## Item 2.1 as a whole

**The four consumers are consistent where the item requires it.** All four
resolve the keyed name through the same helper with the same argument, read the
same field with the same expression, and quote it identically:

| consumer | reads | resolves | drops |
| --- | --- | --- | --- |
| `index-sync-pre.sh:40-42` | `.agent_id // empty` | pre-image **and** stamp, keyed | writes both, gated per key |
| `index-sync-post.sh:23,38` | `.agent_id // empty` | pre-image, keyed | `rm -f "$stashfile"` on both paths |
| `index-compose.sh:44-46` | `.agent_id // empty` | stamp, keyed | `rm -f "$stamp"` |
| `add-tier-batch.sh:66,89` | `.agent_id // empty` | stamp, keyed | `rm -f "$( … )"` |

No consumer has an `agent_type` fallback; none branches on whether `agent_id` is
empty; none holds a literal path fragment. The writer (`index-sync-pre.sh`) and
all three readers therefore agree on the name for every agent, which is the
invariant `index-sync-pre.sh:44-52` asserts and the whole item exists to
establish.
`grep -rn 'gitlore_index_preimage_file\|gitlore_compose_stamp_file' scripts/`
returns eight lines: the two definitions, one cross-reference inside a helper
comment, and exactly these five call sites.

Two deliberate differences remain, both recorded above: the two sync hooks abort
on a malformed payload (they cannot function without parsing it, and they abort
at an earlier read regardless) while these two degrade to the unsuffixed name;
and `index-sync-pre.sh` alone carries no `agent_type` rationale in the file, the
other three pointing at `index-sync-post.sh` or at each other.

**For the Phase 2 checkpoint:**

1. `docs/references/index-authoring-sync.md:52` needs the same narrowing slice 3
   applied in code, and no `docs/` update has accompanied Phase 2 so far. It is
   the one place the plugin's shipped documentation still describes the unkeyed
   invariant.
2. The keying makes a subagent's compose and sync *run*, which makes Item 3.1's
   report relay load-bearing rather than cosmetic: as of this item a subagent's
   memory edit propagates correctly and says so to nobody.
3. The stranded-file residual is bounded in comments (`index-sync-pre.sh:54-58`)
   and not swept: one pre-image and one stamp per subagent that dies mid-batch.
   Nothing added in Phase 2 cleans the gitdir, and `session-start.sh` does not
   touch these names — worth a decision at the checkpoint if Item 3.1 adds a
   sixth marker with the same lifecycle.
4. `gitlore_index_preimage_file`'s stamp and pre-image are keyed but the budget
   nudge marker (`gitlore_index_budget_nudge_file`, session-keyed) is not
   agent-keyed. That is deliberate and Item 3.1's, per slice 3's review; noting
   it so the checkpoint does not read it as an omission.

## Checks that passed, by name

- `scripts/run-bats.sh tests/cc_hook_index_compose.bats tests/cc_hook_add_tier.bats tests/index_sync.bats`
  on the untouched commit — **99 passed, 0 failed** (28 + 71, the figure the
  dispatch predicted).
- The same after the five fixes — **99 passed, 0 failed**, and again after the
  comment rewording pass.
- `just lint` — `lint-shell: 137 files clean`, exit 0, before and after; same
  count as slices 1-3, so nothing was added or left behind.
- `TMPDIR="/tmp/claude-1000/space dir" scripts/run-bats.sh tests/cc_hook_index_compose.bats tests/cc_hook_add_tier.bats`
  — **28 passed, 0 failed**, with the wrapper log landing inside the spaced
  directory, which is what proves the spaced `TMPDIR` reached `setup_tmp_repo`'s
  `mktemp -d`.
- End-to-end probe against **`HEAD`'s** two hooks, extracted with `git show` so
  the tree was never mutated — rc 5 on a malformed payload in three positions,
  stamp stranded, mount skipped and intent not consumed. Output quoted under
  Major 2.
- The same probe against the fixed tree — rc 0 in all five positions, stamp
  consumed, mount run and JSON emitted, jq's diagnostic still on stderr.
- Hostile-agent-id probe (`a 1/../../x y`) driving `index-sync-pre.sh` then
  `index-compose.sh` — resolved name inside the memory gitdir, keyed stamp
  created and consumed, `find` for strays outside the gitdir empty.
- jq behaviour matrix under `set -euo pipefail` — empty stdin, `null`,
  `{"agent_id":null}`, `[]`, `"x"`, truncated object, garbage: the first three
  yield the unsuffixed name at rc 0; the last four exit 5 unguarded and rc 0
  guarded.
- `grep -n 'stamp\|compose_stamp\|gitlore-compose'` over both changed files —
  every hit accounted for in the site table; no literal path fragment.
- `grep -rn 'gitlore_index_preimage_file\|gitlore_compose_stamp_file' scripts/`
  — eight lines: two definitions, one comment cross-reference, five call sites,
  all keyed.
- `grep -rn 'gitlore-compose-stamp\|gitlore-index-preimage'` across `scripts/`,
  `hooks/`, `docs/`, `tests/` — no shipped consumer hard-codes either name
  outside the helpers.
- `grep -n 'agent_type' scripts/cc-hooks/index-sync-pre.sh` — empty, the
  evidence for Minor 2.
- `git status --porcelain -- scripts/ tests/ docs/` — the two hook files
  modified, nothing else; no untracked path under `scripts/` or `tests/`.

## Files touched

- `scripts/cc-hooks/index-compose.sh` — the inline comment at `:23`, the
  `agent_id` rationale and non-fatal read at `:32-44`.
- `scripts/cc-hooks/add-tier-batch.sh` — the header comment at `:20-22`, the
  `agent_id` read moved from `:42` to `:66` and made non-fatal.
- `plans/index-edit-propagation/reports/item-2-1-s4-code-review.md` — this
  report.

Nothing staged, nothing committed; the tree is left dirty and unstaged. Neither
production file was mutated for discrimination — the pre-fix behaviour was
measured against copies extracted with `git show HEAD:…` into `$BATS_RUN_TMPDIR`
— so no restore was needed and `git status --porcelain -- scripts/` shows only
the two intended modifications. The probe drivers live under
`/tmp/claude-1000/`, never under `tests/` or `scripts/`.

## Gate note

`scripts/` is a `precommit_inputs` gated input, so these edits invalidate the
sentinels under `.git/gitlore/gates/`. Per the dispatch, `just precommit`,
`just test-unit` and `just test-integration` were **not** run; the orchestrating
session owns the full gate and the commit.
