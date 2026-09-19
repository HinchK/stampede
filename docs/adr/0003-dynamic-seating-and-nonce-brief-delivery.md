# ADR 0003: Dynamic Seating from TOML Registry and Nonce Brief Delivery Protocol

- **Status**: Accepted
- **Date**: 2026-09-19
- **Deciders**: `arch`, `pm`, `looper`
- **Consulted**: [T-001](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/findings/herdr-semantics.md), [T-003](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/toml-configuration-schema-and-shell-binding.md), [T-006](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/brief-templating-syntax-and-nonce-file-protocol.md), [T-INT-2](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/integrate-config-and-briefs-into-launcher.md)

---

## 1. Context and Problem Statement

The original swarm launcher (`herdr-loop-swarm.sh`) suffered from tightly coupled seat configuration and an unreliable brief dispatch mechanism:

1. **Hardcoded Seating Matrix**: The launcher hardcoded seats (`arch`, `looper`, `pm`, `docs`, `gh`, `reviewer`), agent runtime kinds (`opencode`, `agy`, `claude`), and model identifiers directly into shell script arrays. Changing agent models or enabling optional seats required modifying launcher code directly.
2. **Global Agent Name Collisions**: Empirical research ([`docs/findings/herdr-semantics.md`](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/findings/herdr-semantics.md)) confirmed that Herdr agent names occupy a **single, server-global registry**. Attempting to run swarms concurrently in two different directories failed because `arch` or `looper` was already registered. Moreover, Herdr agent names strictly enforce the grammar `^[a-z][a-z0-9_-]*$`; proposed naming schemes using unicode middle dots (e.g. `arch·slug`) are rejected with `invalid_agent_name`.
3. **Terminal Input Buffer Overflow**: Standing briefs are 3–10 KB markdown documents. The legacy launcher dumped raw brief text directly into the agent prompt interface:
   ```bash
   # DANGEROUS: Floods terminal buffer
   herdr agent prompt "$seat" "$(cat "$brief_file")"
   ```
   In PTY/terminal environments, large text injections trigger buffer overflows, character truncation, escape-sequence mangling, and partial command execution. Furthermore, `herdr agent prompt` often deposited text in the input area without submitting it, leaving agents frozen.

---

## 2. Decision Drivers

- **Declarative Configuration**: Swarm topology, agent kinds, models, and seats must be defined declaratively in an editable configuration file (`swarm.config.toml`).
- **Multi-Swarm Concurrency**: Multiple swarms must run concurrently on the same machine without agent name collisions.
- **Reliable Brief Delivery**: Briefs must be delivered to agents 100% reliably without risking PTY buffer saturation or character drop.
- **Dynamic Context Injection**: Standing briefs must reflect the current repository name, test command, and peers' actual namespaced identities.

---

## 3. Considered Options

- **Option A (Static Shell Script Arrays & In-line Prompts)**: Maintain seat arrays in bash and chunk prompts into smaller pieces. (High maintenance, still vulnerable to terminal race conditions).
- **Option B (Environment Variable Injection)**: Export briefs as environment variables when spawning panes. (Incompatible with persistent panes and diverse agent CLI runners like `claude` and `agy`).
- **Option C (TOML Registry, Slug Namespacing, and Nonce File Delivery)**: Parse `swarm.config.toml` dynamically, namespace seats as `seat-<slug>`, pre-render briefs to disk, and deliver a compact pointer (<200 bytes) referencing the file path.

---

## 4. Decision

We adopted **Option C**. We implemented dynamic seating, safe slug namespacing, and the **Nonce Brief Delivery Protocol**:

### A. Centralized TOML Registry (`swarm.config.toml` & `lib/config.sh`)
- `swarm.config.toml` acts as the single source of truth for seats, tiers, models, and swarm parameters.
- `lib/config.sh` parses TOML using standard Python 3 `tomllib` (Python 3.11+) and binds configuration to shell arrays via safe argument passing (`sys.argv` and `shlex.quote`), preventing shell evaluation bugs.
- Dynamic seating evaluates `SEAT_KEYS` exported by `config_dump_env`, completely removing hardcoded seat calls.

### B. Safe Slug Namespacing (`seat-<slug>`)
- Agent names are namespaced per project:
  ```
  <seat>-<slug>
  ```
  Example: `arch-kultivait`, `pm-kultivait`, `looper-loop-bot-herd-agy`.
- The slug is generated via `slugify()` in `lib/common.sh`:
  - Lowercases input: `A-Z` $\to$ `a-z`.
  - Replaces non-alphanumeric characters with `-`.
  - Prepends `s-` if the string begins with a number (enforcing `^[a-z]`).
  - Truncates to 32 characters.

### C. Templated Brief Rendering (`lib/briefs.sh`)
- Templates live in `briefs/*.in.md` containing placeholder tokens: `{{REPO}}`, `{{TEST_CMD}}`, `{{PROJECT_SLUG}}`, `{{ARCH_AGENT}}`, `{{LOOPER_AGENT}}`, etc.
- At swarm launch, `render_all_briefs` renders templates into `.herdr-swarm/briefs/<seat>.md` for the specific target repository and seated identities.

### D. Nonce Brief Delivery Protocol (`deliver_brief_nonce`)
Instead of injecting massive prompt strings, [`lib/briefs.sh`](file:///Users/hinchk/Fun/loop-bot-herd-agy/lib/briefs.sh) dispatches a compact (<200 bytes) reference prompt:

```bash
deliver_brief_nonce() {
  local seat_name="$1"
  local brief_path="$2"

  # 1. Wait until agent runtime is idle
  herdr agent wait "$seat_name" --until idle --timeout 15000 >/dev/null 2>&1 || true

  # 2. Deliver compact reference prompt (<200 bytes, buffer safe)
  local prompt_msg="STANDING BRIEF: You are seated as '${seat_name}'. Your standing brief is rendered at '${brief_path}'. Read it immediately using your file viewing tools and adopt this posture. Acknowledge when ready."
  herdr agent prompt "$seat_name" "$prompt_msg" >/dev/null 2>&1 || true

  # 3. Explicit submission confirmation
  sleep 1
  herdr agent send-keys "$seat_name" enter >/dev/null 2>&1 || true
}
```

This ensures the terminal buffer receives only a single clean instruction line. The agent then reads the full rendered brief directly from disk using its native file viewing tools (`view_file`, `cat`, etc.).

---

## 5. Consequences

### Positive
- **Immune to Buffer Overflow**: Eliminates PTY truncation, escape corruption, and dropped prompts during brief distribution.
- **Deterministic Prompt Submission**: The `sleep 1 && herdr agent send-keys <name> enter` pattern guarantees prompts are submitted rather than stranded in the prompt input field.
- **Concurrent Swarm Execution**: Distinct project repositories can run swarms side-by-side without agent name collisions in Herdr.
- **Configurability**: Adding a seat or updating a model requires editing only `swarm.config.toml`.

### Negative / Trade-offs
- **File System Prerequisite**: Worker agents must possess file-reading capabilities. (Satisfied by all supported LLM agents: `agy`, `claude`, `opencode`).
- **Disk Footprint**: Rendered briefs occupy local disk space in `.herdr-swarm/briefs/` (typically <50 KB total per project).
