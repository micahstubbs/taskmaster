#!/usr/bin/env bash
#
# Tests for taskmaster-state.sh.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_ROOT/taskmaster-state.sh"

# Isolate state under a temp dir
TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/taskmaster-state-test.XXXXXX")"
trap 'rm -rf "$TEST_HOME"' EXIT
export TASKMASTER_STATE_DIR="$TEST_HOME/state"

# shellcheck disable=SC1090
source "$LIB"

PASS=0; FAIL=0
ok() { printf 'ok  %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf 'FAIL %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

# --- init creates well-formed JSON with schema_version=1 ---
SID="sess-$$"
taskmaster_state_init "$SID"
PATH_OUT="$(taskmaster_state_path "$SID")"
[[ -f "$PATH_OUT" ]] && ok "init creates file" || fail "init creates file"
SV="$(jq -r .schema_version <"$PATH_OUT")"
[[ "$SV" == "1" ]] && ok "schema_version is 1" || fail "schema_version is 1 (got $SV)"
SI="$(jq -r .session_id <"$PATH_OUT")"
[[ "$SI" == "$SID" ]] && ok "session_id stamped" || fail "session_id stamped"
SC="$(jq -r .stop_count <"$PATH_OUT")"
[[ "$SC" == "0" ]] && ok "stop_count starts at 0" || fail "stop_count starts at 0 (got $SC)"

# --- increment ---
taskmaster_state_increment_stop_count "$SID"
SC="$(jq -r .stop_count <"$PATH_OUT")"
[[ "$SC" == "1" ]] && ok "stop_count after one increment is 1" || fail "increment 1 (got $SC)"

taskmaster_state_increment_stop_count "$SID"
taskmaster_state_increment_stop_count "$SID"
SC="$(jq -r .stop_count <"$PATH_OUT")"
[[ "$SC" == "3" ]] && ok "stop_count after three increments is 3" || fail "increment 3 (got $SC)"

# --- concurrent increments ---
SID2="sess-conc-$$"
taskmaster_state_init "$SID2"
PATH_C="$(taskmaster_state_path "$SID2")"
N=50
for i in $(seq 1 "$N"); do
  ( taskmaster_state_increment_stop_count "$SID2" ) &
done
wait
SC="$(jq -r .stop_count <"$PATH_C")"
[[ "$SC" == "$N" ]] && ok "concurrent $N increments reach $N" \
  || fail "concurrent increments lost some (got $SC, expected $N)"

# --- legacy migration ---
LEGACY_DIR="${TMPDIR:-/tmp}/taskmaster"
mkdir -p "$LEGACY_DIR"
SID3="sess-legacy-$$"
LEGACY_FILE="$LEGACY_DIR/$SID3"
echo "7" > "$LEGACY_FILE"

# State doesn't exist yet; migration should pull the 7
taskmaster_state_migrate_legacy_counter "$SID3"
[[ -f "$(taskmaster_state_path "$SID3")" ]] && ok "legacy migration creates state file" \
  || fail "legacy migration creates state file"
SC="$(jq -r .stop_count <"$(taskmaster_state_path "$SID3")")"
[[ "$SC" == "7" ]] && ok "legacy counter value migrated" \
  || fail "legacy counter value migrated (got $SC, expected 7)"
[[ ! -f "$LEGACY_FILE" ]] && ok "legacy file deleted after migration" \
  || fail "legacy file deleted after migration"

# --- migration is idempotent (rerun without legacy file is a no-op) ---
taskmaster_state_migrate_legacy_counter "$SID3"
SC="$(jq -r .stop_count <"$(taskmaster_state_path "$SID3")")"
[[ "$SC" == "7" ]] && ok "second migration call is a no-op" \
  || fail "second migration mutated state (got $SC)"

# --- jq read of nonexistent path returns null ---
SID4="sess-empty-$$"
VAL="$(taskmaster_state_jq "$SID4" '.latest_user_prompt.prompt' 2>/dev/null || echo "MISSING")"
[[ "$VAL" == "null" || -z "$VAL" || "$VAL" == "MISSING" ]] && ok "nonexistent path read is safe" \
  || fail "nonexistent path read is safe (got $VAL)"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" == 0 ]]
