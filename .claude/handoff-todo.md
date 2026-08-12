## Remaining

- Add a gitlore SessionStart pairing check: warn when the ddaanet tier is
  mounted but `prohibitions@ddaanet` is absent from `enabledPlugins`. The
  tier and the plugin install independently and nothing couples them, so a
  repo mounting one without the other is permanently unguarded with no
  visible symptom.
- Apply the briefs under `plans/`: hook-exec-and-compose-revert,
  memory-index-glued-bullets, merge-dispatch-authorization,
  handoff-integration-evals.
- Apply the briefs at the repo root: `brief-plugin-dev-0.5.3.md`,
  `brief-stale-plugin-root-detector-confirmed.md`,
  `brief-index-compose-drops-unterminated-final-line.md`,
  `brief-orphaned-merge-head-no-state-file.md`.
- Propose to `shell-scripting` (another repo, proposal only): the
  `GIT_INDEX_FILE` save/restore around a staging `git add`, and the
  `160000` gitlink symptom. Landing both would make `git-hook-env-leak`
  and `submodule-escape-to-parent` genuinely retirable.
- Propose the memory-submodule carve-out to `ddaa:preflight`'s clean-tree
  and submodule checks — another repo, proposal only.
- Propose the plan-escalation rule as a patch to
  `superpowers:executing-plans`, likewise read-only.
- Migrate the `micro` tier (~40 facts) once a real memory remote is
  settled; it and `general` still point at `./.git/gitlore-placeholder`.
  Then `gitmoji` -> `general` -> `home` -> `devddaanet` -> `skills` ->
  `candidature` -> `edify` -> `Emploi` -> `cwd-safety`.