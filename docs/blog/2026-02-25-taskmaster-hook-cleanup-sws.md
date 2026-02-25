# Cleaning up taskmaster's terminal output

**2026-02-25**

I built [taskmaster](https://github.com/micahstubbs/taskmaster) a few months ago to stop Claude Code from quitting early. The stop [hook](https://github.com/micahstubbs/taskmaster/blob/main/check-completion.sh) fires every time the agent tries to stop and blocks it until it emits an explicit `TASKMASTER_DONE::<session_id>` token — a parseable signal that lets external tooling know the agent genuinely finished.

It works well. The terminal output, though, had gotten out of hand.

#### The problem: a wall of text on every stop attempt

Every time the hook blocked a stop attempt, Claude Code would dump the full completion checklist into the terminal:

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

Fifteen lines of text, every time. In a long session with multiple blocked stops, that accumulates fast. The checklist is instructions *for the AI* — the user never needed to see it.

#### The dual-use trap in Claude Code hook reasons

Claude Code stop hooks return a JSON object when they want to block a stop:

```json
{ "decision": "block", "reason": "..." }
```

The `reason` field does two things at once:

1. **User-visible output** — displayed in the terminal as a "Stop hook error"
2. **AI context** — injected back into the conversation so the agent knows why it was blocked and what to do next

That dual-use created the problem. To give the AI its instructions, I was putting the full checklist in `reason`. Which meant the user was also seeing the full checklist. Every. Single. Time.

#### The fix: skill files are already system context

Here's what I was missing: the AI already has the full completion checklist. Every Claude Code [skill file](https://github.com/micahstubbs/taskmaster/blob/main/SKILL.md) is loaded into system context at session start. The agent doesn't need the checklist repeated in the hook reason — it's already there.

The hook reason only needs to communicate one thing: the specific done signal the agent must emit to satisfy the hook.

```bash
DONE_SIGNAL="${DONE_PREFIX}::${SESSION_ID}"

jq -n --arg reason "$DONE_SIGNAL" '{ decision: "block", reason: $reason }'
```

Now the terminal shows a single collapsed line:

```
● Ran N stop hooks (ctrl+o to expand)
  ⎿  Stop hook error: TASKMASTER_DONE::abc123xyz
```

The agent sees the exact signal it needs to emit. The user sees almost nothing. Both get what they need from the same field.

#### Also improved: done-signal detection

While I was in there I also improved how the hook detects the done signal. The old version parsed the transcript file every time — opening and scanning potentially hundreds of lines of JSON on every stop attempt.

The Claude Code hook API exposes `last_assistant_message` directly in the hook's input JSON. Checking that first is much faster:

```bash
LAST_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // ""')
if [ -n "$LAST_MSG" ] && echo "$LAST_MSG" | grep -Fq "$DONE_SIGNAL" 2>/dev/null; then
  HAS_DONE_SIGNAL=true
fi

# Fallback to transcript scan only if needed
if [ "$HAS_DONE_SIGNAL" = false ] && [ -f "$TRANSCRIPT" ]; then
  if tail -400 "$TRANSCRIPT" 2>/dev/null | grep -Fq "$DONE_SIGNAL"; then
    HAS_DONE_SIGNAL=true
  fi
fi
```

In the common case — where the agent just emitted the done signal in its last message — no transcript parsing happens at all.

#### Separating user output from AI instructions

The broader lesson for hook design: user-visible output and AI instructions have different lifetimes and audiences. System context (skill files, `CLAUDE.md`) is the right home for persistent instructions that shape the agent's behavior across a whole session. Hook reasons are for transient, stop-specific signals — the minimum information the agent needs right now to know what to do next.

In this case that's: "emit `TASKMASTER_DONE::abc123` and you can stop." That's the whole message.

The checklist still runs. The enforcement is still there. It's just not printing to your terminal anymore.

These changes shipped as [v2.3.0](https://github.com/micahstubbs/taskmaster/releases/tag/v2.3.0).
