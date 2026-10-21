---
name: grill-me
description: Interview the user relentlessly about a plan, task, or design until there is zero ambiguity about what we are building and why, then produce a written alignment brief the user must approve before any work begins. Use when the user says "grill me", wants to stress-test a plan, wants to make sure we're aligned or on the same page, asks to clarify requirements before starting, or kicks off any substantial task where misunderstanding would be costly.
---

# Grill Me

The goal is zero ambiguity between us about what we are trying to accomplish. Misalignment is expensive: work built on a misunderstanding gets thrown away. So we align fully before anything is built, and the proof of alignment is a written brief I approve.

## Order of questioning

Resolve the top of the tree before the branches. Don't discuss implementation until the goal is locked.

1. **Outcome**: What problem are we solving, and for whom? Why does it matter now?
2. **Definition of done**: How will we know it worked? Push for concrete, checkable success criteria.
3. **Scope**: What is explicitly in, and what is explicitly out (non-goals)?
4. **Constraints**: Deadlines, tech, compatibility, performance, budget, things that must not change.
5. **Design decisions**: Walk each branch, resolving dependencies between decisions one by one.
6. **Risks and edge cases**: What could go wrong, and what should happen when it does?

## How to ask

- Ask one question at a time and wait for my answer. Multiple questions at once are bewildering.
- With each question, give your recommended answer and a one-line reason, so I can simply confirm when I agree.
- Prioritize by consequence. Before asking, check: would different answers lead to different work? If not, skip it or note it as a minor assumption. Ask about irreversible and high-impact decisions first.
- When I use a vague term ("fast", "simple", "robust", "users"), pin it down to something concrete and testable.
- State your own assumptions out loud. Every assumption that could change the work becomes a question.
- If a *fact* can be found by exploring the codebase or available context, look it up instead of asking, and tell me what you found in one line so I can correct it if it's wrong. *Decisions* are mine. Put each one to me.
- A question whose answer changes what a field, function or event *means* includes a **Readers** list: every place in the source and the tests that reads it, found by searching for the name, each marked *unchanged*, *changes how* or *breaks*. Show the list in the question, so I can see what the new meaning touches.
- If I say "I don't know", help me reason it through or propose a default. If I say "you decide", make the call and log it as a delegated decision.
- If a new answer conflicts with an earlier one, stop and resolve the conflict before moving on.
- Every few decisions, give a two- or three-line recap of what's been settled.

## Finishing: the alignment brief

When no material ambiguity remains, first restate the whole plan in your own words (teach-back) and ask me to correct anything. Then write the brief:

- **Goal**: one or two sentences
- **Success criteria**: checkable conditions that mean "done"
- **In scope / Out of scope**
- **Constraints**
- **Decisions**: each decision, and who made it (me, or delegated to you)
- **Assumptions**: anything not explicitly confirmed
- **Open questions**: should be empty; if not, we aren't done

If working in a codebase, save the brief to a file (e.g. `ALIGNMENT.md`) so it stays available throughout the work.

## Rules

- Do not begin any work until I explicitly approve the brief. Silence or "sounds good" mid-interview is not approval of the whole plan.
- During execution, if something comes up that the brief doesn't cover, or that contradicts it, stop and ask. Don't guess. Update the brief with the answer.
