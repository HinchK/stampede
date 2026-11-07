# Evolving harness swarm vocabulary (superseded)

> **Superseded 2026-11-07.** Moved out of `CONTEXT.md` by the [2026-11-07 swarm post-mortem](../../docs/audits/2026-11-07-swarm-postmortem.md). The "agreed" in the original heading below was not the human's agreement: `looper` answered the EHS-10 grilling (Q1–Q7), and HinchK did not ask for the features these terms describe. Kept as a record only; these are not live terms.

## Agreed vocabulary for the evolving harness swarm

These definitions describe the planned pilot, not shipped capabilities. The accepted requirements live in [Define the first engineering workload and what better means](issues/01-workload-and-success.md).

**Starter task**:
A bounded piece of engineering work initiated by the user during guided team setup to demonstrate that the assembled team can launch, complete useful work, and stop and resume.
_Avoid_: Treating configuration generation alone as successful team setup; assuming a starter task authorizes publishing or production changes.

**Run stop policy**:
The user's selected work-completion, elapsed-time, and action boundaries for pausing a swarm run, together with mandatory human handoff boundaries.
_Avoid_: Conflating a planned break with a failure or with successful completion of the project.

**Credential handoff**:
A mandatory human pause for credential handling outside an explicit secret-exposure/cycling grant; secret values remain excluded from routine logs and generated public artifacts. Normal use of an existing authenticated provider session is distinct from a credential handoff.
_Avoid_: Asking the user to paste secret values into an agent conversation or treating a configured stop as authorization to handle credentials.

**Team configuration**:
The available providers and specialist harness recipes from which Stampede starts workers as useful work becomes ready.
_Avoid_: Equating the configured team with a permanently running roster of agents.

**Harness recipe**:
A reusable description of a model choice, instructions, tools, relevant context, checks, and limits for a kind of work.
_Avoid_: Treating a model name alone as a complete worker configuration.

**Assisted kickoff**:
An optional startup interview that uses research and contrasting agent perspectives to help the human establish the initial epic's goal and boundaries.
_Avoid_: Treating agreement among research agents as the human's agreement to an objective or its boundaries.


The following work-boundary definitions were agreed in [Define the domain contract and smallest useful execution loop](issues/04-domain-and-loop.md).

**Epic**:
The overall agreed outcome toward which the swarm works.
_Avoid_: Treating a single worker's completion as completion of the entire outcome.

**Milestone**:
A demonstrable result with acceptance checks.
_Avoid_: Declaring a milestone complete solely because an agent says it is done.

**Sprint**:
A bounded selection of work toward milestones.
_Avoid_: Equating every sprint with a fixed number of elapsed hours.

**Timed break**:
A planned pause in progress that does not declare a sprint, milestone, or epic complete.
_Avoid_: Counting unfinished work as accepted merely because its allotted time expired.

**Improvement allowance**:
A separate allowance agreed at startup for improving the swarm's harnesses after the selected delivery stopping point. Overall time and budget limits still apply.
_Avoid_: Treating completion of delivery work as permission for unlimited improvement work.


**Worker attempt**:
One worker's effort on a work item, recorded separately from earlier or successor attempts. A worker stop or model switch preserves the work item's identity while a successor begins a new attempt.
_Avoid_: Counting a retry or duplicate result as an additional completed work item.

**Project checkpoint**:
A handoff record of accepted progress, unfinished changes, evidence, and the next action. A successor rechecks the inherited state before relying on it.
_Avoid_: Treating a saved checkpoint as proof that its contents are still current or that unfinished work is complete.


**Contract-lawyer agent**:
The swarm's designated mediator for handoffs and decisions arising from friction or failure. It records mediated events and their decisions, normally resolving them autonomously and seeking human input when context is insufficient or security/stability implications require it. It may clarify requirements, replace faulty checks with equivalent ones, and order verification or rework while preserving agreed outcomes, quality requirements, and hard stops.
_Avoid_: Treating mediation as human approval of every task or as an implicit expansion of the swarm's authority.


**Work item**:
A unit of work toward the agreed outcome, with dependencies, permitted changes/tools, acceptance checks, and limits. Its identity persists across worker attempts.
_Avoid_: Requiring human approval for every routine subtask within already agreed boundaries.

**Completion evidence**:
Results and checks supporting acceptance of a work item against its agreed outcome and quality requirements.
_Avoid_: Treating a worker's declaration or a mediator's desire to maintain progress as sufficient proof of completion.


The supervision terms below were settled in [Define traffic-control supervision and human-proxy authority](issues/12-traffic-control-authority.md).

**Supervision grant**:
A human-issued delegation of specified execution authority for an approved repository and run, bounded by permitted actions, resources, a selected work boundary, an explicit deadline, and revocation. It expires at the earliest applicable boundary and cannot be widened or renewed by an agent.
_Avoid_: Treating a pane message, existing login, or permission to open a PR as unrestricted authority.

**Traffic-control agent**:
An observer of swarm handoffs, metrics, and errors that can direct execution as a human proxy under an active supervision grant. It follows the contract-lawyer's interpretation of requirements, evidence, and handoffs within enforced limits.
_Avoid_: Letting execution urgency overrule acceptance evidence or the grant's boundaries.

**Affected-work pause**:
A pause of work needing human clarification and the actions depending on it, while independent authorized work can continue.
_Avoid_: Continuing dependent work as though the unresolved decision had been made.

**Run-wide stop**:
A halt across the run when credential handling outside an explicit exposure/cycling grant, overall limits, revocation, or an uncontained security/stability concern requires it.
_Avoid_: Continuing an improvement phase or independent worker to bypass the stop.


**Quota warning threshold**:
A remaining-subscription level at which startup-enabled quota management alerts the user in all panels and offers wrap-up/wait or transfer to another model. The agreed levels are 20%, 15%, 10%, and 5%; they are not retained-capacity reserves.
_Avoid_: Treating a warning as an automatic pause or presenting unknown remaining quota as a measured percentage.

**Designated backup model**:
The model/provider route selected to receive a work handoff when startup-enabled quota management encounters unavailable quota information or an exhausted primary route.
_Avoid_: Assuming another model on the same exhausted subscription supplies fresh capacity, or that a handoff creates new work authority.


**User-maintained secret file**:
A file whose secret values are managed by the human and excluded from agent access by default. Explicit secret-exposure/cycling grants may authorize selected access or updates; a provider client's internal login use is not such a grant.
_Avoid_: Treating setup, debugging, readiness checks, or ordinary proxy authority as permission to read or rewrite secret contents.


**Secret-exposure grant**:
An explicit per-run agreement permitting named credentials to selected agents/providers for specified use, coupled to a required credential-cycling pass. It does not permit values in Git commits, public output, or routine logs, or access by unapproved recipients.
_Avoid_: Treating opt-in exposure as permission to reveal every credential or to bypass grant expiry.

**Credential cycling pending**:
A durable unresolved obligation to complete and verify the required credential replacement and revocation pass after authorized exposure. It remains visible through interruptions until verified, with human guidance where automation is unsupported.
_Avoid_: Declaring cleanup complete on a model's assertion or extending work authority because cycling remains pending.


**Engineering attempt**:
An initial effort or repair toward a work item's acceptance outcome, distinct from the worker sessions that execute it. A quota/process interruption can continue the same engineering attempt through a new worker attempt without spending a repair merely for switching or restoring repairs already used.
_Avoid_: Counting provider handoffs as failed repairs or using a handoff to reset a failed work item's allowance.


**Integration cadence**:
The selected boundary for combining verified work into the run's shared working branch. It defaults to milestones; repeated friction may prompt an offer to switch to task-level batches, with the user's agreement.
_Avoid_: Silently changing cadence or treating branch integration as permission to merge the base branch or deploy.

**Credential-cycling gate**:
The requirement to verify the agreed cycling pass before base-branch merging or final run completion after approved secret exposure. Local work and secret-free review PRs may continue while the obligation remains pending.
_Avoid_: Presenting accepted code as evidence that credential cleanup has completed.


**Harness candidate**:
A proposed version of a harness recipe, linked to its parent version, a specific improvement hypothesis, and comparison evidence. It is not an adopted default merely because it fixes the failure that motivated it.
_Avoid_: Letting a candidate redefine its own acceptance criteria or treating an anecdote as sufficient adoption evidence.

**Harness adoption**:
Selection of a qualifying recipe version for future work at the next authorized boundary, with evidence, scope, and version history retained. Active workers keep their recorded version; task-family-specific improvements need not become global defaults.
_Avoid_: Hot-changing active workers or treating recipe adoption as permission to merge runtime code, expand authority, or continue beyond a stop.

**Self-improvement agent**:
The agent dedicated exclusively to improving the swarm and its harnesses while the self-improvement feature is enabled.
_Avoid_: Assigning it ordinary delivery work.

**Milestone closeout**:
The wrap-up that follows evidence that a milestone's code reached `main`: a short efficiency retrospective, failure and collision accounting, preserved and cleaned-up associated worktrees, and the Four-T scorecard. Run by the self-improvement agent while the self-improvement toggle is on; a closeout that cannot finish stays pending and resumes under valid authority.
_Avoid_: Triggering it from an agent's claim of completion, repeating completed closeout actions after a restart, or reading it as permission to delete work.

**Four-T scorecard**:
The standard milestone measures: Tokens, Time, Toil and Trouble, each reported with its source and coverage. Unavailable values are unknown.
_Avoid_: Treating a missing measurement as zero trouble or zero human effort, or drawing a universal cross-model efficiency claim from the figures.

**Self-improvement toggle**:
The single project-level on/off choice for the self-improvement agent and its milestone closeout. Enabled by default; disabling schedules none of that feature's work.
_Avoid_: Treating disabling it as permission to discard unfinished work, interrupt a preservation unsafely, or clear a pending recovery obligation.

**Recovery branch**:
The ordinary local branch that keeps a closed-out worktree's unfinished work visible for focused follow-up, existing or newly created, with uncommitted and untracked work snapshotted onto it before the worktree is removed.
_Avoid_: Assuming a branch reference alone preserves uncommitted files, or removing the worktree before the transfer is verified.

**Improvement gate**:
The per-candidate check for adopting a harness candidate. Before evaluation it fixes a measurable Four-T target, quality requirements and the task family; the candidate is then compared with the current recipe on the motivating problem and on separate regression checks, at least twice, with independent review and all improvement overhead counted. Only a candidate that meets its target without breaking quality or authority boundaries is adopted; an inconclusive result keeps the current recipe.
_Avoid_: Letting a candidate alter its own target or grading, accepting a passing project suite as evidence of the target, or treating adoption as permission to merge runtime code.
