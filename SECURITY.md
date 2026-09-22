# Security Policy

## Reporting a vulnerability

**Please do not report vulnerabilities through public GitHub issues, pull
requests, or discussions.**

Use GitHub's private vulnerability reporting instead:

1. Go to <https://github.com/HinchK/stampede/security/advisories/new>
   (repository → **Security** tab → **Report a vulnerability**).
2. Describe what you found, where, and what an attacker gets from it.

If private advisories are unavailable to you, contact the maintainer through
the contact details on their GitHub profile (<https://github.com/HinchK>) and
ask for a private channel before sending any detail.

A useful report includes:

- the affected file and, where you have it, the commit sha
- what an attacker controls and what they achieve
- a minimal reproduction — a scratch repository and a command line is ideal
- the platform and `bash --version` (behaviour differs between the bash 3.2
  floor and bash 5)

## What to expect

This is a small project maintained on a best-effort basis, so these are
intentions rather than guarantees:

- **Acknowledgement:** within a few business days.
- **Assessment:** an initial severity assessment and a rough plan once the
  report is reproduced.
- **Updates:** as the work progresses, and when a fix ships.
- **Credit:** we are glad to credit you in the advisory and the commit unless
  you would rather stay anonymous.

If you do not hear back, please do follow up — a missed notification is far
more likely than a decision to ignore you.

## Supported versions

There are no releases or tags. `main` is the only supported branch: fixes land
there and nothing older is backported. If you are running a fork or an older
checkout, rebase onto `main` before reporting.

## Scope

In scope — the code in this repository:

- the launcher and supervisor (`herdr-loop-swarm.sh`, `loop-bot-herd.sh`) and
  the libraries in `lib/`
- the integrity of the verification pipeline: a path by which an agent's work
  could be retired as green without the supervisor actually running the test
  suite against that exact commit, or by which a task branch could reach a base
  branch without human action
- shell injection or unsafe interpolation of untrusted input — ticket
  frontmatter, branch and seat names, config values, agent-emitted text — into
  a command, a Python snippet, or a path
- credential handling: anything that writes a token or key into a log, a trace
  under `.herdr-swarm/`, a brief, or a commit

Out of scope:

- vulnerabilities in third-party agent CLIs, model providers, or Herdr itself —
  report those to their maintainers
- the deliberate design choices described below

## This is not a sandbox

Read this before you decide something is a vulnerability.

Stampede executes model-authored code on your machine, in your checkout, with
your credentials, and it drives third-party agent CLIs that do the same. That
is what the tool is for. It is **not** a sandbox, a jail, or a containment
boundary, and it does not try to be one.

Specifically, and by design:

- Agents run as your user, with your filesystem access, your environment, your
  git credentials and your `gh` authentication.
- `make check` — the Suite Gate — runs the target repository's own test command.
  Running Stampede against a repository whose test suite you have not read
  executes that suite's code.
- The test suites stub the agent CLIs and build scratch repositories under
  `/tmp`, so `make check` itself does not invoke a model. Running a swarm does.
- Agents can reach the network through the CLIs they drive.

What Stampede *does* defend is the **integrity of the verdict**: an agent's
claim of "done" is re-verified by an independent supervisor against the exact
commit, integration re-tests the combined result before advancing a ref by
compare-and-swap, and only a human moves a base branch. Those are the security
properties worth reporting a hole in. "An agent could modify files in the
repository it was pointed at" is not a hole — it is the premise.

Run it against a repository you are willing to have rewritten, on a machine
where that is acceptable, and review what lands before you merge it.
