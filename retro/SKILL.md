---
name: retro
description: Run a retrospective on a Claude Code session and propose changes to the agent's environment (steering files, skills, just/CI checks, hooks, permissions, memory) so future runs go better. Use when the user says "retro", "retrospective", "what went wrong in that session", "why did that take so long", "how do we stop that happening again", or points at a past session and asks what to change.
disable-model-invocation: true
---

# Retro

Improve the agent's **environment**, not its last answer. The environment is
everything a future agent inherits: CLAUDE.md files, memory, skills, the
justfile and CI, hooks, permissions, and the tools it can reach. A finding is
only useful if it names a concrete change to a concrete file. "The agent should
have been more careful" is not a finding.

The retro proposes. It does not apply. Changes happen after the user picks them,
through the skill that owns that part of the environment (§6).

If the session was a superpowers workflow and the user wants a bug report for
the superpowers maintainers, use `superpowers:diagnosing-superpowers` instead.

## 1. Find the session

Default to the current one. Otherwise, logs live at
`~/.claude/projects/<cwd with / and . replaced by ->/<session-id>.jsonl`, with
subagent transcripts in `<session-id>/subagents/` and oversized tool output in
`<session-id>/tool-results/`. If the user describes a session instead of naming
it, list candidates with `ls -t` and each file's last `aiTitle`, and confirm the
pick in one line.

Never Read a session log whole. Extract with jq:

```bash
f=<session>.jsonl
# titles
jq -r 'select(.type=="ai-title") | .aiTitle' "$f" | tail -1
# user prompts, with timestamps (corrections are the strongest signal)
jq -r 'select(.type=="user" and (.message.content|type)=="string") | "\(.timestamp) \(.message.content[0:300])"' "$f"
# tool calls, in order
jq -c 'select(.type=="assistant") | .message.content[] | select(.type=="tool_use") | {name, input: (.input|tostring|.[0:200])}' "$f"
# failed and denied tool calls
jq -c 'select(.type=="user") | .message.content | arrays | .[] | select(.type=="tool_result" and .is_error==true) | (.content|tostring|.[0:200])' "$f"
# largest tool results (input cost)
jq -r 'select(.type=="user") | .message.content | arrays | .[] | select(.type=="tool_result") | "\(.content|tostring|length) \(.tool_use_id)"' "$f" | sort -n | tail -10
# largest model messages (output cost); usage repeats per content block, so take the max per message
jq -sr '[.[] | select(.type=="assistant")] | group_by(.message.id) | .[] | "\(map(.message.usage.output_tokens) | max) \(.[0].timestamp)"' "$f" | sort -n | tail -10
# longest turns (wall clock)
jq -r 'select(.type=="system" and .subtype=="turn_duration") | "\(.durationMs/1000|floor)s \(.timestamp)"' "$f" | sort -n | tail -5
```

A denied call reads "The user doesn't want to proceed with this tool use".
Filter numbers with `sort -n | tail`, not `>` in awk or jq: the user's Bash
hook blocks any command containing `>`.
For a long session, hand extraction to a subagent and ask for the §2 timeline
back, so the dumps stay out of your context.

## 2. Build the timeline

A short list, not a narrative: the request, the skills invoked, the phases of
work, and where the time and tokens went. Mark every user correction (quote
it), every denied or failed call, every retry of the same command, and every
place the agent backtracked or rediscovered something it already knew.

## 3. Read the environment as it stood

The repo may have moved on since the session. Read each file at the revision
the session started from, `git show $(git rev-list -1 --before=<session start> HEAD):<path>`,
then compare with the current version. A problem already fixed since is not a
candidate; list it under "checked" in §5.

- Repo `CLAUDE.md` / `AGENTS.md`; global `~/.claude/CLAUDE.md` and `RTK.md`.
- Memory: the project's `MEMORY.md` and any memory files the session touched.
- Every SKILL.md the session invoked, plus any skill that should have fired.
- `just --list`, the `ci` recipe's dependencies, `.github/workflows/`, `devenv.nix`.
- `.claude/settings*.json` (repo and global): hooks and permissions.

## 4. Hunt

Check the timeline against each category. Each has an owner (§6) and a _use
when_ that says what in the timeline points at it.

- **Automated checks** (owner: setup-ci). Could a check have caught a mistake
  the agent made? Read `just ci` first: a check that exists but isn't in `ci`'s
  dependencies, or a workflow that doesn't run `just ci`, is the finding, not a
  reason to write a new check. A repo with no `just ci` or no CI workflow is a
  finding by itself. _Use when_ the agent shipped or nearly shipped an error a
  tool could see, or the repo has no guardrail.
- **Review** (owner: adversarial-review, de-ai). Did a defect survive the
  implement → adversarial-review loop, or did the review report something that
  wasn't real? Classify the miss. A **mechanical** pattern (banned API, import
  shape, file location) becomes a check in `just ci` or a lint rule, never
  prose. A **judgement call** becomes a rule in adversarial-review §4 if it holds
  across repos, or in the repo's `CODING_STANDARDS.md` if it's local; the
  review doesn't read that file yet, so the first such finding also proposes
  the pointer. Comment noise that survived belongs to de-ai. _Use when_ the user
  caught something the review should have, or a review finding was false.
- **Skills** (owner: superpowers:writing-skills). A skill that should have
  fired and didn't (quote the user's phrasing its description lacks); one that
  fired when it shouldn't; a step the agent skipped or bent (quote the step and
  the rationalization); a step it followed that wasted effort; two skills that
  disagree; a reference to a skill or file that doesn't exist. _Use when_ the
  session's behaviour diverged from what a skill says, or a skill's process cost
  more than it returned.
- **Steering files** (owner: direct edit). CLAUDE.md and memory are pushed into
  every context, so they should hold navigation pointers and durable facts,
  little else. Flag rules that belong in review or in a check, instructions that
  don't change behaviour (the agent does it anyway, or the session shows it
  ignored), memory that contradicts what the session found, and a durable
  correction from the user that no memory captured. _Use when_ a steering file
  is long, or the user corrected something they'll have to correct again.
- **Navigation** (owner: direct edit). How long did the agent take to find the
  right file? Is there a hidden dependency between files? Propose a one-line
  pointer in the repo CLAUDE.md. _Use when_ a search took many calls to land.
- **Tool economy** (owner: direct edit, or the tool's skill). The largest tool
  results, whole reads of big files, repeated identical commands, full-suite
  runs where a targeted one would do, subagents spawned for trivial work, one
  huge Write or message, and Bash commands that bypassed the RTK hook. _Use
  when_ a single call or pattern dominates the token count or wall clock.
- **Permissions and hooks** (owner: fewer-permission-prompts, update-config).
  Prompts or denials that stalled the run on read-only commands, or a behaviour
  the user wants every time that only a hook can guarantee. _Use when_ the log
  shows denied calls or the user repeated an "always do X" instruction.
- **Information access** (owner: direct edit or update-config). Something the
  agent needed and couldn't see: dev server output, CI logs, a service's state,
  docs behind a login. Propose teeing logs to a file, a read-only CLI, or an
  MCP. _Use when_ the agent guessed at something it could have observed.

Rules go to the review stage, not the implementation stage. The implementing
agent carries the most context pressure (exploring, writing, debugging); the
reviewer gets a diff and has room to enforce standards. Prefer a check over a
review rule, and a review rule over a CLAUDE.md instruction.

## 5. Present

In the terminal. Never publish a retro as an Artifact.

Open with the condensed §2 timeline, since every candidate's evidence points
into it. Then order candidates by severity: what the problem cost in this session, times how
likely it is to recur. For each one:

- **What happened**, with evidence: a quoted user line, a timestamp, the tool
  call.
- **The change**: the file and the concrete text or diff, not a direction.
- **Owner and category.**

Close with a numbered table (number, severity, category, file, one-line
change) so the user can pick by number. Follow it with a short "checked, no
change" list: categories that came up clean and problems already fixed since
the session. If the session went well, that list is the retro. Don't pad with weak findings; a short retro is a valid
result.

Then stop and ask which to apply.

## 6. Apply what the user picks

Route each pick to its owner:

| Change | Through |
|---|---|
| justfile, CI workflow, devenv, lint wiring | `setup-ci` |
| a skill in `~/.claude/skills/` or a repo's `.claude/skills/` | `superpowers:writing-skills`, including its test-first step |
| a plugin skill (under `~/.claude/plugins/cache/`; edits there are overwritten on update) | a note in the repo CLAUDE.md that adjusts how it's used, or an upstream report via `superpowers:diagnosing-superpowers` |
| hooks, permissions, env vars | `update-config` / `fewer-permission-prompts` |
| CLAUDE.md, CODING_STANDARDS.md, memory files | Edit directly, keeping MEMORY.md's index in step |

## Common mistakes

| Mistake | Instead |
|---|---|
| Blaming the model | Name the environment change that makes the mistake unlikely |
| A CLAUDE.md rule for a mechanical pattern | A check in `just ci`, a lint rule, or a hook |
| A new check when one exists but isn't wired | Wire the existing one into `ci` |
| Reading the jsonl into context | jq extracts, or a subagent |
| "Improve the docs" | The exact file and the text to add or cut |
| Editing files during the retro | Propose, stop, apply only what's picked |
