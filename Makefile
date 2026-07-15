.PHONY: test test-unit test-integration check-version evals lint

# Shellcheck every tracked shell script (extension or shebang) at default
# severity. Discovery and invocation live in scripts/lint-shell.sh.
lint:
	scripts/lint-shell.sh

test: test-unit test-integration

# Discovered by glob, not hand-listed: an explicit list silently orphans new
# suites (five drifted off it, incl. the FR11 memory-gate cover). Integration =
# tests/integration_*.bats + the evals libs; unit = every other tests/*.bats.
INTEGRATION_TESTS := $(wildcard tests/integration_*.bats) $(wildcard tests/evals/lib/*.bats)
UNIT_TESTS := $(filter-out $(INTEGRATION_TESTS),$(wildcard tests/*.bats))

test-unit:
	bats $(UNIT_TESTS)

# Fail if plugin.json drifts from the gitlore entry in the sibling marketplace
# repo (../claude-plugins). Skips cleanly when that repo isn't checked out.
check-version:
	scripts/check-version.sh

test-integration:
	bats $(INTEGRATION_TESTS)

.PHONY: evals
evals:
	tests/evals/run-evals.sh
