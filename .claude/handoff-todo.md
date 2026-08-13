## Remaining

Brief application, ordered by increasing risk and size. Paths are `plans/`
unless the brief sits at the repo root.

1. **`brief-merge-dispatch-authorization.md`** — wording only: make a hook
   directive that names a sub-agent read as authorized by the command the
   user already ran. Applies to the whole class of such directives, not the
   one instance; tests asserting hook text move with it.
2. **`brief-resolve-noisy-noop-failure.md`** (root) — the standalone resolver
   fails noisily against a tier already at its remote tip, taking the resolve
   skill's "surface stderr verbatim and stop" branch on what is a no-op. Found
   from `onekeys`, so read the brief's own repro before deciding the fix.
3. **`brief-index-compose-drops-unterminated-final-line.md`** (root) —
   mechanical: `|| [ -n "$line" ]` on the 13 unguarded `read -r line` sites
   in `scripts/lib/index-compose.sh` (91 and 217 are already guarded), plus a
   regression test in `tests/index_compose.bats` needing a helper that seeds
   an index with no trailing newline. Confirmed data loss, repro in the brief.
4. **`brief-memory-index-glued-bullets.md`** — a glued-bullet rule in
   `gitlore_compose_check_index` (decided: no backtick-awareness) and a `](`
   refusal in `index-sync-post.sh`. Its request 3 is item 3's fix — do not
   apply twice. Request 4 is an optional add that introduces a new hook;
   decide separately.
5. **`brief-hook-exec-and-compose-revert.md`, defect 1** — the installer
   appends its line after an existing `exec`, leaving it unreachable. Refuse
   or interpose rather than append silently. Self-contained to the install
   path.
6. **`brief-orphaned-merge-head-no-state-file.md`** (root) — merge core.
   `gitlore_prepare_merge` reads `pending` from `HEAD` rather than `live`,
   and the stale-merge guard keys on the state file rather than `MERGE_HEAD`.
   The brief offers three fixes and recommends none decisively; pick one
   before writing code.
7. **`brief-hook-exec-and-compose-revert.md`, defect 2** — composition
   reverts an incoming tier merge by mirroring root's wording down over a
   merged carrier. Highest blast radius of the set: it changes which surface
   is canonical, and a wrong answer silently destroys merged memory. Touches
   the same file as items 3 and 4, so sequence it after them.
8. **`brief-handoff-integration-evals.md`** — largest by effort, lowest blast
   radius: new eval scenarios only, no production code. Needs `lib/setup.sh`
   to become two-plugin aware, and the brief names PATH resolution for
   handoff's `bin/` as its single largest unknown. Evals cost money per run
   and are opt-in, not in the default gate.