# session-handoff

A Claude Code plugin that cuts the cost of long tasks.

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
| `session-handoff.sh --show` | Prints what the new session reads: the newest START HERE block and the last status lines |
| `session-handoff.sh --due [idle]` | Exit 0 when a switch is now cheaper than carrying on |
| `session-handoff.sh --go` | macOS: opens the new session in a new Terminal window and closes the old one |

To let Claude decide by itself when to switch, add to your `CLAUDE.md`:

```
After every chunk of work append a bullet to STATUS.md. At clean points (no background agent running) run
`session-handoff.sh --due`; when it says DUE, run /handoff. Never read HANDOFF.md or STATUS.md whole.
```

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
- `--go` works with macOS Terminal only.

MIT license.
