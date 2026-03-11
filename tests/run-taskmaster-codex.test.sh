#!/usr/bin/env bash

set -euo pipefail

TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/taskmaster-runner-test.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

SKILL_DIR="$TEST_TMPDIR/taskmaster"
BIN_DIR="$TEST_TMPDIR/bin"
REAL_BIN_DIR="$TEST_TMPDIR/real-bin"
HOME_DIR="$TEST_TMPDIR/home"
LOG_DIR="$HOME_DIR/.codex/log"
EXPECT_OUT="$TEST_TMPDIR/expect-invocations.log"
REAL_OUT="$TEST_TMPDIR/real-invocations.log"

mkdir -p "$SKILL_DIR/hooks" "$BIN_DIR" "$REAL_BIN_DIR" "$LOG_DIR"

cp /Users/blader/.codex/skills/taskmaster/run-taskmaster-codex.sh "$SKILL_DIR/run-taskmaster-codex.sh"

cat > "$SKILL_DIR/hooks/inject-continue-codex.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
while [[ $# -gt 0 ]]; do
  case "$1" in
    --emit-dir)
      emit_dir="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
mkdir -p "${emit_dir:?missing emit dir}"
sleep 0.1
EOF
chmod +x "$SKILL_DIR/hooks/inject-continue-codex.sh"

cat > "$SKILL_DIR/hooks/run-codex-expect-bridge.exp" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
queue_dir="$1"
shift
printf 'EXPECT:%s\n' "$*" >> "${TASKMASTER_TEST_EXPECT_OUT:?missing expect out}"
"$@"
EOF
chmod +x "$SKILL_DIR/hooks/run-codex-expect-bridge.exp"

cat > "$REAL_BIN_DIR/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'REAL:%s\n' "$*" >> "${TASKMASTER_TEST_REAL_OUT:?missing real out}"
EOF
chmod +x "$REAL_BIN_DIR/codex"

cat > "$BIN_DIR/codex" <<EOF
#!/usr/bin/env bash
exec "$SKILL_DIR/run-taskmaster-codex.sh" "\$@"
EOF
chmod +x "$BIN_DIR/codex"

export HOME="$HOME_DIR"
export PATH="$BIN_DIR:$REAL_BIN_DIR:/usr/bin:/bin"
export TASKMASTER_REAL_CODEX_BIN="$REAL_BIN_DIR/codex"
export TASKMASTER_TEST_EXPECT_OUT="$EXPECT_OUT"
export TASKMASTER_TEST_REAL_OUT="$REAL_OUT"

"$BIN_DIR/codex" resume session-123

if [[ ! -f "$EXPECT_OUT" ]]; then
  printf 'expected resume to use expect bridge\n' >&2
  exit 1
fi

if ! grep -F "resume session-123" "$EXPECT_OUT" >/dev/null 2>&1; then
  printf 'expected resume expect invocation in %s\n' "$EXPECT_OUT" >&2
  cat "$EXPECT_OUT" >&2
  exit 1
fi

if ! grep -F "REAL:resume session-123" "$REAL_OUT" >/dev/null 2>&1; then
  printf 'expected resume to reach real codex through wrapper\n' >&2
  cat "$REAL_OUT" >&2
  exit 1
fi

rm -f "$EXPECT_OUT" "$REAL_OUT"

"$BIN_DIR/codex" exec status

if [[ -f "$EXPECT_OUT" ]]; then
  printf 'expected exec to bypass expect bridge\n' >&2
  cat "$EXPECT_OUT" >&2
  exit 1
fi

if ! grep -F "REAL:exec status" "$REAL_OUT" >/dev/null 2>&1; then
  printf 'expected exec to call real codex directly\n' >&2
  cat "$REAL_OUT" >&2
  exit 1
fi

echo "ok"
