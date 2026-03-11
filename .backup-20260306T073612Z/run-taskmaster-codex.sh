#!/usr/bin/env bash
#
# Run Codex with Taskmaster continuation transport.
# Default: same-process expect injection so the original TUI stays alive.
# Alternate transport: relaunch the same session with `codex resume`.
#
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE_PATH" ]]; do
  SOURCE_DIR="$(cd -P "$(dirname "$SOURCE_PATH")" && pwd)"
  SOURCE_PATH="$(readlink "$SOURCE_PATH")"
  [[ "$SOURCE_PATH" != /* ]] && SOURCE_PATH="$SOURCE_DIR/$SOURCE_PATH"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE_PATH")" && pwd)"
INJECTOR="$SCRIPT_DIR/hooks/inject-continue-codex.sh"
EXPECT_INJECT_BRIDGE="$SCRIPT_DIR/hooks/run-codex-expect-bridge.exp"
RESUME_BRIDGE="$SCRIPT_DIR/hooks/run-codex-resume-bridge.exp"
ORIGINAL_ARGS=("$@")
TASKMASTER_RESUME_EXIT_CODE=90
TASKMASTER_CODEX_BIN_DIR="${TASKMASTER_CODEX_BIN_DIR:-$HOME/.local/bin}"

resolve_real_codex_bin() {
<<<<<<< HEAD
  local candidate
  local wrapper_path="$SOURCE_PATH"
  local wrapper_cmd="$TASKMASTER_CODEX_BIN_DIR/codex-taskmaster"
  local codex_shim="$TASKMASTER_CODEX_BIN_DIR/codex"
  local legacy_wrapper_cmd="$HOME/.codex/bin/codex-taskmaster"
  local legacy_codex_shim="$HOME/.codex/bin/codex"

  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    case "$candidate" in
      "$wrapper_path"|"$wrapper_cmd"|"$codex_shim"|"$legacy_wrapper_cmd"|"$legacy_codex_shim")
=======
  local candidate shebang

  while IFS= read -r candidate; do
    [[ -n "$candidate" && -x "$candidate" ]] || continue
    # Skip any bash/sh script wrapper (taskmaster shim, superset wrapper, etc.)
    shebang="$(head -c 128 "$candidate" 2>/dev/null || true)"
    case "$shebang" in
      "#!/bin/bash"*|"#!/usr/bin/env bash"*|"#!/bin/sh"*|"#!/usr/bin/env sh"*)
>>>>>>> efaa056 (chore(skills): auto-sync 2026-03-06T06:15:18Z)
        continue
        ;;
    esac
    echo "$candidate"
    return 0
  done < <(which -a codex 2>/dev/null | awk '!seen[$0]++')

  return 1
}

<<<<<<< HEAD
real_codex_requires_clean_path() {
  case "$1" in
    "$HOME"/.superset/bin/*|"$HOME"/.superset-*/bin/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

strip_taskmaster_shims_from_path() {
  local current_path="$1"
  local path_entry
  local filtered=()
  local IFS=:

  read -r -a path_parts <<< "$current_path"
  for path_entry in "${path_parts[@]}"; do
    [[ -n "$path_entry" ]] || continue
    case "$path_entry" in
      "$TASKMASTER_CODEX_BIN_DIR"|"$HOME"/.codex/bin|"$HOME"/.codex/tmp/arg0/*)
        continue
        ;;
    esac
    filtered+=("$path_entry")
  done

  if [[ ${#filtered[@]} -eq 0 ]]; then
    printf '%s\n' "$current_path"
    return 0
  fi

  printf '%s\n' "$(IFS=:; echo "${filtered[*]}")"
}
=======
# Re-entry guard: if we've already been invoked (e.g. via superset wrapper → taskmaster → expect
# → superset wrapper → taskmaster again), skip ALL wrappers and exec the real binary directly.
if [[ "${__TASKMASTER_ACTIVE:-}" == "1" ]]; then
  # Find the real codex binary by skipping all bash/sh script wrappers.
  while IFS= read -r __tm_candidate; do
    [[ -n "$__tm_candidate" && -x "$__tm_candidate" ]] || continue
    __tm_shebang="$(head -c 128 "$__tm_candidate" 2>/dev/null || true)"
    case "$__tm_shebang" in
      "#!/bin/bash"*|"#!/usr/bin/env bash"*|"#!/bin/sh"*|"#!/usr/bin/env sh"*)
        continue  # Skip bash/sh wrapper scripts
        ;;
    esac
    exec "$__tm_candidate" "$@"
  done < <(which -a codex 2>/dev/null | awk '!seen[$0]++')
  echo "Could not resolve real codex binary on re-entry." >&2
  exit 4
fi
export __TASKMASTER_ACTIVE=1

>>>>>>> efaa056 (chore(skills): auto-sync 2026-03-06T06:15:18Z)
if ! command -v codex >/dev/null 2>&1; then
  echo "codex CLI not found in PATH." >&2
  exit 4
fi

REAL_CODEX_BIN="${TASKMASTER_REAL_CODEX_BIN:-}"
# If the provided binary is a bash wrapper (e.g. superset shim), ignore it and resolve ourselves.
if [[ -n "$REAL_CODEX_BIN" && -x "$REAL_CODEX_BIN" ]]; then
  __tm_shebang="$(head -c 128 "$REAL_CODEX_BIN" 2>/dev/null || true)"
  case "$__tm_shebang" in
    "#!/bin/bash"*|"#!/usr/bin/env bash"*|"#!/bin/sh"*|"#!/usr/bin/env sh"*)
      REAL_CODEX_BIN=""
      ;;
  esac
fi
if [[ -z "$REAL_CODEX_BIN" ]]; then
  REAL_CODEX_BIN="$(resolve_real_codex_bin || true)"
fi
if [[ -z "$REAL_CODEX_BIN" ]] || [[ ! -x "$REAL_CODEX_BIN" ]]; then
  echo "Could not resolve real codex binary. Set TASKMASTER_REAL_CODEX_BIN." >&2
  exit 4
fi

REAL_CODEX_PATH="$PATH"
if real_codex_requires_clean_path "$REAL_CODEX_BIN"; then
  REAL_CODEX_PATH="$(strip_taskmaster_shims_from_path "$PATH")"
fi

is_known_subcommand() {
  case "$1" in
    exec|e|review|login|logout|mcp|mcp-server|app-server|app|completion|sandbox|debug|apply|a|resume|fork|cloud|features|help)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Pass through for non-interactive codex command families and generic help/version.
for arg in ${ORIGINAL_ARGS[@]+"${ORIGINAL_ARGS[@]}"}; do
  case "$arg" in
    -h|--help|-V|--version)
      exec env PATH="$REAL_CODEX_PATH" "$REAL_CODEX_BIN" "${ORIGINAL_ARGS[@]}"
      ;;
  esac
done

first_non_option=""
for arg in ${ORIGINAL_ARGS[@]+"${ORIGINAL_ARGS[@]}"}; do
  if [[ "$arg" == "--" ]]; then
    break
  fi
  if [[ "$arg" == -* ]]; then
    continue
  fi
  first_non_option="$arg"
  break
done
if [[ -n "$first_non_option" ]] && is_known_subcommand "$first_non_option"; then
  exec env PATH="$REAL_CODEX_PATH" "$REAL_CODEX_BIN" "${ORIGINAL_ARGS[@]}"
fi

PASSTHROUGH_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --)
      shift
      while [[ $# -gt 0 ]]; do
        PASSTHROUGH_ARGS+=("$1")
        shift
      done
      ;;
    *)
      PASSTHROUGH_ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ ! -x "$INJECTOR" ]]; then
  echo "Missing executable injector script: $INJECTOR" >&2
  exit 4
fi

if [[ ! -x "$EXPECT_INJECT_BRIDGE" ]]; then
  echo "Missing executable expect bridge: $EXPECT_INJECT_BRIDGE" >&2
  exit 4
fi

if [[ ! -x "$RESUME_BRIDGE" ]]; then
  echo "Missing executable resume bridge: $RESUME_BRIDGE" >&2
  exit 4
fi

if ! command -v expect >/dev/null 2>&1; then
  echo "expect is required." >&2
  exit 4
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required." >&2
  exit 4
fi

build_log_path() {
  local timestamp

  timestamp="$(date -u +%Y%m%dT%H%M%SZ)-$$-1"
  echo "$HOME/.codex/log/taskmaster-session-${timestamp}.jsonl"
}

prepare_log_env() {
  local log_path="$1"
  mkdir -p "$(dirname "$log_path")"
  : > "$log_path"
  export CODEX_TUI_RECORD_SESSION=1
  export CODEX_TUI_SESSION_LOG_PATH="$log_path"
}

cleanup_background() {
  local pid="$1"
  if [[ -n "$pid" ]]; then
    if kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
    wait "$pid" >/dev/null 2>&1 || true
  fi
}

codex_supports_interactive_resume() {
  env PATH="$REAL_CODEX_PATH" "$REAL_CODEX_BIN" resume --help >/dev/null 2>&1
}

build_resume_passthrough_args() {
  local token
  local next_idx
  local idx=0

  RESUME_PASSTHROUGH_ARGS=()

  while [[ $idx -lt ${#ORIGINAL_ARGS[@]} ]]; do
    token="${ORIGINAL_ARGS[$idx]}"

    case "$token" in
      --)
        break
        ;;
      -c|--config|--enable|--disable|-i|--image|-m|--model|--local-provider|-p|--profile|-s|--sandbox|-a|--ask-for-approval|-C|--cd|--add-dir)
        RESUME_PASSTHROUGH_ARGS+=("$token")
        next_idx=$((idx + 1))
        if [[ $next_idx -lt ${#ORIGINAL_ARGS[@]} ]]; then
          RESUME_PASSTHROUGH_ARGS+=("${ORIGINAL_ARGS[$next_idx]}")
        fi
        idx=$((idx + 2))
        ;;
      --config=*|--enable=*|--disable=*|--image=*|--model=*|--local-provider=*|--profile=*|--sandbox=*|--ask-for-approval=*|--cd=*|--add-dir=*)
        RESUME_PASSTHROUGH_ARGS+=("$token")
        idx=$((idx + 1))
        ;;
      --oss|--full-auto|--dangerously-bypass-approvals-and-sandbox|--search|--no-alt-screen)
        RESUME_PASSTHROUGH_ARGS+=("$token")
        idx=$((idx + 1))
        ;;
      -h|--help|-V|--version)
        idx=$((idx + 1))
        ;;
      -*)
        # Preserve unknown standalone-looking flags until the initial prompt.
        RESUME_PASSTHROUGH_ARGS+=("$token")
        idx=$((idx + 1))
        ;;
      *)
        break
        ;;
    esac
  done
}

read_next_prompt_from_queue() {
  local queue_dir="$1"
  local prompt_file=""

  while IFS= read -r prompt_file; do
    [[ -n "$prompt_file" ]] || continue
    break
  done < <(find "$queue_dir" -maxdepth 1 -type f -name 'inject.*.txt' -print 2>/dev/null | LC_ALL=C sort)

  if [[ -z "$prompt_file" ]]; then
    return 1
  fi

  NEXT_QUEUE_PROMPT="$(cat "$prompt_file")"
  rm -f "$prompt_file"
  return 0
}

run_resume_mode() {
  local log_path
  local queue_dir
  local injector_pid=""
  local codex_exit=0
  local session_id=""
  local -a current_cmd=()

  build_resume_passthrough_args

  log_path="$(build_log_path)"
  prepare_log_env "$log_path"

  queue_dir="$(mktemp -d "${TMPDIR:-/tmp}/taskmaster-emit.XXXXXX")"

  "$INJECTOR" \
    --follow \
    --log "$log_path" \
    --emit-dir "$queue_dir" &
  injector_pid="$!"

  PATH="$REAL_CODEX_PATH"
  export PATH

  current_cmd=("$REAL_CODEX_BIN" "${PASSTHROUGH_ARGS[@]}")

  while true; do
    "$RESUME_BRIDGE" "$queue_dir" "${current_cmd[@]}" || codex_exit=$?

    if [[ "$codex_exit" -ne "$TASKMASTER_RESUME_EXIT_CODE" ]]; then
      break
    fi

    if ! read_next_prompt_from_queue "$queue_dir"; then
      echo "Taskmaster resume transport requested relaunch without a queued prompt." >&2
      codex_exit=4
      break
    fi

    session_id="$(<"$queue_dir/session_id" 2>/dev/null || true)"
    if [[ -z "$session_id" ]]; then
      echo "Taskmaster resume transport could not determine the Codex session id." >&2
      codex_exit=4
      break
    fi

    current_cmd=("$REAL_CODEX_BIN" resume "${RESUME_PASSTHROUGH_ARGS[@]}")
    current_cmd+=("$session_id")
    current_cmd+=("$NEXT_QUEUE_PROMPT")
    codex_exit=0
  done

  cleanup_background "$injector_pid"
  rm -rf "$queue_dir"

  return "$codex_exit"
}
run_expect_mode() {
  local log_path
  local queue_dir
  local injector_pid=""
  local codex_exit=0

  log_path="$(build_log_path)"
  prepare_log_env "$log_path"

  queue_dir="$(mktemp -d "${TMPDIR:-/tmp}/taskmaster-emit.XXXXXX")"

  "$INJECTOR" \
    --follow \
    --log "$log_path" \
    --emit-dir "$queue_dir" &
  injector_pid="$!"
  PATH="$REAL_CODEX_PATH"
  export PATH

  if [[ ${#PASSTHROUGH_ARGS[@]} -gt 0 ]]; then
    "$EXPECT_INJECT_BRIDGE" "$queue_dir" "$REAL_CODEX_BIN" "${PASSTHROUGH_ARGS[@]}" || codex_exit=$?
  else
    "$EXPECT_INJECT_BRIDGE" "$queue_dir" "$REAL_CODEX_BIN" || codex_exit=$?
  fi

  cleanup_background "$injector_pid"
  rm -rf "$queue_dir"

  return "$codex_exit"
}

TASKMASTER_CODEX_TRANSPORT="${TASKMASTER_CODEX_TRANSPORT:-expect}"
case "$TASKMASTER_CODEX_TRANSPORT" in
  auto)
    run_expect_mode
    ;;
  resume)
    if ! codex_supports_interactive_resume; then
      echo "Codex CLI does not support interactive session resume on this version." >&2
      exit 4
    fi
    run_resume_mode
    ;;
  expect)
    run_expect_mode
    ;;
  *)
    echo "Unknown TASKMASTER_CODEX_TRANSPORT: $TASKMASTER_CODEX_TRANSPORT" >&2
    exit 4
    ;;
esac

exit $?
