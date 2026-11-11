# Tier routing

Open this when a tier is mounted and the fact might go up to it.

## 5. Which tier

Ask whether the fact's *mechanism* depends on something unique to this repo, or
only on this repo being a member of a class — a plugin, a hook-managed repo, a
submodule-based store. Evidence naming the repo where it surfaced is not
evidence the mechanism depends on that repo.

Class membership is necessary, not sufficient. A mechanism can belong to the
class and still have exactly one consumer: name the *other* member that will
meet the symptom. Being true anywhere does not make it relevant everywhere. The
asymmetry favours staying local: a tier line is loaded by every session in
every mounting repo against a capped index, so a weak promotion crowds lines
that route better, silently, in every repo; demotion later costs a file move.
Separate behaviour from encoding — how this repo's code handles a mechanism is
always project-local, and usually belongs in its design doc rather than memory.

## 6. Links when a fact routes up

`[[links]]` travel verbatim. Any that pointed at a project-local sibling
resolve only in the repo that wrote them and are dead from every other consumer
of the tier — not the acceptable write-it-later dangle, since the target stays
local by design. Strip the pointer and keep the prose that names the incident;
where the link *was* the whole reference, delete it — a tier fact stands on its
own or it is not a tier fact. Also strip a link naming a skill rather than a
memory, and one whose target the prose already names.
