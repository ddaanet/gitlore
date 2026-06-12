#!/usr/bin/env bash
set -euo pipefail

# Emit the submodule-side commit gate (Fix A / FR11). Writes a wrapper into the
# memory submodule's hooks dir that execs the plugin's `memory-pre-commit`. The
# wrapper mirrors the parent wrappers (emit-wrappers.sh / D5): it resolves the
# live plugin via `git config gitlore.hooksDir` and degrades to a clean skip
# when that config is unset or stale, so a transient plugin state never bricks a
# memory commit (NFR8).
#
# The submodule gitdir's hooks dir (`git -C <mempath> rev-parse --git-path
# hooks`) is the *common* hooks dir, shared across every submodule worktree, so
# a single emission also guards linked-worktree memory trees (D11 parity).

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(git config gitlore.hooksDir)/../..}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"

mempath=$(gitlore_memory_path 2>/dev/null) || exit 0   # no submodule → nothing to guard

# Session-less linked worktree: the memory tree isn't checked out, so its gitdir
# pointer is absent and `--git-path` can't resolve. The shared common-dir hooks
# dir is already covered by the main worktree's emission; nothing to do here.
[ -e "$mempath/.git" ] || exit 0

# The wrapper resolves the live plugin via `git config gitlore.hooksDir`. When it
# fires under `git -C <mempath> commit`, `git config` reads the SUBMODULE's config,
# not the parent's where SessionStart pins the key — so mirror the parent's value
# into the submodule config (common config, shared across submodule worktrees).
# Only when set: leaving it unset preserves the "hooks not installed" skip path.
parent_hooksdir=$(git config gitlore.hooksDir 2>/dev/null || true)
[ -n "$parent_hooksdir" ] && git -C "$mempath" config gitlore.hooksDir "$parent_hooksdir"

hooks_dir=$(git -C "$mempath" rev-parse --git-path hooks)
mkdir -p "$hooks_dir"

gitlore_emit_hook_wrapper "$hooks_dir/pre-commit" memory-pre-commit
