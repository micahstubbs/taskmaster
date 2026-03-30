#!/bin/sh
#
# Taskmaster installer
#
# Installs the skill + stop hook and registers it in ~/.claude/settings.json.
#
set -eu
# Enable pipefail if the shell supports it (bash, zsh)
(set -o pipefail 2>/dev/null) && set -o pipefail || true

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$HOME/.claude/skills/taskmaster"
HOOKS_DIR="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"

echo "Installing Taskmaster..."

# 1. Copy skill files
mkdir -p "$SKILL_DIR/hooks"
cp "$SCRIPT_DIR/SKILL.md" "$SKILL_DIR/SKILL.md"
cp "$SCRIPT_DIR/check-completion.sh" "$SKILL_DIR/hooks/check-completion.sh"
chmod +x "$SKILL_DIR/hooks/check-completion.sh"
echo "  Skill installed to $SKILL_DIR"

# 2. Copy hook to user-level ~/.claude/hooks/
mkdir -p "$HOOKS_DIR"
cp "$SCRIPT_DIR/check-completion.sh" "$HOOKS_DIR/taskmaster-check-completion.sh"
chmod +x "$HOOKS_DIR/taskmaster-check-completion.sh"
echo "  Hook installed to $HOOKS_DIR/taskmaster-check-completion.sh"

# 3. Register the stop hook in settings.json
HOOK_CMD="\$HOME/.claude/hooks/taskmaster-check-completion.sh"

if [ ! -f "$SETTINGS" ]; then
  # No settings file — create one with just the hook
  cat > "$SETTINGS" <<EOF
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOOK_CMD",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
EOF
  echo "  Created $SETTINGS with stop hook"
elif grep -q 'skills/taskmaster/hooks/check-completion.sh' "$SETTINGS" 2>/dev/null; then
  # Old path found — migrate to new ~/.claude/hooks/ path
  if command -v jq >/dev/null 2>&1; then
    TMP=$(mktemp)
    jq '
      .hooks.Stop |= map(
        .hooks |= map(
          if (.command | test("skills/taskmaster/hooks/check-completion\\.sh"))
          then .command = "$HOME/.claude/hooks/taskmaster-check-completion.sh"
          else . end
        )
      )
    ' "$SETTINGS" > "$TMP" && mv "$TMP" "$SETTINGS"
    echo "  Migrated hook path to $HOOK_CMD in $SETTINGS"
  else
    echo "  jq not found — please update the hook path manually in $SETTINGS"
    echo "  Old: \$HOME/.claude/skills/taskmaster/hooks/check-completion.sh"
    echo "  New: $HOOK_CMD"
  fi
elif ! grep -q 'check-completion.sh' "$SETTINGS" 2>/dev/null; then
  # Settings exists but hook not registered — merge it in
  if command -v jq >/dev/null 2>&1; then
    HOOK_ENTRY=$(cat <<EOF
[{"hooks":[{"type":"command","command":"$HOOK_CMD","timeout":10}]}]
EOF
)
    TMP=$(mktemp)
    jq --argjson hook "$HOOK_ENTRY" '
      .hooks //= {} |
      .hooks.Stop //= [] |
      .hooks.Stop += $hook
    ' "$SETTINGS" > "$TMP" && mv "$TMP" "$SETTINGS"
    echo "  Added stop hook to $SETTINGS"
  else
    echo ""
    echo "  jq not found — could not auto-register the hook."
    echo "  Add this manually to $SETTINGS:"
    echo ""
    echo '  "hooks": {'
    echo '    "Stop": [{'
    echo '      "hooks": [{'
    echo '        "type": "command",'
    echo "        \"command\": \"$HOOK_CMD\","
    echo '        "timeout": 10'
    echo '      }]'
    echo '    }]'
    echo '  }'
    echo ""
  fi
else
  echo "  Stop hook already registered in $SETTINGS"
fi

echo ""
echo "Done. Restart your coding agent to activate Taskmaster."
