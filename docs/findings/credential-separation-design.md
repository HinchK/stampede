# Research: Credential Separation for Agent Seats Under GitHub Architecture

**Ticket:** `maps/tickets/cred-1-credential-separation-research.md`  
**Date:** 2026-09-27  
**Author:** `agy-gh-hinchk-stampede` (Gemini Flash)  
**Status:** Complete (Research Only)  

---

## 1. Executive Summary

This investigation evaluates whether agent seats in the Herdr swarm (`arch-1`, `arch-2`, `looper`, `pm`, `agy-gh`, `agy-docs`, `reviewer`) can be provisioned with a `git`/`gh` credential that **structurally cannot push to `main`**, regardless of what prompt instructions, vendor hallucinations, or local script modifications an agent makes.

### Core Findings

1. **No credential in GitHub's architecture can restrict push access to a specific branch on its own.**  
   Across all four credential mechanisms evaluated—Fine-Grained Personal Access Tokens (PATs), GitHub App installation tokens, dedicated machine-user collaborator accounts, and SSH deploy keys—Git push authorization on GitHub is **strictly repository-scoped**. GitHub credentials grant permission to write to repository contents; they contain zero ref-matching or branch-filtering logic.
2. **Branch-level push restriction is exclusively a server-side repository feature.**  
   Restricting pushes to a specific branch (e.g. blocking `main` while allowing `worktree/*` or feature branches) requires **Branch Protection Rules** or **Repository Rulesets** enforced by GitHub's Git server.
3. **Visibility and Plan Status: The 2026-09-23 blocker is resolved under current visibility.**  
   On 2026-09-23, `docs/audits/2026-09-23-harden-the-promote-gate.md` found that branch protection was blocked on `HinchK/stampede` with HTTP 403 (*"Upgrade to GitHub Pro or make this repository public to enable this feature"*).  
   **Empirical verification on 2026-09-27 confirms `HinchK/stampede` is currently a PUBLIC repository.** On public repositories, GitHub Free provides full access to Branch Protection Rules and Repository Rulesets at $0/month.
4. **Achievability:**  
   - **Under current PUBLIC visibility:** Real structural credential separation **is achievable today** on GitHub Free. It requires pairing a dedicated agent credential (a machine-user PAT or GitHub App token) with a server-side branch protection rule or ruleset on `main` that permits pushes only by the human driver (`HinchK`).
   - **If visibility reverts to PRIVATE:** Real structural credential separation **is not achievable** without upgrading the account to **GitHub Pro** ($4/month), as branch protection on private repositories remains hard-gated behind paid plans.

---

## 2. Evaluation of the Four Credential Mechanisms

The central technical question is: *Does the credential mechanism support restricting push access to a specific branch without branch protection rules?*

```
+------------------------------------+------------------+-----------------------------+
| Mechanism                          | Permission Scope | Branch-Level Push Restrict? |
|                                    |                  | (Without Branch Protection) |
+------------------------------------+------------------+-----------------------------+
| 1. Fine-Grained PAT                | Repository-level | NO                          |
| 2. GitHub App Installation Token   | Repository-level | NO                          |
| 3. Machine User Collaborator       | Repository-level | NO                          |
| 4. SSH Deploy Key                  | Repository-level | NO                          |
+------------------------------------+------------------+-----------------------------+
```

### 2.1 Fine-Grained Personal Access Tokens (PATs)

- **Official Documentation:** [Managing your personal access tokens — Fine-grained personal access tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#fine-grained-personal-access-tokens)
- **Architecture & Capabilities:** Fine-grained PATs improve upon classic tokens by allowing users to scope tokens to specific repositories (e.g., only `HinchK/stampede`) and specific REST API / Git resource permissions. Pushing git commits requires the `Repository permissions -> Contents: Read and write` scope.
- **Can it restrict push access to a specific branch without branch protection?**  
  **NO.** The `Contents` permission is an all-or-nothing grant across all Git references (`refs/heads/*`, `refs/tags/*`). There is no branch pattern selector in the fine-grained PAT configuration. Once granted `Contents: Read and write`, the token can push commits to `refs/heads/main` identically to any other branch unless a server-side branch protection rule or ruleset rejects the push.

### 2.2 GitHub App Installation Access Tokens

- **Official Documentation:** [Authenticating as a GitHub App installation](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-as-a-github-app-installation) and [REST API: Create an installation access token](https://docs.github.com/en/rest/apps/apps#create-an-installation-access-token-for-an-app).
- **Architecture & Capabilities:** A GitHub App can be installed on selected repositories and generate ephemeral installation access tokens (1-hour TTL) with fine-grained permission sets (e.g., `contents: write`, `issues: write`, `pull_requests: write`).
- **Can it restrict push access to a specific branch without branch protection?**  
  **NO.** Similar to fine-grained PATs, the `contents: write` permission is repository-wide. When calling `POST /app/installations/{installation_id}/access_tokens`, the API accepts repository IDs and a subset of the App's permissions, but accepts no branch filters. An installation token with `contents: write` can update any branch in the repository.  
  *(Note: Omitting `contents: write` and granting only `pull_requests: write` prevents pushing to `main`, but also prevents pushing feature or worktree branches to the remote, breaking worker seats that need to push remote branches for PR workflows).*

### 2.3 Dedicated Machine-User Account with Restricted Collaborator Permissions

- **Official Documentation:** [Inviting collaborators to a personal repository](https://docs.github.com/en/account-and-profile/setting-up-and-managing-your-personal-account-on-github/managing-access-to-your-personal-repositories/inviting-collaborators-to-a-personal-repository) and [About custom repository roles](https://docs.github.com/en/organizations/managing-user-access-to-your-organizations-repositories/managing-repository-roles/about-custom-repository-roles).
- **Architecture & Capabilities:** A secondary GitHub user account (e.g., `stampede-agent`) is created and invited as a collaborator to `HinchK/stampede`.
- **Can it restrict push access to a specific branch without branch protection?**  
  **NO.** On personal user accounts (as opposed to GitHub Enterprise Cloud organizations), collaborator permissions are binary: collaborators have direct Read/Write access across the entire repository. GitHub does not support custom repository roles or branch-level collaborator ACLs on personal accounts. A collaborator with write access can push directly to `main` unless prevented by branch protection rules.

### 2.4 SSH Deploy Keys

- **Official Documentation:** [Managing deploy keys](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys#deploy-keys).
- **Architecture & Capabilities:** SSH public keys configured directly on a repository under `Settings -> Deploy keys`. Deploy keys have a single access configuration: a checkbox for "Allow write access".
- **Can it restrict push access to a specific branch without branch protection?**  
  **NO.** As stated in GitHub's official documentation: *"A deploy key with write access has the same access as a collaborator with write access to the repository."* Deploy keys operate at the SSH transport layer for the entire repository. They possess zero ref-level awareness and cannot restrict pushes to specific branches.

---

## 3. Plan & Visibility Reality: 2026-09-23 vs. 2026-09-27

### 3.1 What was found on 2026-09-23

In [`docs/audits/2026-09-23-harden-the-promote-gate.md`](file:///Users/hinchk/Fun/stampede/docs/audits/2026-09-23-harden-the-promote-gate.md), the PM audit probed GitHub branch protection:
```bash
$ gh api repos/HinchK/stampede/branches/main/protection
{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.", "status":"403"}
$ gh api repos/HinchK/stampede/rulesets
{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.", "status":"403"}
```
At that time, `HinchK/stampede` was a **private repository** on the **GitHub Free** plan. Branch protection and rulesets were hard-blocked by GitHub's pricing tier.

### 3.2 Empirical Verification on 2026-09-27

Probing the GitHub API today shows the repository state has changed:
```bash
$ gh repo view HinchK/stampede --json isPrivate,visibility,viewerPermission
{
  "isPrivate": false,
  "owner": { "id": "MDQ6VXNlcjE1MDk0NTY=", "login": "HinchK" },
  "viewerPermission": "ADMIN",
  "visibility": "PUBLIC"
}

$ gh api repos/HinchK/stampede/branches/main/protection
gh: Branch not protected (HTTP 404)

$ gh api repos/HinchK/stampede/rulesets
[]
```

- **HTTP 404 on branch protection** (instead of HTTP 403) confirms that branch protection is **fully enabled and available** on the repository; there is simply no rule configured yet on `main`.
- **HTTP 200 with an empty list `[]` on rulesets** confirms that repository rulesets are likewise **fully available**.

### 3.3 GitHub Pricing Tier Matrix for Branch Protection & Rulesets

- **Public Repositories:** Free on all plans (GitHub Free, Free for Organizations, Pro, Team, Enterprise).
- **Private Repositories:** Requires GitHub Pro ($4/mo for personal accounts), GitHub Team ($4/user/mo), or GitHub Enterprise.

*(Citations: [GitHub Docs: About protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/defining-the-mergeability-of-pull-requests/about-protected-branches), [GitHub Docs: About rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets)).*

---

## 4. The Structural Credential Separation Architecture

Because credentials alone cannot restrict branches, true structural separation requires two interlocking layers:

```
[ Agent Seat ]                     [ Human Driver ]
   (PAT: stampede-agent)              (PAT: HinchK)
         │                                  │
         │ git push origin main             │ git push origin main
         ▼                                  ▼
┌─────────────────────────────────────────────────────────────┐
│                 GitHub Server (HinchK/stampede)             │
│                                                             │
│  Branch Protection / Ruleset on refs/heads/main:            │
│  - Restrict updates: Allowed actors = [ HinchK ]            │
│                                                             │
│   Actor == stampede-agent? ───► REJECT (GH006 error)       │
│   Actor == HinchK?         ───► ALLOW                      │
└─────────────────────────────────────────────────────────────┘
```

### Why Both Layers Are Required

1. **The Server-Side Gate without Credential Separation is Flawed:**  
   If all agents and the human share `HinchK`'s credential (the status quo), then protecting `main` and allowing `HinchK` to push allows any agent carrying `HinchK`'s credential to push as well. Conversely, blocking all direct pushes to `main` blocks the human driver from running the promote command locally.
2. **The Credential Separation without the Server-Side Gate is Useless:**  
   As proven in Section 2, issuing a separate token to agents without a branch protection rule leaves `main` completely open to direct pushes by that token.
3. **Together, They Are Structurally Airtight:**  
   - Agent seats hold credential `TOKEN_AGENT` belonging to machine user `stampede-agent`.
   - The repository configures a Branch Protection Rule or Ruleset on `main` restricting pushes exclusively to `HinchK`.
   - Any push to `main` using `TOKEN_AGENT` is rejected at the Git transport level by GitHub (`remote: error: GH006: Protected branch update failed for refs/heads/main`).
   - Pushes to other branches (e.g. `worktree/*`) by `TOKEN_AGENT` succeed.
   - The human driver retains `HinchK` credentials on their personal terminal, preserving sovereign human promote capability.

---

## 5. Evaluation of Agent Credential Options for Layer 2

If branch protection on `main` is enabled, which agent credential mechanism is best?

### Option A: Dedicated Machine-User Account (Recommended)
- **How it works:** A secondary GitHub user account (`stampede-agent`) is created and added as a collaborator to `HinchK/stampede` with Write permissions. A Fine-Grained PAT (or classic `repo`-scoped PAT) is generated for that user and provided to the swarm.
- **Pros:**
  - Standard Git/HTTPS authentication: works transparently with `git push`, `gh issue`, `gh pr`.
  - Zero local daemon or server requirements.
  - Commits pushed by the agent are clearly attributed to `stampede-agent` in GitHub's audit trail.
  - Fail-closed: GitHub's server blocks `stampede-agent` from pushing to `main` while allowing `HinchK`.
- **Cons:**
  - Requires maintaining a second GitHub user account (email address and credentials).

### Option B: GitHub App
- **How it works:** A GitHub App is registered under `HinchK` and installed into `HinchK/stampede`. A script or daemon uses the App's private key to generate short-lived installation tokens.
- **Pros:**
  - First-class machine identity; no separate user email account needed.
  - Tokens expire automatically after 1 hour.
- **Cons:**
  - Token minting overhead: requires managing a private key (`.pem`), computing RS256 JWTs, and calling the GitHub REST API to refresh tokens every hour.
  - Adds runtime complexity to local agent shells and git credential helpers.

**Recommendation:** A dedicated machine-user account with a personal access token is far simpler to integrate into the existing local Herdr environment while providing identical structural security.

---

## 6. What Implementation Would Require (Follow-Up Scope)

Per `HEADLESS-2` precedent, this document is research only and does not modify code or implement configurations. If the driver chooses to proceed, the implementation requirements for a follow-up ticket would be:

1. **Policy Confirmation:** Confirm whether `HinchK/stampede` will remain **PUBLIC** or revert to **PRIVATE**.  
   - If public: Proceed on GitHub Free.
   - If private: Upgrade repository owner account to GitHub Pro ($4/month).
2. **Configure Branch Rule on `main`:**  
   Configure a GitHub Branch Protection Rule or Ruleset for `main`:
   - Enable "Restrict who can push to matching branches".
   - Specify `HinchK` as the only allowed actor (or require PR with `HinchK` as the sole merge authority).
3. **Provision Agent Credential:**  
   - Create machine account (e.g. `stampede-agent`).
   - Invite as repository collaborator on `HinchK/stampede`.
   - Generate token scoped to repository `Contents (write)`, `Pull requests (write)`, `Issues (write)`.
4. **Environment Isolation in Swarm Config:**  
   - Configure Herdr / launcher to inject `GH_TOKEN` / `GITHUB_TOKEN` corresponding to `stampede-agent` into agent panes.
   - Configure Git credential helper in worker worktrees to authenticate pushes with `stampede-agent`.
   - Leave the human driver's primary terminal using `HinchK`'s personal credentials.
5. **Fail-Closed Verification:**  
   - Verify that running `git push origin main` using the agent credential is hard-rejected with HTTP 403 / Git error `GH006`.
   - Verify that running `git push origin worktree/test` using the agent credential succeeds.
   - Verify that running `arbiter_promote --confirm` and push from the human driver terminal succeeds.
