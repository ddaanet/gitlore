# 2026-07-21 — The parent commit now records the memory pointer its own hook just created

`pre-commit` committed memory and advanced `live` but never staged the gitlink,
so the parent pinned the *pre-hook* memory SHA — every parent commit lagged one
memory commit, a fresh clone at any commit restored stale memory, and a manual
"pin the pointer" follow-up commit was the standing workaround (twice in two
days). The hook now stages `$mempath` after a successful
`gitlore_sync_memory_to_live`. The subtlety is **which index**: git hands the
hook a different one per invocation — `.git/index` for a plain commit,
`.git/index.lock` under `-a`, a `.git/next-index-*.lock` temp index for a
pathspec commit (characterized against git 2.47.3). A bare `git add` does not
merely miss the latter two, it dies on
`Unable to create '.git/index.lock': File exists` and, under `set -e`,
**blocks the commit** — so `GIT_INDEX_FILE` is captured *before* the
`--local-env-vars` unset (which exists for submodule resolution) and restored
for that one `git add`. `tests/integration_gitlink_staging.bats` drives all
three modes through a real `git commit`, since the invocation is the behaviour:
every existing test called the hook directly and none could have caught this.
D16's rationale dropped its now-false "it doesn't stage the submodule gitlink
anyway" clause.
