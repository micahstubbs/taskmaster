#!/usr/bin/env bash

set -euo pipefail

TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/taskmaster-bridge-test.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

cat > "$TEST_TMPDIR/fake-child.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

IFS= read -r line
printf '%s\n' "$line" > "$TASKMASTER_BRIDGE_TEST_OUT"
EOF
chmod +x "$TEST_TMPDIR/fake-child.sh"

printf '%s' 'Bridge hello' > "$TEST_TMPDIR/inject.0001.txt"

export TASKMASTER_BRIDGE_TEST_OUT="$TEST_TMPDIR/out.txt"

script -q /dev/null \
  /Users/blader/.codex/skills/taskmaster/hooks/run-codex-expect-bridge.exp \
  "$TEST_TMPDIR" \
  "$TEST_TMPDIR/fake-child.sh" \
  >/dev/null 2>&1 || true

actual="$(cat "$TASKMASTER_BRIDGE_TEST_OUT")"
expected=$'\E[200~Bridge hello\E[201~'

if [[ "$actual" != "$expected" ]]; then
  printf 'expected bracketed-paste payload, got: %q\n' "$actual" >&2
  exit 1
fi

echo "ok"

TEST_TMPDIR_DSR="$(mktemp -d "${TMPDIR:-/tmp}/taskmaster-bridge-dsr-test.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR" "$TEST_TMPDIR_DSR"' EXIT

cat > "$TEST_TMPDIR_DSR/fake-dsr-child.py" <<'EOF'
#!/usr/bin/env python3
import os
import select
import sys
import termios
import tty

fd = sys.stdin.fileno()
attrs = termios.tcgetattr(fd)
try:
    tty.setcbreak(fd)
    sys.stdout.write("\x1b[6n")
    sys.stdout.flush()

    response = b""
    ready, _, _ = select.select([sys.stdin.buffer], [], [], 2.0)
    if ready:
        response = os.read(fd, 64)
finally:
    termios.tcsetattr(fd, termios.TCSADRAIN, attrs)

with open(os.environ["TASKMASTER_BRIDGE_TEST_OUT_DSR"], "wb") as fh:
    fh.write(response)
EOF
chmod +x "$TEST_TMPDIR_DSR/fake-dsr-child.py"

export TASKMASTER_BRIDGE_TEST_OUT_DSR="$TEST_TMPDIR_DSR/out.bin"

script -q /dev/null \
  /Users/blader/.codex/skills/taskmaster/hooks/run-codex-expect-bridge.exp \
  "$TEST_TMPDIR_DSR" \
  "$TEST_TMPDIR_DSR/fake-dsr-child.py" \
  >/dev/null 2>&1 || true

python3 - <<'EOF' "$TEST_TMPDIR_DSR/out.bin"
import sys

actual = open(sys.argv[1], "rb").read()
expected = b"\x1b[1;1R"

if actual != expected:
    raise SystemExit(f"expected cursor-position response {expected!r}, got {actual!r}")
EOF

echo "ok"

TEST_TMPDIR_DELAYED_DSR="$(mktemp -d "${TMPDIR:-/tmp}/taskmaster-bridge-delayed-dsr-test.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR" "$TEST_TMPDIR_DSR" "$TEST_TMPDIR_DELAYED_DSR"' EXIT

cat > "$TEST_TMPDIR_DELAYED_DSR/fake-delayed-dsr-child.py" <<'EOF'
#!/usr/bin/env python3
import os
import select
import sys
import termios
import time
import tty

fd = sys.stdin.fileno()
attrs = termios.tcgetattr(fd)
try:
    tty.setcbreak(fd)
    time.sleep(1.3)
    sys.stdout.write("\x1b[6n")
    sys.stdout.flush()

    response = b""
    ready, _, _ = select.select([sys.stdin.buffer], [], [], 2.0)
    if ready:
        response = os.read(fd, 64)
finally:
    termios.tcsetattr(fd, termios.TCSADRAIN, attrs)

with open(os.environ["TASKMASTER_BRIDGE_TEST_OUT_DELAYED_DSR"], "wb") as fh:
    fh.write(response)
EOF
chmod +x "$TEST_TMPDIR_DELAYED_DSR/fake-delayed-dsr-child.py"

export TASKMASTER_BRIDGE_TEST_OUT_DELAYED_DSR="$TEST_TMPDIR_DELAYED_DSR/out.bin"

script -q /dev/null \
  /Users/blader/.codex/skills/taskmaster/hooks/run-codex-expect-bridge.exp \
  "$TEST_TMPDIR_DELAYED_DSR" \
  "$TEST_TMPDIR_DELAYED_DSR/fake-delayed-dsr-child.py" \
  >/dev/null 2>&1 || true

python3 - <<'EOF' "$TEST_TMPDIR_DELAYED_DSR/out.bin"
import sys

actual = open(sys.argv[1], "rb").read()
expected = b"\x1b[1;1R"

if actual != expected:
    raise SystemExit(f"expected delayed cursor-position response {expected!r}, got {actual!r}")
EOF

echo "ok"

TEST_TMPDIR_CAPS="$(mktemp -d "${TMPDIR:-/tmp}/taskmaster-bridge-caps-test.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR" "$TEST_TMPDIR_DSR" "$TEST_TMPDIR_DELAYED_DSR" "$TEST_TMPDIR_CAPS"' EXIT

cat > "$TEST_TMPDIR_CAPS/fake-terminal-cap-child.py" <<'EOF'
#!/usr/bin/env python3
import os
import select
import sys
import termios
import tty

fd = sys.stdin.fileno()
attrs = termios.tcgetattr(fd)
try:
    tty.setcbreak(fd)
    sys.stdout.write("\x1b[?u\x1b[c")
    sys.stdout.flush()

    response = b""
    deadline = 2.0
    while deadline > 0:
      ready, _, _ = select.select([sys.stdin.buffer], [], [], deadline)
      if not ready:
          break
      response += os.read(fd, 64)
      if response == b"\x1b[?0u\x1b[?1;2c":
          break
      deadline = 0.2
finally:
    termios.tcsetattr(fd, termios.TCSADRAIN, attrs)

with open(os.environ["TASKMASTER_BRIDGE_TEST_OUT_CAPS"], "wb") as fh:
    fh.write(response)
EOF
chmod +x "$TEST_TMPDIR_CAPS/fake-terminal-cap-child.py"

export TASKMASTER_BRIDGE_TEST_OUT_CAPS="$TEST_TMPDIR_CAPS/out.bin"

script -q /dev/null \
  /Users/blader/.codex/skills/taskmaster/hooks/run-codex-expect-bridge.exp \
  "$TEST_TMPDIR_CAPS" \
  "$TEST_TMPDIR_CAPS/fake-terminal-cap-child.py" \
  >/dev/null 2>&1 || true

python3 - <<'EOF' "$TEST_TMPDIR_CAPS/out.bin"
import sys

actual = open(sys.argv[1], "rb").read()
expected = b"\x1b[?0u\x1b[?1;2c"

if actual != expected:
    raise SystemExit(f"expected terminal capability responses {expected!r}, got {actual!r}")
EOF

echo "ok"

TEST_TMPDIR_AUTO_PASTE="$(mktemp -d "${TMPDIR:-/tmp}/taskmaster-bridge-auto-paste-test.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR" "$TEST_TMPDIR_DSR" "$TEST_TMPDIR_DELAYED_DSR" "$TEST_TMPDIR_CAPS" "$TEST_TMPDIR_AUTO_PASTE"' EXIT

cat > "$TEST_TMPDIR_AUTO_PASTE/fake-auto-paste-child.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
sleep 1
EOF
chmod +x "$TEST_TMPDIR_AUTO_PASTE/fake-auto-paste-child.sh"

printf 'line one\nline two' > "$TEST_TMPDIR_AUTO_PASTE/inject.0001.txt"
export SUPERSET_CODEX_TRACE_PATH="$TEST_TMPDIR_AUTO_PASTE/trace.log"
unset TASKMASTER_EXPECT_PASTE_MODE

script -q /dev/null \
  /Users/blader/.codex/skills/taskmaster/hooks/run-codex-expect-bridge.exp \
  "$TEST_TMPDIR_AUTO_PASTE" \
  "$TEST_TMPDIR_AUTO_PASTE/fake-auto-paste-child.sh" \
  >/dev/null 2>&1 || true

if ! rg -n 'inject_send mode=bracketed' "$TEST_TMPDIR_AUTO_PASTE/trace.log" >/dev/null 2>&1; then
  printf 'expected auto multiline injection to resolve to bracketed paste\n' >&2
  sed -n '1,120p' "$TEST_TMPDIR_AUTO_PASTE/trace.log" >&2 || true
  exit 1
fi

echo "ok"
