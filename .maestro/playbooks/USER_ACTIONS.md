# User Actions Required

> **RESOLVED (2026-10-10)** — verification in `VERIFY.md` found Superpowers INSTALLED-AND-ACTIVE. The restart
> step below is already satisfied (sessions started after the config edit load the plugin). Nothing left to do;
> this file is kept for the record.

Superpowers cannot finish installing without these interactive steps. Run them in your **opencode** session in this order.

## Steps

1. Restart OpenCode — quit the running OpenCode session for this Maestro agent (`stampede`) and start it again (or restart the Maestro app). A running session will not pick up the config change mid-flight.

   ```text
   (no command to paste — this is a restart action)
   ```

   Expected result: the new session starts with the updated config and superpowers loads at startup.

## Verification

After completing the steps above, run this in your **opencode** session:

```text
Tell me about your superpowers
```

The agent should respond with a description of the bundled skills (brainstorming, writing-plans, using-git-worktrees, test-driven-development, etc.).
