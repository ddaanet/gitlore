# 2026-08-25 — docs/ and plans/ are hard-wrapped by a formatter, so a line count means something

Prose in `docs/` and `plans/` was one paragraph per line, so a 400-line cap or
a "how big is this plan" glance measured paragraphs, not text. `just
format-docs` now hard-wraps both trees at 80 columns and runs first in
`precommit`; no sentinel, because a full pass over 101 files is ~0.4 s, less
than the gate bookkeeping would cost.

The formatter is rumdl, chosen over prettier, dprint, mdformat, mdslw, remark
and pandoc by one test: render every file to HTML with cmark-gfm before and
after, and diff. rumdl's MD013 reflow was the only candidate with zero
rendering changes on well-formed input and no change to emphasis markers —
prettier rewrites `*em*` to `_em_` with no option to keep it, dprint dedents
fenced code, mdslw and remark break lines inside headings, table cells and code
spans. rumdl's cache buys nothing at that size, so `--no-cache` keeps the tree
clean. Only MD013 is enabled: rumdl is a wrapper here, not a linter.

The pin is a uv dependency group in `pyproject.toml` with `uv.lock`, per the
shared convention: `uv sync` once, `.envrc` puts `.venv/bin` on `PATH`, the
recipe calls bare `rumdl` and refuses a version off the pin rather than
wrapping the tree with whatever is installed. `uvx` in the recipe was rejected
because it goes through `~/.cache/uv`, which the agent sandbox blocks. The
first attempt at the prefix turned seven wiring tests red: the venv's python3
shadowed the system one, and `scripts/hook-manager/wire-*.sh` probe `python3`
for PyYAML. That exposed a dependency the gate had on the system python all
along, so PyYAML is in the dev group too and the wiring suite now runs on what
`uv.lock` says.

The render diff also surfaced six plans with a three-backtick `markdown` fence
holding a three-backtick `bash` fence, where the inner close ended the outer
block; those outer fences are now four backticks. They rendered wrong before
and tripped every candidate, so the fix precedes the first formatting run.

The first pass also broke `scripts/check-docs-links.py`: it read a cluster
node's summary bullet one line at a time, and once wrapped, the `**D27**`
citations on continuation lines counted for nothing — ten sub-decisions
reported as unstubbed. The checker now joins a bullet with its indented
continuation lines before reading it.
