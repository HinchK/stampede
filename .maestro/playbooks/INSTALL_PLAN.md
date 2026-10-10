# Install Plan

- **Provider**: opencode
- **Supported**: yes
- **Date**: 2026-10-10

## Prerequisites
- `git`: 2.56.0
- Harness CLI (`opencode`): `/opt/homebrew/bin/opencode` (v1.18.35)
- Provider-specific: OpenCode config: `~/.config/opencode/opencode.json` (exists; already has `"plugin": []` with no superpowers entry)

## Strategy
Document 3 will make exactly one change: edit the global OpenCode config at `~/.config/opencode/opencode.json` — parse the JSON, append `superpowers@git+https://github.com/obra/superpowers.git` to the existing (empty) `plugin` array, and rewrite the file, leaving the `mcp` and `provider` blocks untouched. No version pin (installs floating HEAD so future restarts pick up updates) and no prior-install cleanup (probed on 2026-10-10: no `~/.config/opencode/plugins/superpowers.js`, no `skills/superpowers`, no `~/.config/opencode/superpowers`, and no `skills.paths` key — nothing to clean). After the edit, the user must restart their OpenCode session for the plugin to load; document 4 then verifies installation via the log grep and the `Tell me about your superpowers` smoke test.

## Automatable Steps

1. Merge the superpowers plugin entry into the global OpenCode config
   - Action: Edit `~/.config/opencode/opencode.json`: parse the JSON, append `"superpowers@git+https://github.com/obra/superpowers.git"` to the existing `"plugin": []` array, rewrite the file (parse-and-rewrite; never string-replace; leave `mcp` and `provider` blocks unchanged).
   - Expects: the rewritten file re-parses as valid JSON and `plugin` equals exactly `["superpowers@git+https://github.com/obra/superpowers.git"]`.
2. Verify superpowers loads (run by document 4, only after User-Required Step 1)
   - Action: `opencode run --print-logs "hello" 2>&1 | grep -i superpowers`
   - Expects: at least one log line mentioning superpowers (plugin resolution / load); exit status of the grep pipeline is 0. Fallback smoke test in an OpenCode session: `Tell me about your superpowers` → agent describes bundled skills (brainstorming, writing-plans, using-git-worktrees, test-driven-development, etc.).

## User-Required Steps

1. Restart OpenCode
   - Action in harness: quit the running OpenCode session for this Maestro agent (`stampede`) and start it again (or restart the Maestro app). A running OpenCode session will not pick up the config change mid-flight. There is no command to paste — this is a restart action.
   - Expects: the new session starts with the updated config; Automatable Step 2's verification then finds superpowers.

## Skip / Block
None. Provider is supported and every prerequisite is met.
