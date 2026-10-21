---
name: implement
description: Implement a feature, bug fix, or refactor end to end, then put the result through the de-ai and adversarial-review skills before handing it back, fixing what they find. Use whenever the user asks to implement, build, add, write, fix, or change something in a codebase that is more than a one-line edit, including casual asks like "can you add X", "wire up Y", "make this work", or "take a crack at this ticket", even if they don't mention review or cleanup.
---

# Implement

Deliver a change the user could merge without having to review it for the
things this workflow already catches: narration in comments, defects the
adversarial review would find, and behavior nobody asked for.

This skill orchestrates two others and does not restate them:

- **de-ai** — the comment standard new code is written under.
- **adversarial-review** — scope, baseline, hunt, verify, report, fix loop.

Read both SKILL.md files before writing any code. They normally live in
`.claude/skills/<name>/` in the repo or `~/.claude/skills/<name>/`. If either is
missing, tell the user which one, and continue with the rest of this workflow;
do not improvise a replacement from memory.

For a change of a few lines, keep the shape but shrink every step: a sentence of
intent, the edit, the de-ai standard, a quick self-review against the
Correctness and risk category, the checks. Don't produce ceremony larger than
the change.

## 1. Pin down what is being asked

Read the request, the ticket or issue if one is linked, and the code it touches.
Then write the **intent**: a short statement of what the change will do, what it
will deliberately not do, and how you'll know it works (the test or command that
demonstrates it).

The intent is not a formality. It becomes the "claims" that adversarial-review's
Claims versus code step checks the finished diff against, so a vague intent
produces a toothless review. Name behavior changes explicitly, including ones
that seem too small to mention.

If the request is ambiguous in a way that would change the design — two
reasonable readings that lead to different code — ask one question before
building. Otherwise state your assumption in the intent and proceed.

## 2. Record the baseline

Follow adversarial-review §2: find the project's real check commands, run them,
and record exactly what passes and fails, and how long the full suite takes.

Start the run in the background as soon as you know the commands, and finish
step 1 while it runs. Make no edits until it has finished, or the baseline
measures your change instead of the starting point.

This record is the reference for the rest of the task. "Green" anywhere below
means no new failures relative to it. When the review runs in step 4, reuse this
record as its §2 baseline instead of re-running the suite on your own changes
and calling that the baseline — a failure you introduced would otherwise be
recorded as pre-existing.

Note the starting revision (commit hash or jj change id). The review scopes to
everything after it.

## 3. Build it

Write the change under the de-ai standard from the start (its "Writing new
code" section): no narration, no step labels, no edit-history notes, a comment
only where it passes the core test. There is no separate cleanup pass; the
review's Comments category is the backstop.

While building, use adversarial-review's hunt list as a design checklist, not
just a review checklist. Before calling a piece done, ask the Correctness and
risk questions of it: what happens on the error path, who releases this
resource, can this input be hostile, does anything outside depend on what I just
changed. Write tests for the risky part — the error path, the boundary, the
compatibility case — and avoid the test defects the review lists (duplicate
coverage, testing the framework, assertions that cannot fail).

Stay inside the intent. Don't reformat untouched code, bump dependencies, or
tidy neighbouring files. The review will flag all of it as unrelated churn, and
it makes the change harder to review and revert.

**Build independent parts in parallel.** If the intent splits into parts that
touch disjoint files and none uses an interface another part creates, dispatch
one subagent per part, all in one message, each with `isolation: "worktree"`.
Give each the intent, its part, the exact interfaces it must produce or may use,
and the path to the de-ai skill. Merge their branches in order; the full-suite
run below then covers the merged result. A merge conflict means the parts weren't independent:
finish the conflicting part yourself on the merged tree. Parts that share a file
or an interface are built in sequence.

Run the fast checks as you go. Run the full suite before moving on, and fix
anything new before step 4.

**Commits.** Follow what the user asked for and the repo's conventions. If
neither says, in git leave the change uncommitted; in jj, work in a new change
on top of the starting revision. If you do commit, make each commit one logical
step that passes checks on its own, since the review's §8 walk verifies exactly
that.

## 4. Adversarial self-review

Run adversarial-review over the range from the starting revision to the tip (or
the working-copy diff, if uncommitted), with the step-1 intent as the
description it checks claims against and the step-2 record as its baseline.

You wrote this code, which is the worst position to review it from: you know
what it's supposed to do, so you read what you meant instead of what's there.
Counter that:

- **If the environment can spawn a subagent, run the review in one.** Give it
  the range, the intent, the baseline record, and the path to the
  adversarial-review skill, and nothing about your reasoning while building.
  Its findings come back to you for step 5.
- **Otherwise, review from the diff, not from memory.** Re-read the intent,
  then read the diff and the whole touched files cold, as if a colleague wrote
  them. When you catch yourself thinking "that's handled because I…", find the
  line that handles it.

Scope the review's Comments category to lines this change added or modified.
Pre-existing comments elsewhere in a touched file are out of scope: removing
them would be unrelated churn. If there is heavy noise outside the change,
mention it in the final report as a possible follow-up.

The review's rule against padding matters more here, not less. A self-review
that invents findings to look rigorous wastes a fix cycle; one that finds
nothing after honest verification is a good result.

## 5. Fix what the review found

The user asked for a working implementation, so fixing findings in your own
unpushed work is already authorized: skip the review's "report, then stop" and
go straight into its §7 fix loop in batch mode. Work blocking findings first,
then should-fix. Apply nits only where the recommended option is clearly better,
and list the rest.

Two constraints carry over unchanged from the review skill and are not waived by
this one:

- Commits that someone else authored or that are already pushed are not yours to
  rewrite. If a finding points into them, report it instead of fixing it.
- Rewriting git history (the autosquash in `references/git.md`) still needs the
  user's explicit authorization. If you committed in git, leave fixups in place
  and ask in the final report. Absorbing into your own unpushed jj stack is fine.

If the change is uncommitted, there is nothing to absorb and §8 does not apply:
the full-suite run after the last fix group is the final check.

Every fix is new code, so it is written under the de-ai standard too.

**Bound the loop.** After fixing, re-review only the fix hunks, not the whole
change again, including the Comments category: fix loops are where
edit-history comments ("fixed the null case", "now handles…") creep in. If that
second pass finds a new blocking issue, fix it and stop there; report anything
further as open rather than starting a third round. A fix that keeps breaking
something else means the design is wrong, and that is the user's call.

## 6. Hand back

Keep it short. The user wants to know what changed and what to look at, not a
retelling of the workflow.

1. **What was built** — the intent, amended if it changed along the way, with
   any assumption you made called out.
2. **Checks** — baseline versus now, in the same terms: which checks pass, and
   confirmation that nothing new fails. Name any pre-existing failures so they
   aren't mistaken for yours.
3. **Review outcome** — how many findings, how many fixed, and the review's
   numbered table for anything left open (blocked, deferred, unverified, or
   declined nits with their alternatives). If nothing survived verification,
   say so in one line.
4. **Decisions for the user** — anything that needs them: history rewrites
   awaiting authorization, exported names worth renaming, findings in code you
   weren't allowed to touch, out-of-scope comment noise worth a follow-up.

Don't push. Pushing is always the user's call, asked each time.
