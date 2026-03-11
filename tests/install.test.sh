#!/usr/bin/env bash

set -euo pipefail

SCRIPT="/Users/blader/.codex/skills/taskmaster/install.sh"

assert_single_block() {
  local rc_path="$1"
  local count

  count="$(rg -c '^# TASKMASTER CODEX WRAPPER$' "$rc_path")"
  if [[ "$count" != "1" ]]; then
    printf 'expected exactly one Taskmaster block in %s, got %s\n' "$rc_path" "$count" >&2
    exit 1
  fi
}

TEST_HOME_SUPERSET="$(mktemp -d "${TMPDIR:-/tmp}/taskmaster-install-test-superset.XXXXXX")"
TEST_HOME_PLAIN="$(mktemp -d "${TMPDIR:-/tmp}/taskmaster-install-test-plain.XXXXXX")"
trap 'rm -rf "$TEST_HOME_SUPERSET" "$TEST_HOME_PLAIN"' EXIT

mkdir -p "$TEST_HOME_SUPERSET/.superset/bin"
printf '#!/usr/bin/env bash\n' > "$TEST_HOME_SUPERSET/.superset/bin/codex"
chmod +x "$TEST_HOME_SUPERSET/.superset/bin/codex"
cat > "$TEST_HOME_SUPERSET/.zshrc" <<'EOF'
export PATH="$HOME/.local/bin:$PATH"
# Prefer the Superset codex wrapper over taskmaster and npm-global shims.
export PATH="$HOME/.superset/bin:$PATH"
EOF

HOME="$TEST_HOME_SUPERSET" SHELL="/bin/zsh" TASKMASTER_INSTALL_TARGET=codex bash "$SCRIPT" >/dev/null

superset_block_line="$(rg -n '^# TASKMASTER CODEX WRAPPER$' "$TEST_HOME_SUPERSET/.zshrc" | cut -d: -f1)"
superset_path_line="$(rg -n '^[^\n]*\.superset/bin[^\n]*$' "$TEST_HOME_SUPERSET/.zshrc" | tail -n 1 | cut -d: -f1)"

if [[ -z "$superset_block_line" || -z "$superset_path_line" || "$superset_block_line" -ge "$superset_path_line" ]]; then
  printf 'expected Taskmaster block before Superset PATH line in %s\n' "$TEST_HOME_SUPERSET/.zshrc" >&2
  sed -n '1,120p' "$TEST_HOME_SUPERSET/.zshrc" >&2
  exit 1
fi

assert_single_block "$TEST_HOME_SUPERSET/.zshrc"

HOME="$TEST_HOME_SUPERSET" SHELL="/bin/zsh" TASKMASTER_INSTALL_TARGET=codex bash "$SCRIPT" >/dev/null
assert_single_block "$TEST_HOME_SUPERSET/.zshrc"

cat > "$TEST_HOME_PLAIN/.zshrc" <<'EOF'
export PATH="/opt/homebrew/bin:$PATH"
EOF

HOME="$TEST_HOME_PLAIN" SHELL="/bin/zsh" TASKMASTER_INSTALL_TARGET=codex bash "$SCRIPT" >/dev/null

plain_block_line="$(rg -n '^# TASKMASTER CODEX WRAPPER$' "$TEST_HOME_PLAIN/.zshrc" | cut -d: -f1)"
plain_existing_line="$(rg -n '^export PATH="/opt/homebrew/bin:\$PATH"$' "$TEST_HOME_PLAIN/.zshrc" | cut -d: -f1)"

if [[ -z "$plain_block_line" || -z "$plain_existing_line" || "$plain_block_line" -le "$plain_existing_line" ]]; then
  printf 'expected Taskmaster block appended after existing PATH content in %s\n' "$TEST_HOME_PLAIN/.zshrc" >&2
  sed -n '1,120p' "$TEST_HOME_PLAIN/.zshrc" >&2
  exit 1
fi

assert_single_block "$TEST_HOME_PLAIN/.zshrc"

echo "ok"
