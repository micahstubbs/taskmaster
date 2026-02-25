# Lessons Learned

Append-only log of debugging insights and non-obvious solutions.

---

## 2026-02-25T14:00 - Claude Code hook `reason` is dual-use: user-visible AND AI context

**Problem**: The taskmaster stop hook embedded a full 5-item completion checklist in the `reason` field of `{ "decision": "block", "reason": "..." }`. Every stop attempt printed the entire checklist to the user's terminal.

**Root Cause**: Claude Code's stop hook `reason` field serves two purposes simultaneously — it is displayed to the user in the terminal UI ("Stop hook error: ...") AND injected back into the AI conversation as context. Putting verbose instructions in `reason` to inform the AI caused them to also appear as user-visible output.

**Lesson**: The `reason` field is not a private AI channel. Anything in `reason` is shown to the human. Persistent AI instructions belong in SKILL.md (system context loaded at session start), not in transient hook `reason` values. The `reason` should carry only the minimum transient signal the agent needs right now.

**Code Issue**:
```bash
# Before (verbose — full checklist in reason, shown to user)
REASON="${LABEL}: ${PREAMBLE}

Before stopping, do each of these checks:
1. RE-READ THE ORIGINAL USER MESSAGE(S)...
2. CHECK THE TASK LIST...
[etc]"
jq -n --arg reason "$REASON" '{ decision: "block", reason: $reason }'

# After (minimal — only the done signal; checklist lives in SKILL.md)
DONE_SIGNAL="${DONE_PREFIX}::${SESSION_ID}"
jq -n --arg reason "$DONE_SIGNAL" '{ decision: "block", reason: $reason }'
```

**Solution**: Strip the checklist from `reason`. Put it only in SKILL.md, which is always loaded as system context. The `reason` now contains only the done signal token the agent must emit.

**Prevention**: When designing Claude Code hooks, ask: "Does this text need to be in the reason, or is it already in system context?" If it's in a skill file, it doesn't belong in `reason`.

---

## 2026-02-25T14:30 - `last_assistant_message` is faster than transcript scanning for done-signal detection

**Problem**: The hook was opening and scanning potentially large transcript JSON files on every stop attempt to detect whether the agent had emitted the done signal.

**Root Cause**: The hook relied exclusively on transcript-file parsing, which requires disk I/O and JSON scanning on every invocation.

**Lesson**: The Claude Code hook input JSON exposes `last_assistant_message` directly. Checking that field is O(1) and avoids the file read in the common case (agent just emitted the signal in its latest message).

**Code Issue**:
```bash
# Before (always scans transcript file)
if tail -400 "$TRANSCRIPT" 2>/dev/null | grep -Fq "$DONE_SIGNAL"; then
  HAS_DONE_SIGNAL=true
fi

# After (fast path via last_assistant_message, transcript as fallback)
LAST_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // ""')
if [ -n "$LAST_MSG" ] && echo "$LAST_MSG" | grep -Fq "$DONE_SIGNAL" 2>/dev/null; then
  HAS_DONE_SIGNAL=true
fi
if [ "$HAS_DONE_SIGNAL" = false ] && [ -f "$TRANSCRIPT" ]; then
  if tail -400 "$TRANSCRIPT" 2>/dev/null | grep -Fq "$DONE_SIGNAL"; then
    HAS_DONE_SIGNAL=true
  fi
fi
```

**Prevention**: Always check `last_assistant_message` before falling back to transcript file parsing in stop hooks.
