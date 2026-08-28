# Testing — the two tiers and the gate's cost

The detail behind `design.md`'s NFR9 and NFR10: what each test tier can see,
which is what decides where a case goes, and what the commit gate costs today.
No decision is argued here; the eval harness's own practice is in the four
`evals-*.md` nodes.

---

## Two tiers, split by what each can see (NFR9)

The bats suites (`tests/*.bats`) own the edge cases and every script's
contract, called the way production calls it. The eval harness (`tests/evals/`)
owns the **happy paths**, driven through the real agent, because the seam
between the agent and the shell is invisible to bats: no assertion can drive "a
session starts, the agent edits memory, the user approves, the commit lands,"
and a prompt has no assertion-level test at all. Scenarios stay in the `pass^k`
shape the harness already uses, so an agent-side flake stays distinguishable
from a regression. Edge cases do not go in an eval; an eval's value is proving
the whole chain fits together.

## The gate's cost (NFR10)

`just precommit` — `format-docs`, `check-distribution`, then
`check-version lint test` — runs 530 s over 620 cases (measured 2026-07-29 on
the 2-vCPU dev droplet, `--jobs 2`; `check-distribution` adds ~2 s and carries
its own sentinel, so a change confined to `agents/`, `commands/` or `skills/`
pays only that). `user + sys` came to 566 s against 530 s wall, so the suite is
barely parallel and more cores would not divide the number. Making it faster is
open work, and cutting per-case work is the lever, not raising `--jobs`.
`bats -T` reports per-test timings, so the breakdown that would direct that
work comes free on the next full run. The input-hash sentinel caches a green
result, so the full cost is paid precisely when a change is in flight.
