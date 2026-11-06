# Evaluating an evolving Stampede swarm

Date: 2026-11-06. Research for **Establish credible methods for evaluating an evolving swarm**. This note supplies evidence and candidate methods; it does not select the user's workload, thresholds, sample size, or budget. No experiment was run.

## What the evidence establishes

- **Harness engineering is supported by experience, not a general causal speedup estimate.** OpenAI describes an internal product built with agent-generated code and estimates one-tenth of manual development time. There is no randomized single-agent versus swarm comparison in that account. Its practical lessons concern executable constraints, accessible application behavior, repository knowledge, and feedback. Treat the reported speedup as a case-study estimate. [OpenAI, Harness engineering](https://openai.com/index/harness-engineering/)
- **Continuity is an evaluation target.** Anthropic's long-running harness work reports premature completion and poor handoffs, then uses incremental features, progress artifacts, Git history, and user-flow testing. The article explicitly leaves whether a single generalist or specialized multi-agent architecture performs better unresolved. It supports testing restart and continuation behavior, not assuming replication solves it. [Anthropic, Effective harnesses](https://www.anthropic.com/research/effective-harnesses-for-long-running-agents)
- **Textual adaptation has controlled, task-specific evidence.** GEPA compares prompt optimization methods using Qwen3-8B and GPT-4.1-Mini, standardized inference settings, and train/validation/test separation. Training content is available to optimization; validation scores support selection; validation-instance content is restricted. Its positive results concern particular reasoning, retrieval, instruction-following, and code-optimization settings. They do not establish that an evolving software-development swarm beats a strong coding agent across projects. [GEPA v2, section 4 and appendices](https://arxiv.org/html/2507.19457v2)
- **Small-model advocacy is not universal proof.** Belcak and colleagues explicitly present a position that specialized agent invocations suit smaller models and heterogeneous systems. This motivates testing the hypothesis; the position itself does not resolve Stampede's quality, coordination, or subscription economics. Model size, lower price, and a narrowly scoped assignment must be distinguished. [Small Language Models are the Future of Agentic AI](https://arxiv.org/abs/2506.02153v3)
- **Observed work matters more than perceived productivity.** METR's early-2025 randomized study used 16 experienced developers and 246 real issues; observed completion time increased despite participants believing AI helped. This is a historical result for that population and tool generation, not a current claim about Stampede. It motivates recording human effort rather than surveying perceived speed alone. [METR study](https://metr.org/blog/2025-07-10-early-2025-ai-experienced-os-dev-study/)

## Candidate comparison

The following is a proposed design, not an adopted protocol:

| Arm | Comparison purpose |
| --- | --- |
| Strong single agent with a competent fixed harness | Practical baseline; give it the same relevant tools and acceptance information. |
| Swarm with fixed harnesses | Measure the deployed orchestration package. |
| Same swarm with an explicit adaptation phase | Measure the incremental effect of harness evolution. |

Changing models and topology together confounds attribution. Include a same-model single-agent/swarm control, or clearly report the result as a comparison of complete systems. Compare fixed versus evolving arms with the same starting configurations and access to development tasks. Define whether the baseline receives an equal tuning allowance. Record every tuning and selection attempt, including rejected candidates.

Freeze a separate final test set. Split by project or task family when near-duplicate issues could leak solutions. Keep evaluator fixtures and final answers outside worker access. Development feedback may improve candidates; final test feedback must not feed the same reported selection cycle. Version candidate configurations and the independent evaluator separately. These recommendations extend GEPA's split discipline to software work; they are not findings that Stampede already implements. [GEPA methodology](https://arxiv.org/html/2507.19457v2)

## Measurement and failure controls

Anthropic recommends grading outcomes, combining deterministic checks with calibrated model/human judgment, isolating trials, and repeating runs. It distinguishes success at least once in several attempts from success consistently across attempts. Git history or cached artifacts from previous trials can leak solutions. [Anthropic, Demystifying evals](https://www.anthropic.com/research/demystifying-evals-for-ai-agents)

For Stampede, predeclare:

- **Quality:** independently accepted functionality, preserved behavior, integration success, defects found in a fixed follow-up window, and rework. An agent's completion claim is not the outcome.
- **Efficiency:** end-to-end elapsed time and active human minutes for setup, steering, review, repair, and recovery. Count all workers, evaluators, retries, and adaptation work. Report API charges, observable subscription consumption, and unknown quota separately; tokens are not interchangeable dollars across providers.
- **Reliability:** repeated runs from clean snapshots, task-level results and uncertainty, timeouts and abandoned attempts retained in the denominator. Randomize or balance run order; avoid one engineer's learned solution contaminating later human-assisted trials.
- **Long horizon:** planned session resets, provider interruption, checkpoint continuation, and combined-branch testing. Preserve legitimate project history within a trial while isolating histories between trials.
- **Evaluator integrity:** assess behavior in an independent environment; detect changed acceptance fixtures or disabled checks. Calibrate subjective review against human examples and conceal arm identity where feasible. Prefer outcome evidence over scoring how convincingly agents describe success.

Control and report hardware, resource ceilings, tool versions, model identifiers, and time limits. Anthropic measured a six-point Terminal-Bench difference between infrastructure configurations; this shows that environment changes can rival apparent model improvements. [Infrastructure noise](https://www.anthropic.com/research/infrastructure-noise)

## Decisions still required

HinchK must choose the representative workload, acceptable quality floor, resource envelope, human involvement, adaptation cadence, and sample-size/stopping rationale. Specify which tradeoffs count as useful and how losses will be reported. A small pilot can establish feasibility and expose failure modes; it cannot justify universal superiority or an expertise claim without further evidence.
