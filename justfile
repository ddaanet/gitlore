import 'plugin-dev/release.just'

# `evals` is a separate, opt-in recipe: the 5-round eval grid drives the real
# claude CLI, so it costs real time and money and doesn't belong in the
# default release gate. Run it explicitly when a change touches eval-covered
# behavior.
#
# `just release` depends on `prerelease` (that dependency lives in the vendored
# plugin-dev/release.just, which requires every consumer to define the recipe).

# Fast, frequent. Version drift, shellcheck, then the full bats suite.
precommit:
    scripts/run-gate.sh precommit make check-version lint test

# Slow, rare. Drives the real claude CLI, so it costs time and money. Run
# explicitly, not part of the default release gate.
evals:
    scripts/run-gate.sh evals make evals

# The pre-release gate. Same as precommit; kept as its own name for
# `release`'s dependency and for the option to widen it later.
prerelease: precommit
