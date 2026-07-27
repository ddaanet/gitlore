## Current task

A `/ddaa:proof` pass over gitlore's **local** memory — the bare-path files in
`memory/`, not the 91 `ddaanet/` tier facts. Item-by-item: present, analyze, take
David's verdict, apply. Items 1-8 are decided; resume at item 9. Eight local
facts remain, so the pass runs to item 16.

**The test the pass converged on, sharpened at item 6 and applied since:** is the
claim recorded where it acts? Everything splits four ways —

1. Basic knowledge a model already has (that prompts need evals; that installers
   should be dogfooded) → delete, record nothing.
2. A gitlore design decision (the bats/eval division of labour; the `pass^k`
   scenario shape) → `docs/design.md`, present tense in NFR or Architecture,
   dated only in the changelog.
3. A don't-regress constraint (why `create-remote.sh` does not use
   `gh repo create --source=.`) → a comment on the line that would be regressed.
4. A silence the code should not have (pre-push skipping the memory push without
   saying so) → **fix the code**; the memory only existed to compensate.

Only what survives all four is memory. Six files have gone this way so far, and
none of the remaining eight has yet been read against categories 3 and 4.

Two rules from earlier in the pass still bind: a memory restating what a skill or
design doc already owns is deleted, not refined
(`ddaanet/feedback_memory_not_other_owners_job`); and when the owner is missing
the statement, fix the owner — a brief into its repo — rather than keeping the
memory. Two promotions proposed before item 3 were **rejected and must not be
revived**, under David's trigger test: a useful trigger is one automemory
recognizes from a user prompt, or `/gitlore:recall` recognizes from context.

Items 9-16 in presentation order: `reference_submodule_config_visibility`,
`reference_auto_memory_directory`, `reference_nested_submodule_tier` (451 B index
line, now the largest local one), `reference_own_hooks_json_sandbox_erofs`,
`reference_cc_memory_retrieval_agentic`, `feedback_memory_retrieval_in_practice`,
`feedback_recall_checkpoints`, `feedback_memory_before_root_commit`. The last
three are all about recall and may consolidate — but check first whether any of
them is category 2, since `docs/design.md` owns the recall design.

## Open decisions

- **`name:` frontmatter drift is the root of the name-drift dangling links.**
  Local files carry a hyphenated `name:` that does not match the filename stem —
  `cc-memory-retrieval-agentic` and `reference-submodule-config-visibility`
  remain, and the tier has its own (`reference-submodule-escape-to-parent`).
  Normalizing `name:` to the filename stem repairs that whole link class at once.
  Settle with the dangling-link item at the end of the pass, not per-file.

- **Dangling `[[...]]` links across the store**, two classes: name-drift (above)
  and genuinely absent targets (`reference_cross_repo_push_auth`,
  `reference_plugin_cache_staleness`, `feedback_verify_handoff_pending`,
  `feedback_git_status_sandbox`, `reference_cc_sandbox_resume_transcript`,
  `feedback_agent_executes`). Re-audit at the end; the count of 28 predates this
  session's deletions and repairs.

- **Index compaction still stands; the hook nags on every index write.**
  22.1 KB, 89% of the 25600 budget. Largest lines:
  `ddaanet/reference_git_stderr_and_parsing` 456 B,
  `reference_nested_submodule_tier` 451 B,
  `ddaanet/feedback_classifier_denied_self_config` 449 B,
  `ddaanet/reference_gitlore_memory_commit_routing` 378 B,
  `ddaanet/reference_sandbox_effects` 351 B. `feedback_index_compaction_triggers`
  requires an adversarial audit of the diff; the last pass over-cut 15 lines.
  Nothing has been trimmed opportunistically. The pass itself is shrinking the
  index faster than a trim would, so this may not need doing at all.

- **The vanished-pointer evidence is gone and cannot be re-derived.**
  `refs/gitlore/compose-base` refreshed again during later composes and has no
  reflog. That is the standing argument for making compose record which base it
  merged. The `resolve_compose` red a previous handoff called "the handle" does
  NOT reproduce — `just test` ran green this session.

- Whether the `agents`/`commands`/`skills` exclusion from `precommit_inputs`
  should stand. It is what was asked for, and it means an edit to any of those
  three leaves a green precommit green.
