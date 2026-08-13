## Remaining

1. **The unterminated-final-line defect in `scripts/lib/index-merge.sh`** — the
   same class just fixed in `index-compose.sh`, in the divergence merge rather
   than the in-session pass, and unscoped by the brief that reported it.
   `gitlore_index_merge_paths` (line 28) reads a side's bullets with a bare
   `read`, so an unterminated index loses its last path from that side's list
   and the entry-wise presence rule reads the absence as a deletion. Found by
   reading, not yet reproduced — verify before fixing, then red-test it. The
   `cat "$tmpd/out.pre" "$tmpd/out.bullets" "$tmpd/out.post"` at line 135 has
   the mirror hazard `gitlore_compose_write` just had, and is likewise
   unverified. `gitlore_compose_pick`, which that file also leans on, is
   already guarded.

Then brief application, ordered by increasing risk and size. Paths are
`plans/` unless the brief sits at the repo root.

2. **`brief-merge-dispatch-authorization.md`** — wording only: make a hook
   directive that names a sub-agent read as authorized by the command the
   user already ran. Applies to the whole class of such directives, not the
   one instance; tests asserting hook text move with it.
3. **`brief-resolve-noisy-noop-failure.md`** (root) — the standalone resolver
   fails noisily against a tier already at its remote tip, taking the resolve
   skill's "surface stderr verbatim and stop" branch on what is a no-op. Found
   from `onekeys`, so read the brief's own repro before deciding the fix.
4. **`brief-memory-index-glued-bullets.md`** — a glued-bullet rule in
   `gitlore_compose_check_index` (decided: no backtick-awareness) and a `](`
   refusal in `index-sync-post.sh`. Its request 3 has already landed with the
   unterminated-line fix — do not apply it again. Its request 4 is decided and
   written up in the brief: a `PreToolUse`/`PostToolUse` pair that computes the
   intended result of a risky-shaped `Edit`, repairs the file when they differ,
   and reports when they stop differing so the pair can retire.
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
   is canonical, and a wrong answer silently destroys merged memory.
8. **`brief-handoff-integration-evals.md`** — largest by effort, lowest blast
   radius: new eval scenarios only, no production code. Needs `lib/setup.sh`
   to become two-plugin aware, and the brief names PATH resolution for
   handoff's `bin/` as its single largest unknown. Evals cost money per run
   and are opt-in, not in the default gate.