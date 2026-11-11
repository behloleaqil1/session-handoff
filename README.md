# session-handoff

A Claude Code plugin that cuts the cost of long tasks.

**Measured: about 65% lower cost per call.** On the author's project, 21,717 main-session calls without the routine
averaged 442K tokens of context each; 1,685 calls with it averaged 125K. Weighted by price (cache read 0.1, cache
write 1.25, output 5, relative to one input token) that is 50.6K against 17.9K input-token equivalents per call,
switch costs included. One project and different work in the two periods, so read it as an indication, not a benchmark.

Every call in a session re-reads the whole conversation. After a few hours that is hundreds of thousands of tokens per
call, most of it no longer needed. This plugin replaces the long context with a short written handoff:

1. `/handoff` makes Claude write one self-contained "START HERE" paragraph at the top of `HANDOFF.md` and a few
   bullets in `STATUS.md`.
2. You type `/clear` and paste the prompt the script put on your clipboard.
3. The new session reads only that paragraph and the last status lines (about 2 to 4 thousand tokens) and carries on.

## Install

```
/plugin marketplace add behloleaqil1/session-handoff
/plugin install session-handoff@session-handoff
```

Needs `bash`; `jq` for `--due`. The clipboard step uses `pbcopy`, `wl-copy`, `xclip` or `clip.exe` when present,
otherwise the prompt is printed.

## Use

| Command | What it does |
|---|---|
| `/handoff` | Claude writes the handoff, then prepares the switch |
| (automatic) | A hook tells Claude to run `/handoff` once a switch pays |
| `session-handoff.sh --show` | Prints what the new session reads: the newest START HERE block and the last status lines |
| `session-handoff.sh --due [idle]` | Exit 0 when a switch is now cheaper than carrying on |
| `session-handoff.sh --go` | macOS: opens the new session in a new Terminal window and closes the old one |

It is automatic after the install: on every prompt a hook checks, from the session's own transcript, whether a fresh
session has become cheaper than carrying on. Only then it adds one line that tells Claude to finish the current
request and run `/handoff`. Nothing to add to your `CLAUDE.md`. The check needs `jq`; without it the hook does nothing.

## When does a switch pay?

Carrying on costs a cache read of the whole context on every call. A switch costs one cache write of the start-up
context plus the work of writing and re-reading the handoff. With a start-up context of `B` tokens that grows `g`
tokens per call, the cost per call is lowest when you switch at

```
B + sqrt(2 x S x g / 0.1)        S = 1.25 x B + RESTART_EXTRA
```

(0.1 and 1.25 are the cache-read and cache-write prices relative to input). `--due` measures `B` and `g` from the
session's own transcript. Before a wait longer than the cache lifetime the whole context is written again anyway, so
`--due idle` uses a much lower limit (`B + IDLE_MARGIN`).

## Settings

Environment variables: `HANDOFF_FILE`, `STATUS_FILE`, `MAX_AGE_MIN` (20: both files must be this fresh),
`STATUS_LINES` (6), `RESTART_EXTRA` (80000), `IDLE_MARGIN` (60000), `DUE_MAX` (250000), `DUE_TOKENS` (a fixed limit),
`CACHE_READ`, `CACHE_WRITE`, `CLOSE_AFTER` (30).

`--go` passes the first line of `.claude/session-handoff.conf` to the new session as flags (for example a permission
mode). That file is yours to write: Claude does not pick its own permission mode.

## Limits

- A switch ends the session: background agents and tasks of the old session die. `/handoff` refuses to switch while
  one runs.
- The handoff is only as good as the paragraph Claude writes. Read it once before you clear.
- The hook runs on your prompts: a long unattended run gets no reminder until you next type something.
- The last step is yours: type `/clear` and paste (or use `--go` on macOS).
- `--go` works with macOS Terminal only.

MIT license.
