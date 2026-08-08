#!/usr/bin/env bash
# Trigger strings that a NEGATIVE assertion somewhere refutes.
#
# A negative spelling its string inline goes vacuous the day production rewords:
# the assertion keeps passing, having quietly stopped watching anything. Held
# here, one literal is read by both sides — at least one POSITIVE assertion
# pins that production still emits it, and the negatives refute the same
# variable. A rename turns the positive red, the literal is corrected once, and
# every negative moves with it.
#
# Define the literal here rather than sourcing it from the production lib.
# Sourcing moves both sides together, and the positive then only detects
# non-emission — never a bad rename. The duplication is the pin.
#
# Each entry names, in its comment, the positive that pins it. An entry with no
# positive is not covered by this mechanism and must say so.

# Read from the .bats suites, never from here.
# shellcheck disable=SC2034

# The post-mount triage nudge's marker (D17). Pinned by "a manifest-touching
# batch emits a triage directive naming the active tier's scope" in
# tests/cc_hook_index_compose.bats.
GITLORE_T_TRIAGE_MARK='active-tier'

# Git's own advice when a nested repository is staged as a plain tree instead of
# a gitlink. Not gitlore's wording — pinned by staging a nested repo directly in
# "install does not emit the embedded-git-repository advice"
# (tests/install_run.bats), which is the only way to observe a third-party
# message gitlore exists to avoid producing.
GITLORE_T_EMBEDDED_REPO='embedded git repository'

# The dangling-pointer report's wording (scripts/lib/index-compose.sh). Pinned by
# "a dangling pointer names the file and the index that carries it" in
# tests/index_compose.bats; refuted where compose has nothing dangling to say.
GITLORE_T_DANGLING='names no file'

# The submodule url install writes before a real remote exists
# (scripts/install/init-submodule.sh). Pinned by "local mode keeps placeholder
# and never calls gh" in tests/install_remote.bats.
GITLORE_T_PLACEHOLDER_URL='./.git/gitlore-placeholder'

# Git's own error when a hook runs with the parent's GIT_DIR still exported.
# Not gitlore's wording — pinned by provoking it directly with the same leaked
# environment in "ignores parent GIT_DIR/GIT_INDEX_FILE leaked by 'git commit'"
# (tests/git_hook_pre_commit.bats), which is the only way to show the message is
# still live in this git and that this fixture reaches the producer at all.
GITLORE_T_LEAKED_GITDIR='index file open failed'

# scripts/install/global-shim.sh's `${CLAUDE_PLUGIN_ROOT:?…}` bail. Pinned by
# "the shim refuses without CLAUDE_PLUGIN_ROOT" in tests/global_shim.bats;
# refuted in tests/resolve.bats, where resolve.sh must derive its own root
# instead of bailing this way.
GITLORE_T_PLUGIN_ROOT_UNSET='CLAUDE_PLUGIN_ROOT must be set'
