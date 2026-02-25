#!/usr/bin/env bash
#
# Stop hook: keep firing until the agent emits an explicit done signal.
#
# The stop is allowed only after the agent emits:
#   TASKMASTER_DONE::<session_id>
#
# Optional env vars:
#   TASKMASTER_MAX          Max number of blocks before allowing stop (default: 100)
#   TASKMASTER_DONE_PREFIX  Prefix for done token (default: TASKMASTER_DONE)
#
set -u

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path')
if [ -z "$SESSION_ID" ] || [ "$SESSION_ID" = "null" ]; then
  SESSION_ID="unknown-session"
fi

# --- skip subagents: they have very short transcripts ---
if [ -f "$TRANSCRIPT" ]; then
  LINE_COUNT=$(wc -l < "$TRANSCRIPT" 2>/dev/null || echo "0")
  if [ "$LINE_COUNT" -lt 20 ]; then
    exit 0
  fi
fi

# --- counter ---
COUNTER_DIR="${TMPDIR:-/tmp}/taskmaster"
mkdir -p "$COUNTER_DIR"
COUNTER_FILE="${COUNTER_DIR}/${SESSION_ID}"
MAX=${TASKMASTER_MAX:-100}

COUNT=0
if [ -f "$COUNTER_FILE" ]; then
  COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
fi

# --- done signal detection ---
DONE_PREFIX="${TASKMASTER_DONE_PREFIX:-TASKMASTER_DONE}"
DONE_SIGNAL="${DONE_PREFIX}::${SESSION_ID}"
HAS_DONE_SIGNAL=false

# Primary: check last_assistant_message (most reliable — no transcript parsing needed)
LAST_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // ""')
if [ -n "$LAST_MSG" ] && echo "$LAST_MSG" | grep -Fq "$DONE_SIGNAL" 2>/dev/null; then
  HAS_DONE_SIGNAL=true
fi

# Fallback: check transcript file if last_assistant_message didn't match
if [ "$HAS_DONE_SIGNAL" = false ] && [ -f "$TRANSCRIPT" ]; then
  if tail -400 "$TRANSCRIPT" 2>/dev/null | grep -Fq "$DONE_SIGNAL"; then
    HAS_DONE_SIGNAL=true
  fi
fi

if [ "$HAS_DONE_SIGNAL" = true ]; then
  rm -f "$COUNTER_FILE"
  exit 0
fi

NEXT=$((COUNT + 1))
echo "$NEXT" > "$COUNTER_FILE"

# Optional escape hatch. Default is 100.
if [ "$MAX" -gt 0 ] && [ "$NEXT" -ge "$MAX" ]; then
  rm -f "$COUNTER_FILE"
  exit 0
fi

# Minimal reason — full completion checklist lives in SKILL.md (always in system context).
# Only the done signal is included so the agent knows exactly what to emit when complete.
jq -n --arg reason "$DONE_SIGNAL" '{ decision: "block", reason: $reason }'
