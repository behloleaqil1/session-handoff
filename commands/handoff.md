---
description: Write the handoff (HANDOFF.md, STATUS.md), then prepare a cheap switch to a fresh session
---
Prepare a session switch. Do these in order, with no other work:

1. Collect the facts fresh (do not rely on memory): what is done, what is in progress and where (branch, PR, file), what runs in the background, what waits for the user, the next steps in order.
2. Insert a NEW paragraph at the top of `HANDOFF.md` in the project folder (create the file if missing) that begins `**<date> ~<time>Z, START HERE (supersedes every block below).**` and is SELF-CONTAINED: the new session reads only this block. ONE paragraph with no blank line inside it, under about 900 words: the user's rules still in force, the state of the work, exact commands and paths the next session needs, what is pending with the user, the next steps in order. Leave the older blocks below it untouched.
3. Append 3 to 8 dated one-line bullets to `STATUS.md` (create if missing) for what changed since its last bullet.
4. If a background agent or task of this session is still running, do NOT switch: say which ones and stop here (a switch kills them). Otherwise run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/session-handoff.sh"` and give the user its output: they type `/clear` and paste the prompt. Only when the user asked for an automatic switch (macOS): write one closing line, then as the LAST action run the script with `--go`.

Between switches: run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/session-handoff.sh" --due` at clean points (add `idle` before a wait of over an hour); exit 0 means a switch is now cheaper than carrying on.
