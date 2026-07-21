import 'plugin-dev/release.just'

# Two gates, each with its own sentinel (scripts/run-gate.sh): they invalidate
# together — any tree change invalidates both — but skip independently. So
# `just prerelease` right after a green `just precommit` re-runs only the evals,
# the part precommit does not cover.
#
# `just release` depends on `precommit` alone (that dependency lives in the
# vendored plugin-dev/release.just). Release via `just prerelease release`: the
# evals run once, and release's own precommit is a sentinel skip.

# Fast, frequent. Version drift, shellcheck, then the full bats suite.
precommit:
    scripts/run-gate.sh precommit make check-version lint test

# Slow, rare. Drives the real claude CLI, so it costs time and money.
evals:
    scripts/run-gate.sh evals make evals

# The full pre-release gate.
prerelease: precommit evals
