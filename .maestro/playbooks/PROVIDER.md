# Detected Provider

- **Provider (Maestro toolType)**: opencode
- **Confidence**: high
- **Detected on**: 2026-10-10

## Signals

### Self-identification
Agent self-identifies as OpenCode (certain — introspective, no files checked); canonical Maestro toolType: `opencode`.

### PATH probe
- `claude`: `/Users/hinchk/.local/bin/claude`
- `codex`: `/opt/homebrew/bin/codex`
- `opencode`: `/opt/homebrew/bin/opencode`
- `droid`: `not-found`
- `copilot`: `not-found`
- `gemini`: `/opt/homebrew/bin/gemini`
- `qwen`: `not-found`

## Reconciliation Notes
Self-identification (`opencode`) is authoritative and is corroborated by the PATH probe — the `opencode` binary is present at `/opt/homebrew/bin/opencode`. Additional harnesses (`claude`, `codex`, `gemini`) are installed on this machine, which is expected on a multi-harness setup and does not contradict the introspective result. Confidence remains high; nothing would need to raise it.

## Supported by Superpowers?
yes
