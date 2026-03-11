#!/usr/bin/env bash

set -euo pipefail

TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/taskmaster-inject-test.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

INJECTOR="/Users/blader/.codex/skills/taskmaster/hooks/inject-continue-codex.sh"
LOG_PATH="$TEST_TMPDIR/session.jsonl"
EMIT_DIR="$TEST_TMPDIR/emit"

mkdir -p "$EMIT_DIR"

cat > "$LOG_PATH" <<'EOF'
{"kind":"codex_event","payload":{"msg":{"type":"session_configured","session_id":"session-123"}}}
{"kind":"codex_event","payload":{"msg":{"type":"task_complete","turn_id":"turn-1","last_agent_message":"Work is incomplete."}}}
{"kind":"session_end"}
EOF

set +e
"$INJECTOR" --log "$LOG_PATH" --emit-dir "$EMIT_DIR"
status_missing_done=$?
set -e

if [[ "$status_missing_done" -ne 2 ]]; then
  printf 'expected missing-done final_answer case to exit 2, got %q\n' "$status_missing_done" >&2
  exit 1
fi

emit_count="$(find "$EMIT_DIR" -type f | wc -l | tr -d ' ')"
if [[ "$emit_count" -ne 1 ]]; then
  printf 'expected one queued continuation prompt, found %q\n' "$emit_count" >&2
  exit 1
fi

rm -f "$EMIT_DIR"/*

cat > "$LOG_PATH" <<'EOF'
{"kind":"codex_event","payload":{"msg":{"type":"session_configured","session_id":"session-123"}}}
{"kind":"codex_event","payload":{"msg":{"type":"task_complete","turn_id":"turn-2","last_agent_message":"Done.\nTASKMASTER_DONE::session-123"}}}
{"kind":"session_end"}
EOF

set +e
"$INJECTOR" --log "$LOG_PATH" --emit-dir "$EMIT_DIR"
status_with_done=$?
set -e

if [[ "$status_with_done" -ne 0 ]]; then
  printf 'expected done-token final_answer case to exit 0, got %q\n' "$status_with_done" >&2
  exit 1
fi

emit_count="$(find "$EMIT_DIR" -type f | wc -l | tr -d ' ')"
if [[ "$emit_count" -ne 0 ]]; then
  printf 'expected no queued continuation prompt for done-token case, found %q\n' "$emit_count" >&2
  exit 1
fi

cat > "$LOG_PATH" <<'EOF'
{"kind":"codex_event","payload":{"msg":{"type":"session_configured","session_id":"session-123"}}}

{"kind":"codex_event","payload":{"msg":{"type":"task_complete","turn_id":"turn-blank","last_agent_message":"Done.\nTASKMASTER_DONE::session-123"}}}
{"kind":"session_end"}
EOF

rm -f "$EMIT_DIR"/*

set +e
"$INJECTOR" --log "$LOG_PATH" --emit-dir "$EMIT_DIR"
status_with_blank_line=$?
set -e

if [[ "$status_with_blank_line" -ne 0 ]]; then
  printf 'expected blank-line log with done token to exit 0, got %q\n' "$status_with_blank_line" >&2
  exit 1
fi

emit_count="$(find "$EMIT_DIR" -type f | wc -l | tr -d ' ')"
if [[ "$emit_count" -ne 0 ]]; then
  printf 'expected no queued continuation prompt for blank-line done-token case, found %q\n' "$emit_count" >&2
  exit 1
fi

cat > "$LOG_PATH" <<'EOF'
{"kind":"codex_event","payload":{"msg":{"type":"session_configured","session_id":"session-123"}}}
{"kind":"codex_event","payload":{"msg":{"type":"task_complete","turn_id":"turn-1","last_agent_message":"Needs more work."}}}
{"kind":"codex_event","payload":{"msg":{"type":"task_complete","turn_id":"turn-2","last_agent_message":"Done.\nTASKMASTER_DONE::session-123"}}}
{"kind":"codex_event","payload":{"msg":{"type":"task_complete","turn_id":"turn-3","last_agent_message":"A later turn is incomplete again."}}}
{"kind":"session_end"}
EOF

rm -f "$EMIT_DIR"/*

set +e
"$INJECTOR" --log "$LOG_PATH" --emit-dir "$EMIT_DIR"
status_done_not_terminal=$?
set -e

if [[ "$status_done_not_terminal" -ne 2 ]]; then
  printf 'expected later incomplete turn after done token to exit 2, got %q\n' "$status_done_not_terminal" >&2
  exit 1
fi

emit_count="$(find "$EMIT_DIR" -type f | wc -l | tr -d ' ')"
if [[ "$emit_count" -ne 2 ]]; then
  printf 'expected two queued continuation prompts across incomplete turns, found %q\n' "$emit_count" >&2
  exit 1
fi

echo "ok"
