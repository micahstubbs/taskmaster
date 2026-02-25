# Cleaning up taskmaster's terminal output

**2026-02-25**

I built [taskmaster](https://github.com/micahstubbs/taskmaster) a few months ago to solve a real problem: Claude Code would sometimes stop working before actually finishing a task. The stop hook forces the agent to keep going until it emits an explicit `TASKMASTER_DONE::<session_id>` signal — a parseable token that gives external tooling a deterministic completion marker.

It works. But the terminal output was a mess.

## The problem

Every time the hook blocked a stop, Claude Code would display the full completion checklist in the user-visible terminal output:

```
● Ran 9 stop hooks (ctrl+o to expand)
  ⎿  Stop hook error: TASKMASTER (1/100): Verify that all work is truly complete
  before stopping.

  Before stopping, do each of these checks:

  1. RE-READ THE ORIGINAL USER MESSAGE(S). List every discrete request...
  2. CHECK THE TASK LIST. Review every task. Any task not marked completed?...
  3. CHECK THE PLAN. Walk through each step...
  4. CHECK FOR ERRORS. Did any tool call, build, test, or lint fail?...
  5. CHECK FOR LOOSE ENDS. Any TODO comments, placeholder code...
```

That's a 15-line wall of text every time the hook fires. In a long session with multiple stop attempts, this pollution accumulates. The checklist is instructions *for the AI*, not the user — it doesn't need to be on screen.

## How Claude Code hook reasons work

Claude Code stop hooks return a JSON object when they want to block:

```json
{ "decision": "block", "reason": "..." }
```

The `reason` field serves two purposes simultaneously:

1. **User-visible terminal output** — shown in the UI as a "Stop hook error"
2. **AI context** — injected back into the conversation so the agent knows why it was blocked

This dual-use is the root of the problem. If you put the full instructions in `reason` so the AI has them, the user sees a wall of text. But you need the AI to know what to do.

## The fix: separate instructions from signal

The key insight: the AI already has the full completion checklist in system context via `SKILL.md`. Every Claude Code skill file is loaded at session start — the agent knows what to do when blocked without being told again in the hook reason.

So the hook reason only needs to contain one thing: the done signal token the agent must emit to satisfy the hook.

```bash
DONE_SIGNAL="${DONE_PREFIX}::${SESSION_ID}"

jq -n --arg reason "$DONE_SIGNAL" '{ decision: "block", reason: $reason }'
```

Now the terminal shows at most one collapsed line:

```
● Ran N stop hooks (ctrl+o to expand)
  ⎿  Stop hook error: TASKMASTER_DONE::abc123xyz
```

The agent sees the done signal it needs to emit. The user sees almost nothing. Both get what they need.

## Improving the done-signal detection

While I was in the hook, I also upgraded how it detects the done signal. The old version parsed the transcript file — opening and scanning potentially hundreds of lines of JSON on every stop attempt.

The newer Claude Code API exposes `last_assistant_message` directly in the hook's JSON input. Checking that first is much faster and avoids the transcript entirely in the happy path:

```bash
LAST_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // ""')
if [ -n "$LAST_MSG" ] && echo "$LAST_MSG" | grep -Fq "$DONE_SIGNAL" 2>/dev/null; then
  HAS_DONE_SIGNAL=true
fi

# Fallback to transcript only if needed
if [ "$HAS_DONE_SIGNAL" = false ] && [ -f "$TRANSCRIPT" ]; then
  if tail -400 "$TRANSCRIPT" 2>/dev/null | grep -Fq "$DONE_SIGNAL"; then
    HAS_DONE_SIGNAL=true
  fi
fi
```

## The broader lesson

When designing hooks and other automation that wraps AI agents, it helps to keep user-visible output and AI-context separate. System context (skills, CLAUDE.md) is the right place for persistent instructions. Hook reasons are for transient signals — the specific thing the agent needs right now to unblock itself.

In this case: "emit `TASKMASTER_DONE::abc123` to stop." That's it.

The full completion checklist is still there, still enforced, still directing the agent's behavior. It's just not cluttering the terminal anymore.

The changes shipped as [v2.3.0](https://github.com/micahstubbs/taskmaster/releases/tag/v2.3.0).
