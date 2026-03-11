#!/usr/bin/env bash
#
# Taskmaster installer for Codex and Claude.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CODEX_ROOT="$HOME/.codex"
CLAUDE_ROOT="$HOME/.claude"

CODEX_SKILL_DIR="$CODEX_ROOT/skills/taskmaster"
CLAUDE_SKILL_DIR="$CLAUDE_ROOT/skills/taskmaster"

CODEX_VENDOR_BIN_DIR="$CODEX_ROOT/bin"
CODEX_BIN_DIR="${TASKMASTER_CODEX_BIN_DIR:-$HOME/.local/bin}"
CODEX_LAUNCHER_LINK="$CODEX_BIN_DIR/codex-taskmaster"
CODEX_SHIM_LINK="$CODEX_BIN_DIR/codex"
CODEX_LEGACY_LAUNCHER_LINK="$CODEX_VENDOR_BIN_DIR/codex-taskmaster"
CODEX_LEGACY_SHIM_LINK="$CODEX_VENDOR_BIN_DIR/codex"
SHELL_NAME="$(basename "${SHELL:-}")"

CLAUDE_HOOKS_DIR="$CLAUDE_ROOT/hooks"
CLAUDE_HOOK_LINK="$CLAUDE_HOOKS_DIR/taskmaster-check-completion.sh"
CLAUDE_SETTINGS_PATH="$CLAUDE_ROOT/settings.json"
CLAUDE_HOOK_COMMAND="~/.claude/hooks/taskmaster-check-completion.sh"

safe_copy() {
  local src="$1"
  local dst="$2"

  if [[ "$(cd "$(dirname "$src")" && pwd)/$(basename "$src")" == "$(cd "$(dirname "$dst")" && pwd)/$(basename "$dst")" ]]; then
    return 0
  fi
  cp "$src" "$dst"
}

copy_skill_files() {
  local skill_dir="$1"

  mkdir -p "$skill_dir/hooks"
  mkdir -p "$skill_dir/docs"

  safe_copy "$SCRIPT_DIR/SKILL.md" "$skill_dir/SKILL.md"
  safe_copy "$SCRIPT_DIR/README.md" "$skill_dir/README.md"
  safe_copy "$SCRIPT_DIR/LICENSE" "$skill_dir/LICENSE"
  safe_copy "$SCRIPT_DIR/docs/SPEC.md" "$skill_dir/docs/SPEC.md"
  safe_copy "$SCRIPT_DIR/install.sh" "$skill_dir/install.sh"
  safe_copy "$SCRIPT_DIR/uninstall.sh" "$skill_dir/uninstall.sh"
  safe_copy "$SCRIPT_DIR/taskmaster-compliance-prompt.sh" "$skill_dir/taskmaster-compliance-prompt.sh"

  safe_copy "$SCRIPT_DIR/run-taskmaster-codex.sh" "$skill_dir/run-taskmaster-codex.sh"
  safe_copy "$SCRIPT_DIR/check-completion.sh" "$skill_dir/check-completion.sh"
  safe_copy "$SCRIPT_DIR/hooks/check-completion.sh" "$skill_dir/hooks/check-completion.sh"
  safe_copy "$SCRIPT_DIR/hooks/inject-continue-codex.sh" "$skill_dir/hooks/inject-continue-codex.sh"
  safe_copy "$SCRIPT_DIR/hooks/run-codex-expect-bridge.exp" "$skill_dir/hooks/run-codex-expect-bridge.exp"
  safe_copy "$SCRIPT_DIR/hooks/run-codex-resume-bridge.exp" "$skill_dir/hooks/run-codex-resume-bridge.exp"

  chmod +x "$skill_dir/install.sh"
  chmod +x "$skill_dir/uninstall.sh"
  chmod +x "$skill_dir/taskmaster-compliance-prompt.sh"
  chmod +x "$skill_dir/run-taskmaster-codex.sh"
  chmod +x "$skill_dir/check-completion.sh"
  chmod +x "$skill_dir/hooks/check-completion.sh"
  chmod +x "$skill_dir/hooks/inject-continue-codex.sh"
  chmod +x "$skill_dir/hooks/run-codex-expect-bridge.exp"
  chmod +x "$skill_dir/hooks/run-codex-resume-bridge.exp"
}

codex_detected() {
  command -v codex >/dev/null 2>&1 || [[ -d "$CODEX_ROOT" ]]
}

claude_detected() {
  command -v claude >/dev/null 2>&1 || [[ -d "$CLAUDE_ROOT" ]]
}

resolve_link_target() {
  local link_path="$1"
  local raw_target
  local target_dir

  raw_target="$(readlink "$link_path")"
  if [[ "$raw_target" == /* ]]; then
    printf '%s\n' "$raw_target"
    return 0
  fi

  target_dir="$(cd "$(dirname "$link_path")" && cd "$(dirname "$raw_target")" && pwd)"
  printf '%s/%s\n' "$target_dir" "$(basename "$raw_target")"
}

remove_taskmaster_link_if_present() {
  local link_path="$1"
  local resolved_target

  [[ -L "$link_path" ]] || return 0
  resolved_target="$(resolve_link_target "$link_path")"

  case "$resolved_target" in
    "$CODEX_SKILL_DIR/run-taskmaster-codex.sh"|"$CODEX_LAUNCHER_LINK"|"$CODEX_LEGACY_LAUNCHER_LINK")
      rm -f "$link_path"
      echo "  Codex: removed Taskmaster-managed link at $link_path"
      ;;
  esac
}

detect_shell_rc_path() {
  case "$SHELL_NAME" in
    zsh)
      printf '%s\n' "$HOME/.zshrc"
      ;;
    bash)
      printf '%s\n' "$HOME/.bashrc"
      ;;
    *)
      return 1
      ;;
  esac
}

ensure_shell_wrapper_block() {
  local rc_path="$1"
  local launcher_dir="$2"

  if ! command -v python3 >/dev/null 2>&1; then
    echo "  Codex: python3 not found; add $launcher_dir to PATH manually" >&2
    return 0
  fi

  python3 - "$rc_path" "$launcher_dir" <<'PY'
import os
import sys

rc_path = os.path.expanduser(sys.argv[1])
launcher_dir = os.path.expanduser(sys.argv[2])

start = "# TASKMASTER CODEX WRAPPER"
end = "# END TASKMASTER CODEX WRAPPER"
block = f"""{start}
taskmaster_codex_bin="{launcher_dir}"
case ":$PATH:" in
  *":$taskmaster_codex_bin:"*) ;;
  *) export PATH="$taskmaster_codex_bin:$PATH" ;;
esac
{end}
"""

try:
    with open(rc_path, "r", encoding="utf-8") as f:
        content = f.read()
except FileNotFoundError:
    content = ""

if start in content and end in content:
    before, rest = content.split(start, 1)
    _, after = rest.split(end, 1)
    new_content = before.rstrip() + "\n\n" + block + after.lstrip("\n")
else:
    stripped = content.rstrip()
    if stripped:
        new_content = stripped + "\n\n" + block
    else:
        new_content = block

os.makedirs(os.path.dirname(rc_path), exist_ok=True)
with open(rc_path, "w", encoding="utf-8") as f:
    f.write(new_content.rstrip() + "\n")
PY

  echo "  Codex: ensured $launcher_dir is early on PATH via $rc_path"
}

install_codex_shim_if_requested() {
  if [[ "${TASKMASTER_INSTALL_CODEX_SHIM:-1}" != "1" ]]; then
    remove_taskmaster_link_if_present "$CODEX_SHIM_LINK"
    echo "  Codex: leaving \`codex\` unmanaged; use \`codex-taskmaster\`"
    return 0
  fi

  if [[ -e "$CODEX_SHIM_LINK" && ! -L "$CODEX_SHIM_LINK" ]]; then
    echo "  Codex: skipped shim at $CODEX_SHIM_LINK (existing file is not a symlink)"
    return 0
  fi

  ln -sf "$CODEX_SKILL_DIR/run-taskmaster-codex.sh" "$CODEX_SHIM_LINK"
  echo "  Codex: linked codex shim at $CODEX_SHIM_LINK"
}

ensure_claude_stop_hook() {
  local settings_path="$1"
  local hook_command="$2"

  if ! command -v python3 >/dev/null 2>&1; then
    echo "  Claude: python3 not found; add Stop hook manually -> $hook_command" >&2
    return 0
  fi

  python3 - "$settings_path" "$hook_command" <<'PY'
import json
import os
import sys

settings_path = sys.argv[1]
hook_command = sys.argv[2]

if os.path.exists(settings_path):
    try:
        with open(settings_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        print(f"  Claude: settings is not valid JSON ({settings_path}); add Stop hook manually.", file=sys.stderr)
        sys.exit(0)
else:
    data = {}

if not isinstance(data, dict):
    print(f"  Claude: settings root is not an object ({settings_path}); add Stop hook manually.", file=sys.stderr)
    sys.exit(0)

container = None
if isinstance(data.get("hooks"), dict):
    container = data["hooks"]
else:
    container = data

stop_hooks = container.get("Stop")
if not isinstance(stop_hooks, list):
    stop_hooks = []
    container["Stop"] = stop_hooks

exists = False
for entry in stop_hooks:
    if not isinstance(entry, dict):
        continue
    hooks = entry.get("hooks")
    if not isinstance(hooks, list):
        continue
    for hook in hooks:
        if not isinstance(hook, dict):
            continue
        if hook.get("type") == "command" and hook.get("command") == hook_command:
            exists = True
            break
    if exists:
        break

if not exists:
    stop_hooks.append(
        {
            "matcher": "*",
            "hooks": [
                {
                    "type": "command",
                    "command": hook_command,
                }
            ],
        }
    )

os.makedirs(os.path.dirname(settings_path), exist_ok=True)
with open(settings_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

if exists:
    print("  Claude: Stop hook already configured")
else:
    print("  Claude: added Stop hook to settings")
PY
}

install_codex() {
  local shell_rc_path=""

  copy_skill_files "$CODEX_SKILL_DIR"

  mkdir -p "$CODEX_BIN_DIR"
  ln -sf "$CODEX_SKILL_DIR/run-taskmaster-codex.sh" "$CODEX_LAUNCHER_LINK"
  install_codex_shim_if_requested

  if [[ "$CODEX_BIN_DIR" != "$CODEX_VENDOR_BIN_DIR" ]]; then
    remove_taskmaster_link_if_present "$CODEX_LEGACY_LAUNCHER_LINK"
    remove_taskmaster_link_if_present "$CODEX_LEGACY_SHIM_LINK"
  fi

  echo "  Codex: installed skill files to $CODEX_SKILL_DIR"
  echo "  Codex: linked launcher at $CODEX_LAUNCHER_LINK"
  echo "  Codex: launcher dir is user-managed so Codex upgrades should not overwrite it"

  if [[ "${TASKMASTER_INSTALL_SHELL_WRAPPER:-1}" == "1" ]]; then
    if shell_rc_path="$(detect_shell_rc_path)"; then
      ensure_shell_wrapper_block "$shell_rc_path" "$CODEX_BIN_DIR"
    else
      echo "  Codex: unsupported shell '$SHELL_NAME'; ensure $CODEX_BIN_DIR is ahead of the real Codex binary on PATH"
    fi
  fi
}

install_claude() {
  copy_skill_files "$CLAUDE_SKILL_DIR"

  mkdir -p "$CLAUDE_HOOKS_DIR"
  ln -sf "$CLAUDE_SKILL_DIR/check-completion.sh" "$CLAUDE_HOOK_LINK"
  ln -sf "$CLAUDE_SKILL_DIR/taskmaster-compliance-prompt.sh" "$CLAUDE_HOOKS_DIR/taskmaster-compliance-prompt.sh"
  chmod +x "$CLAUDE_HOOK_LINK"

  echo "  Claude: installed skill files to $CLAUDE_SKILL_DIR"
  echo "  Claude: linked Stop hook at $CLAUDE_HOOK_LINK"
  ensure_claude_stop_hook "$CLAUDE_SETTINGS_PATH" "$CLAUDE_HOOK_COMMAND"
}

INSTALL_TARGET="${TASKMASTER_INSTALL_TARGET:-auto}"
INSTALL_CODEX=0
INSTALL_CLAUDE=0

case "$INSTALL_TARGET" in
  auto)
    if codex_detected; then
      INSTALL_CODEX=1
    fi
    if claude_detected; then
      INSTALL_CLAUDE=1
    fi
    if [[ "$INSTALL_CODEX" -eq 0 && "$INSTALL_CLAUDE" -eq 0 ]]; then
      INSTALL_CODEX=1
      INSTALL_CLAUDE=1
      echo "No Codex/Claude install detected; defaulting to both targets."
    fi
    ;;
  codex)
    INSTALL_CODEX=1
    ;;
  claude)
    INSTALL_CLAUDE=1
    ;;
  both)
    INSTALL_CODEX=1
    INSTALL_CLAUDE=1
    ;;
  *)
    echo "Invalid TASKMASTER_INSTALL_TARGET='$INSTALL_TARGET' (expected: auto|codex|claude|both)" >&2
    exit 4
    ;;
esac

echo "Installing Taskmaster..."

if [[ "$INSTALL_CODEX" -eq 1 ]]; then
  install_codex
fi

if [[ "$INSTALL_CLAUDE" -eq 1 ]]; then
  install_claude
fi

echo ""
echo "Done."

if [[ "$INSTALL_CODEX" -eq 1 ]]; then
  echo ""
  echo "Codex usage:"
  echo "  codex [codex args]"
  echo "  codex-taskmaster [codex args]"
  echo "  Disable codex shim install: TASKMASTER_INSTALL_CODEX_SHIM=0 bash ~/.codex/skills/taskmaster/install.sh"
fi

if [[ "$INSTALL_CLAUDE" -eq 1 ]]; then
  echo ""
  echo "Claude usage:"
  echo "  Claude Stop hook is configured at $CLAUDE_HOOK_COMMAND"
fi
