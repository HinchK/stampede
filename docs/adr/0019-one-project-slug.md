# ADR 0019: One Project Slug, Taken From `[swarm] name`

- **Status**: Accepted
- **Date**: 2026-11-07
- **Deciders**: HinchK (decided in the post-mortem grilling), Claude (recorded)
- **Consulted**: [2026-11-07 swarm post-mortem](../audits/2026-11-07-swarm-postmortem.md) §4.2, [ADR 0003](0003-dynamic-seating-and-nonce-brief-delivery.md), `CONTEXT.md` §4 *Slug Namespacing* and §14 *Fail-Closed Ref Resolution*, issue #166 (ARB-SLUG-2), closed #66, ticket ARB-SLUG-1

---

A project has exactly one slug, read from `[swarm] name` in `swarm.config.toml`. It names the agents (`arch-1-stampede`), the seat branches (`swarm/stampede/arch-1-stampede`) and the integration line (`swarm/stampede/integration`). The launcher must not derive a second slug from the GitHub repo name or the directory name when `[swarm] name` is set.

We decided this because the project has had two slugs, and that split has now caused the same defect three times. The launcher slugified `REPO` (`hinchk-stampede`), while the arbiter CLI and the supervisor used `SWARM_CONFIG_NAME` (`stampede`). ARB-SLUG-1 produced a phantom integration ref, #66 was the same class, and #166 split integration across `swarm/stampede/integration` and `swarm/hinchk-stampede/integration` during the 2026-11-06 run. Sharing `slugify()` didn't help, because the callers passed it different inputs. This ADR makes the input single-sourced.

## Considered options

- **The repo-derived slug everywhere** (`owner/repo`, which is globally unique). Rejected because local-only projects have no repo, so a fallback (the directory name) would still be needed: two sources again.
- **Two named slugs, an agent namespace from the repo and an integration line from config.** Rejected because "which slug does this caller want?" is the question every one of the three incidents got wrong.

## Consequences

- Two local projects that both set `[swarm] name = "stampede"` would collide in Herdr's server-global agent registry. We accept this because the user chooses the name and can change it.
- Agent names and seat branches change from `*-hinchk-stampede` to `*-stampede`. This rename is done in the post-mortem reset, when the seat branches are recreated anyway. Fixing the launcher's slug derivation is #166.
