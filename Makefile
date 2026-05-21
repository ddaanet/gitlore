.PHONY: test test-unit test-integration

test: test-unit test-integration

test-unit:
	bats tests/lib_util.bats tests/lib_log.bats tests/hook_manager_detect.bats tests/hook_manager_wire.bats tests/emit_wrappers.bats tests/cc_hook_session_start.bats tests/cc_hook_post_tool_use.bats tests/git_hook_pre_commit.bats tests/install_run.bats tests/smoke.bats tests/pre_push_hook.bats tests/gh_mock.bats tests/install_remote.bats tests/resolve.bats

test-integration:
	bats tests/integration_happy_path.bats
