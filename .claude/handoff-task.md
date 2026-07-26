## Current task

Finish the gate rework. The first pass landed on a **false premise** and David
corrected four things at once; the corrections are the task.

### The premise that was wrong

The strange dotfiles (`.bash_profile`, `.bashrc`, `.zshrc`, `.idea`, …) that made
`git add -A` die with `can only add regular files, symbolic links or
git-directories` were **real local files in the working tree**, not a sandbox
artifact. David removed them with `git clean -f`. Every claim built on
"the sandbox surfaces phantom dotfiles" is therefore wrong and must go — David:
"remove any reference to those files."

That claim was inherited from a memory written last session and never checked
against its source. It is now load-bearing in five places:

- `memory/ddaanet/reference_gate_hash_sandbox.md` — the whole file. **Delete it**
  and its pointer line in `memory/MEMORY.md` (composition drops the carrier copy
  in `memory/ddaanet/MEMORY.md` on the same pass; do not hand-edit that file).
- `memory/ddaanet/reference_sandbox_effects.md` — "phantom dotfiles" appears in
  its body and in its `memory/MEMORY.md` hook. Scrub both.
- `docs/design.md` — the `2026-07-26` changelog row added this session is written
  entirely around the sandbox story. Rewrite it; do not delete the row, the gate
  change is real.
- `justfile`, `scripts/run-gate.sh`, `tests/gate_sentinel.bats` — comments. The
  last two are being deleted anyway (below).
- `memory/project_gitlore_global_memory.md` and `memory/feedback_evals_happy_path.md`
  also match the grep — check whether their match is this claim or an unrelated
  use of the word before touching them.

### 1. Delete `run-gate.sh`; inline ghmem's checksum logic

David: "run-gate.sh is crap, remove it, the memory too, use the checksum based
logic from micro/tools/ghmem/justfile". So:

- `git rm scripts/run-gate.sh` and `tests/gate_sentinel.bats` (that suite exists
  only to test the script).
- Port `bash_prolog`, `gate-inputs-hash` and `check-sentinel` from
  `/Users/david/code/micro/tools/ghmem/justfile` into gitlore's `justfile` as a
  `bash_prolog` variable, and have `precommit` / `evals` call `check-sentinel`
  early and write `gate-inputs-hash > "$sentinel"` only on success — ghmem's
  shape exactly.
- Keep the sentinel **outside the working tree** at
  `$(git rev-parse --git-path gitlore/gates)/<name>`, not ghmem's gitignored
  `tmp/.<name>-sentinel`. gate_sentinel.bats asserted "never enters the working
  tree" and that property is worth keeping; ghmem only used `tmp/` because its
  repo had no better place.

### 2. Two input sets, not one

David: "changes to skills / agents / commands / hooks must invalidate evals, but
not precommit, those files are not used by plain tests."

**Concern, stated once, then build it as asked:** the grep says otherwise for all
four. `tests/plugin_distribution.bats` reads `agents/`, `commands/`, `skills/`
and `hooks/` and asserts on their real content — it is a distribution guard, not
a fixture test. `hooks/` is read by ten unit suites (`cc_hook_index_compose`,
`cc_hook_session_start`, `hook_manager_wire`, `index_sync`,
`push_rejection_discriminator`, `cc_hook_add_tier`, `cc_hook_recall`,
`hook_manager_detect`, `tier_divergence`, `plugin_distribution`); `skills/` by
`cc_hook_recall`; `commands/` by `cc_hook_add_tier`. Excluding them from
precommit's inputs is a knowingly-accepted stale green for those suites — e.g.
renaming `agents/memory-merger.md` leaves precommit skipping while
`plugin_distribution.bats`'s guard is now false.

Recommendation: split as instructed but keep **`hooks`** in the precommit set —
ten suites read it, which is not a marginal call. Put `agents`, `commands`,
`skills` in the evals-only set. If David wants the literal split, take it and say
which suites go stale.

### 3. Memory commits take no conventional prefix

David: "this is memory, no conventional commit, it would always be docs." So the
approval summary written to `.claude/gitlore-memory-message` is plain prose — no
`docs:`/`fix:` prefix. `CLAUDE.md` says "Conventional-commit prefixes are
required"; that rule is about the **parent** repo. Worth a memory entry and
possibly a `CLAUDE.md` clarification, once the store is being written again.

## What is already done and should survive

- `Makefile` deleted (staged `D`); its five targets are justfile recipes
  (`check-version`, `lint`, `test`, `test-unit`, `test-integration`), suites
  discovered by glob, never hand-listed.
- `tests/justfile_gates.bats` — **new, untracked, 7 cases, each mutation-checked
  red.** Keep it. Two of its assertions carry the one finding worth salvaging
  from the deleted memory: an explicit input allow-list **narrows silently**
  (`git ls-files` says nothing about a pathspec matching nothing, and a new
  top-level directory is simply never enumerated), so every declared path must
  exist and every top-level entry must be declared or on a written-down
  exclusion list. Both must survive the port to the inline prolog, and the
  second needs splitting across the two input sets.
- `memory/` and `docs/` stay excluded from every gate's inputs: no check reads
  either, and memory is staged as a gitlink, so including it re-ran the whole
  ~10-minute suite on every memory commit.
- `README.md` Development section rewritten (`make test` → `just test`).
- Full suite green: **579 ok / 0 not ok**, run at 18:44.

## Tree state

Parent at `f6c3d4e` on `origin/main`, **nothing committed this session**. Memory
is at `7044112` with local `live` advanced; the parent has NOT recorded that
gitlink and has NOT pushed. `memory/` and the `ddaanet` tier are both clean —
the un-approved index edit made earlier was reverted, so no FR11 gate is armed.

Staged: `D Makefile`, `A docs/plans/brief-memory-commit-batch-model-channel.patch`
(the brief at line 7 names it as a companion and `62b1e59` committed the `.md`
without it — include it). Unstaged: `justfile`, `scripts/run-gate.sh`,
`tests/gate_sentinel.bats`, `README.md`, `docs/design.md`, `memory` gitlink.
Untracked: `tests/justfile_gates.bats`.

The sentinel `.git/gitlore/gates/precommit` holds `4070476222 671692` in the
current `cksum` format; `.git/gitlore/gates/evals` still holds an old 41-byte
sha1, so the first `just evals` after this will correctly re-run. Both formats
change again when the logic moves into the justfile — expect one forced re-run.

## Open decisions

- The literal-vs-evidence split above (§2) is the one real decision.

- `memory/MEMORY.md` is at **95% of the 25600-byte budget**, ~24.3KB against a
  24.4KB read limit — the *hard* limit now, not the advisory one. Deleting the
  `reference_gate_hash_sandbox` line buys ~450 bytes back, which may be enough
  to defer a full pass. Do not compact opportunistically:
  `feedback_index_compaction_triggers` records that last session's pass needed an
  adversarial audit to catch 15 over-cuts.
