#!/bin/bash
# session-handoff.sh: switch to a fresh Claude Code session cheaply instead of carrying a long context.
#   --show         print what a new session should read: ONLY the newest START HERE block of HANDOFF.md and the last
#                  lines of STATUS.md (never the whole files).
#   --due [idle]   exit 0 when a switch is now cheaper than carrying on (computed from this session's transcript);
#                  "idle" = before a wait longer than the prompt cache lifetime, a much lower limit.
#   (no argument)  after Claude updated both files: check they are fresh, print the continue prompt and copy it to the
#                  clipboard. Then type /clear and paste.
#   --go           macOS only: the same check, then a NEW session opens in a new Terminal window with the prompt and
#                  this session is closed after CLOSE_AFTER seconds. Background agents of this session die with it.
# Settings (environment): HANDOFF_FILE, STATUS_FILE (default: HANDOFF.md, STATUS.md in the project folder),
#   MAX_AGE_MIN (20), STATUS_LINES (6), CLOSE_AFTER (30), and for --due: RESTART_EXTRA, GROWTH_DEFAULT, IDLE_MARGIN,
#   DUE_MAX, DUE_TOKENS, CACHE_READ (0.1), CACHE_WRITE (1.25).
set -u
D=${CLAUDE_PROJECT_DIR:-$PWD}; H=${HANDOFF_FILE:-$D/HANDOFF.md}; S=${STATUS_FILE:-$D/STATUS.md}
SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
MAX_AGE_MIN=${MAX_AGE_MIN:-20}; STATUS_LINES=${STATUS_LINES:-6}
PROMPT="Continue the work in $D. Run: bash \"$SELF\" --show   and read its output (the newest START HERE block of $(basename "$H") and the last $(basename "$S") lines). Do NOT read those two files whole. Then carry on with the next steps listed there."

if [ "${1:-}" = --due ]; then
  # Every call re-reads the whole context at the cache-read price (CACHE_READ x input). A switch costs
  #   S = CACHE_WRITE x B + RESTART_EXTRA   (B = the context after the start-up reads, taken at call 10; RESTART_EXTRA =
  #   writing the handoff and re-reading what the old session knew; raise it to switch less often).
  # With the context growing g tokens per call, the cost per call is lowest when the switch comes at
  #   B + sqrt(2 x S x g / CACHE_READ)
  command -v jq >/dev/null || { echo "not due: jq is not installed"; exit 1; }
  dir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$(printf %s "$D" | sed 's/[^A-Za-z0-9]/-/g')
  t=$(ls -t "$dir"/*.jsonl 2>/dev/null | head -1)
  [ -n "$t" ] || { echo "not due: no transcript in $dir"; exit 1; }
  r=$(jq -c 'select(.message.usage and .message.id) | [.message.id, (.message.usage | .input_tokens + .cache_read_input_tokens + .cache_creation_input_tokens)]' "$t" 2>/dev/null |
    jq -rs --argjson extra "${RESTART_EXTRA:-80000}" --argjson g0 "${GROWTH_DEFAULT:-1500}" --argjson cap "${DUE_MAX:-250000}" \
      --argjson rd "${CACHE_READ:-0.1}" --argjson wr "${CACHE_WRITE:-1.25}" '
      (reduce .[] as $x ([]; if length > 0 and .[-1][0] == $x[0] then .[-1] = $x else . + [$x] end) | map(.[1])) as $c
      | ($c | length) as $n | if $n == 0 then empty else
        $c[([$n, 10] | min) - 1] as $B | $c[-1] as $ctx
        | (if $n >= 30 then ([($ctx - $B) / ($n - 10), 300] | max) else $g0 end) as $g
        | ($wr * $B + $extra) as $S
        | "\($ctx) \([$B + (2 * $S * $g / $rd | sqrt), $cap] | min | floor) \($B) \($g | floor) \($n)" end')
  [ -n "$r" ] || { echo "not due: no usage found in $t"; exit 1; }
  # shellcheck disable=SC2086
  set -- "$1" "${2:-}" $r; ctx=$3; limit=$4; B=$5
  [ "$2" = idle ] && limit=$((B + ${IDLE_MARGIN:-60000}))
  [ -n "${DUE_TOKENS:-}" ] && limit=$DUE_TOKENS
  info="context $ctx, limit $limit (start $B, growth $6/call, $7 calls${2:+, $2})"
  [ "$ctx" -ge "$limit" ] && { echo "DUE: $info"; exit 0; }
  echo "not due: $info"; exit 1
fi
if [ "${1:-}" = --show ]; then
  first=$(grep -n -m1 'START HERE' "$H" 2>/dev/null | cut -d: -f1)
  [ -n "$first" ] || { echo "session-handoff: no START HERE block in $H" >&2; exit 1; }
  echo "== $(basename "$H"): newest START HERE block (line $first) =="
  awk -v s="$first" 'NR >= s { if ($0 == "" && NR > s) exit; print }' "$H"
  echo; echo "== $(basename "$S"): last $STATUS_LINES lines =="
  tail -n "$STATUS_LINES" "$S" 2>/dev/null | cut -c1-700
  exit 0
fi

mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }   # BSD, then GNU
now=$(date +%s); stale=""
for f in "$H" "$S"; do
  age=$(( (now - $(mtime "$f")) / 60 ))
  [ "$age" -le "$MAX_AGE_MIN" ] || stale="$stale $(basename "$f") (${age} min old)"
done
[ -z "$stale" ] || { echo "session-handoff: NOT ready: update first:$stale (limit ${MAX_AGE_MIN} min)" >&2; exit 1; }
size=$(bash "$SELF" --show | wc -c | tr -d ' ')
[ "$size" -gt 0 ] || exit 1
clip=""; for c in pbcopy wl-copy "xclip -selection clipboard" clip.exe; do command -v ${c%% *} >/dev/null && { clip=$c; break; }; done
echo "Ready: the new session will read $size bytes (~$((size / 4)) tokens) instead of the whole files."
if [ "${1:-}" != --go ]; then
  if [ -n "$clip" ] && printf '%s' "$PROMPT" | $clip; then echo "The continue prompt is on the clipboard. Type /clear and paste it."
  else echo "Type /clear and paste this prompt:"; fi
  echo; echo "$PROMPT"; exit 0
fi
# --go: a NEW session in a new Terminal window (a fresh context is the clear), then this session is closed.
# Extra flags for the new session are the USER's to set (first non-comment line of .claude/session-handoff.conf,
# e.g. --permission-mode acceptEdits): Claude never picks its own permission mode.
[ "$(uname)" = Darwin ] || { echo "session-handoff: --go needs macOS Terminal; run without --go, then /clear and paste" >&2; exit 1; }
case $D in *[\"\\\$\`]*) echo "session-handoff: --go refuses a project path with quotes, \$ or backslashes" >&2; exit 1 ;; esac
CONF=$D/.claude/session-handoff.conf; ARGS=$( [ -f "$CONF" ] && grep -v '^#' "$CONF" | head -1 | tr -cd 'A-Za-z0-9 _=.,:/-' )
P=$(mktemp "${TMPDIR:-/tmp}/session-handoff.XXXXXX"); printf '%s' "$PROMPT" > "$P"
old=$PPID; while [ "$old" -gt 1 ] && [ "$(basename "$(ps -o comm= -p "$old")" 2>/dev/null)" != claude ]; do old=$(ps -o ppid= -p "$old" | tr -d ' '); done
osascript -e "tell application \"Terminal\" to do script \"cd '$D' && claude $ARGS \\\"\$(cat '$P')\\\"\"" >/dev/null ||
  { echo "session-handoff: could not open a Terminal window" >&2; exit 1; }
echo "New session opened in a new Terminal window${ARGS:+ (flags: $ARGS)}."
if [ "${old:-0}" -gt 1 ]; then
  echo "This session (pid $old) closes in ${CLOSE_AFTER:-30} s."
  nohup sh -c "sleep ${CLOSE_AFTER:-30}; kill $old" >/dev/null 2>&1 &
fi
