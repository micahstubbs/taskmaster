# Cleaning up taskmaster's terminal output

**2026-02-25**

I built [taskmaster](https://github.com/micahstubbs/taskmaster) a few months ago to stop Claude Code from quitting early. The stop [hook](https://github.com/micahstubbs/taskmaster/blob/main/check-completion.sh) fires every time the agent tries to stop and blocks it until it emits an explicit `TASKMASTER_DONE::<session_id>` token — a parseable signal that confirms the agent actually finished.

It works. The terminal output, though, was a mess.

#### The problem

Every time the hook blocked a stop attempt, Claude Code dumped the full completion checklist into the terminal:

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

Fifteen lines, every time, accumulating across a long session. The checklist is instructions *for the AI* — I never needed to read it.

#### How the `reason` field works

Claude Code stop hooks return JSON when they want to block a stop:

```json
{ "decision": "block", "reason": "..." }
```

The `reason` field does two things at once:

1. **User-visible output** — shown in the terminal as a "Stop hook error"
2. **AI context** — injected back into the conversation so the agent knows what to do next

I was putting the full checklist in `reason` so the agent had its instructions. Which meant I was also printing the full checklist to my terminal. Every single stop attempt.

#### What I was missing

The AI already has the checklist. Every Claude Code [skill file](https://github.com/micahstubbs/taskmaster/blob/main/SKILL.md) loads into system context at session start. The agent doesn't need instructions repeated in the hook reason — it just needs to know the specific token to emit.

So I stripped the reason down to exactly that:

```bash
DONE_SIGNAL="${DONE_PREFIX}::${SESSION_ID}"

jq -n --arg reason "$DONE_SIGNAL" '{ decision: "block", reason: $reason }'
```

Now the terminal shows one collapsed line:

```
● Ran N stop hooks (ctrl+o to expand)
  ⎿  Stop hook error: TASKMASTER_DONE::abc123xyz
```

The agent sees the signal it needs. I see almost nothing. Both of us get what we need from the same field.

#### Faster signal detection too

While I was in there I also changed how the hook detects the done signal. The old version opened the transcript file and scanned potentially hundreds of lines of JSON on every stop attempt.

The Claude Code hook API passes `last_assistant_message` directly in the hook's input JSON. Checking that first skips the file read in the common case:

```bash
LAST_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // ""')
if [ -n "$LAST_MSG" ] && echo "$LAST_MSG" | grep -Fq "$DONE_SIGNAL" 2>/dev/null; then
  HAS_DONE_SIGNAL=true
fi

# Only scan the transcript if the message check didn't match
if [ "$HAS_DONE_SIGNAL" = false ] && [ -f "$TRANSCRIPT" ]; then
  if tail -400 "$TRANSCRIPT" 2>/dev/null | grep -Fq "$DONE_SIGNAL"; then
    HAS_DONE_SIGNAL=true
  fi
fi
```

When the agent just emitted the done signal in its last message — the normal case — no transcript parsing happens.

#### The lesson

Hook reasons and system context have different jobs. System context (skill files, `CLAUDE.md`) carries persistent instructions that shape behavior across a whole session. Hook reasons carry transient, stop-specific information — the minimum the agent needs right now.

Here that's: "emit `TASKMASTER_DONE::abc123` and you're done."

The checklist still runs. The enforcement is unchanged. It just doesn't print to my terminal anymore.

These changes shipped as [v2.3.0](https://github.com/micahstubbs/taskmaster/releases/tag/v2.3.0).
