# Changelog

All notable changes to Taskmaster are documented here.

## [2.3.0] - 2026-02-25

### Changed
- Hook `reason` field now contains only the TASKMASTER_DONE signal token instead
  of the full completion checklist. This keeps user-visible terminal output
  minimal — one collapsed line rather than a wall of text.
- Full completion checklist lives exclusively in SKILL.md, which is always
  loaded as system context. The agent already has all instructions; the reason
  field no longer needs to duplicate them.
- Added `last_assistant_message` as the primary done-signal detection path
  (faster, no transcript file parsing required). Transcript-based check is
  retained as fallback.
- Removed `HAS_RECENT_ERRORS` / `stop_hook_active` escape-hatch logic in favor
  of the explicit TASKMASTER_DONE signal protocol.
- `hooks/check-completion.sh` brought in sync with root-level canonical source.

## [2.2.0] - 2026-02-19

### Changed
- Default `TASKMASTER_MAX` set to 100 (previously 0 / infinite).
- Moved full completion checklist from hook `reason` into SKILL.md system
  context (first pass; reason still contained a short prompt).
- `install.sh` made POSIX-portable (`sh` shebang, conditional `pipefail`).

### Fixed
- Resolved infinite loop caused by `set -euo pipefail` in sh-sourced contexts.

## [2.1.0]

### Added
- Session-scoped counter with configurable `TASKMASTER_MAX` escape hatch.
- Subagent skip: transcripts shorter than 20 lines are ignored.
- `TASKMASTER_DONE_PREFIX` env var for customising the done token prefix.

## [2.0.0]

### Added
- TASKMASTER_DONE signal protocol: stop is allowed only after the agent emits
  `TASKMASTER_DONE::<session_id>` in its response.
- Transcript-based done-signal detection.

## [1.0.0]

### Added
- Initial release: stop hook that blocks agent from stopping prematurely.
- Completion checklist injected via hook `reason` field.
- `TASKMASTER_MAX` loop guard.
