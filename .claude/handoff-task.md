## Current task

A second shell-gotchas audit, over every shell file NOT changed since v0.5.0 — the first pass, filed at `plans/2026-08-27-shell-gotchas-audit.md`, covered only the changed files and is fully applied. macOS compatibility is a requirement of this pass: bash 3.2, BSD `sed`/`find`/`stat`/`paste`, no `timeout`; audit each file whole, verify each BLOCK/WARN empirically, fix test-first, and file the report under `plans/`.
