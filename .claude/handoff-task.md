## Current task

Nothing is in flight. The two routing-key advisories now ride the
index→frontmatter sync — byte budget and missing-trigger-token — built,
green (530), documented, and dogfooded both directions against the real
store, which is now at 0 flags and 71% of budget.

The shape worth carrying: the *named* version of this feature was refuted
before anything was built. Scoring a hook against its body's distinctive
tokens (tf-idf) does not discriminate at 76 documents — `df ≤ 3` marks
ordinary prose as distinctive, so the score tracks hook LENGTH, not
quality. What replaced it is two countable things, and the second one is
only usable because it is gated on `metadata.type`: ungated it fires on
22 of 76 bullets, type-conditioned on 3 of 37. A `reference` fact is
reached by an error string or a flag; a `feedback` rule is reached by
topic, where prose is correct.

## Open decisions

- **The push backlog.** `main` carries the memory and tier commits that
  one parent push publishes in lockstep via `pre-push`. Not deferred for
  a technical reason — it is outward-facing, so it waits to be asked for.
  Raised repeatedly; stop raising it unprompted.
- **The third index-quality failure mode is unaddressed and may stay
  that way** — a trigger that is *present but buried* in a
  paragraph-length line. Nothing countable can see it; the options are
  leaving it to the agent (current) or a semantic pass at the artifact
  boundary, which costs a model call per index write or becomes a
  `/gitlore:lint-index` command nobody runs.
- **`just prerelease` has never run against the three eval scenarios.**
  They have only ever run at `EVAL_K=1`; the real gate is `pass^5`, slow
  and paid.
- **`release` depends on a plugin-defined `prerelease`** — the fix
  belongs in `ddaanet/claude-plugin-dev`, not this repo's vendored copy;
  today releases go `just prerelease release`.
