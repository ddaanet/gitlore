.PHONY: test test-unit test-integration check-version

test: test-unit test-integration

test-unit:
	bats tests/lib_util.bats tests/lib_log.bats tests/hook_manager_detect.bats tests/hook_manager_wire.bats tests/emit_wrappers.bats tests/cc_hook_session_start.bats tests/cc_hook_post_tool_use.bats tests/git_hook_pre_commit.bats tests/install_run.bats tests/smoke.bats tests/pre_push_hook.bats tests/gh_mock.bats tests/install_remote.bats tests/resolve.bats tests/resolve_merge_branch.bats tests/resolve_merge_remote.bats tests/resolve_both_flavors.bats tests/resolve_recovery.bats tests/plugin_distribution.bats tests/launcher_shim.bats tests/emit_launcher.bats tests/global_shim.bats tests/cc_hook_worktree_remove.bats tests/check_version.bats

# Fail if plugin.json drifts from the gitlore entry in the sibling marketplace
# repo (../claude-plugins). Skips cleanly when that repo isn't checked out.
check-version:
	scripts/check-version.sh

test-integration:
	bats tests/integration_happy_path.bats tests/integration_clone_restore.bats
