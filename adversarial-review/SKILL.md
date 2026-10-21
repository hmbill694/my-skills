---
name: adversarial-review
description: Review a code change adversarially, assuming it is wrong until proven otherwise, and verify every finding before reporting it. Covers correctness and risk (error paths, security, compatibility), behavior the commit message doesn't claim, dead code, comment defects, useless tests, and non-idiomatic code, with an optional fix loop that absorbs each fix into the commit that introduced it. Use whenever the user asks to review, critique, audit, or sanity-check a branch, PR, commit range, stack, or diff, including casual asks like "look over this before I merge" or "anything wrong with my PR?", and when asked to fix findings from such a review.
---

# Adversarial review

Review a change set on the assumption that it is incorrect. Every line is a claim
to be disproved, not a fact to be accepted.

Two failure modes to avoid, in order of cost:

1. **Reporting a finding that isn't real.** This is the expensive one. It burns
   the user's attention and teaches them to distrust the whole report. Verify
   before reporting — see §5, which is the most important section here.
2. **Missing a real defect.** Cheaper, but the reason for the adversarial stance.

Do not manufacture findings to look thorough. A short report of confirmed
defects beats a long one padded with speculation. If a section of the change is
genuinely fine, say so and move on.

Print every command that changes the working copy or history as you run it, so
the user can follow and undo.

## 1. Scope the change exactly

Establish the precise revision range before reading anything. Do not guess, and
do not trust a local branch name to mean what it looks like.

- **git:** `git log --oneline <base>..HEAD`, then `git diff --stat <base>...HEAD`
- **jj:** `jj log -r '<base>..<bookmark>'`, then `jj diff --from <base> --to <tip> --stat`
- **PR:** `gh pr diff <n>` and `gh pr view <n>`

A local `main` often lags the remote. Resolve the real merge base (`main@origin`,
`origin/main`) and confirm the resulting commit list matches what the user
believes is in the change. If it doesn't, say so before continuing — you may be
reviewing more or less than they think.

Note who authored the commits and whether they are pushed. This decides what
§7 may do later.

## 2. Establish the baseline before forming opinions

Run the project's check suite at the tip *first*: tests, linter, formatter
check, type checker. Find the real commands (Makefile, justfile, package.json,
CI config) rather than inventing them. If the project has none, say so; the
review still proceeds, but §7 fixes will be verified by targeted runs only.

Record the result as a set, not a colour: which checks pass, and exactly which
tests or diagnostics fail. A failure that predates the change is not a finding
about the change, and "green" for the rest of this review means **no new
failures relative to this record**, not zero failures.

Note how long the full suite takes. §7 uses that to choose how often to run it.

## 3. Read whole files, not just the diff

The diff shows what changed. The defects are frequently in what stayed.

Read every file the change touches, end to end. Dead helpers, parallel data
structures that can drift, and duplicated tests are invisible in a diff and
obvious in a file.

Skip generated, vendored, and lock files beyond checking whether they belong in
the change at all (§4, unrelated churn). For a very large file, read the touched
regions, the whole enclosing class or section, and every caller of a changed
symbol, then say in the report that you read it selectively.

Then read what the change imports and calls, at least the parts it uses. You
cannot judge whether a wrapper is redundant, whether a constant belongs where it
sits, or whether a helper already exists in a shared library, without reading
the thing being wrapped.

## 4. Hunt

Walk every touched file against every category below, in the order listed; the
order is roughly the order of cost if missed. A file is done when each category
has been checked against it, not when the first finding appears. On a large
change, run the first two categories across every file before starting the
rest, so the review's time goes where the damage is.

### Correctness and risk
- **Error paths.** Exceptions swallowed or broadened, errors logged and then
  ignored, a failure that leaves state half-written, retries without a bound.
- **Resources.** Files, connections, locks, subscriptions acquired without a
  guaranteed release on every path.
- **Untrusted input.** Anything from a user, file, network, or environment
  reaching a query, shell, path, template, or deserializer without validation.
  Secrets or credentials added to code, config, fixtures, or logs. Authorization
  checks moved, weakened, or skipped on a new path.
- **Concurrency.** Shared mutable state touched from more than one task or
  thread, check-then-act races, ordering assumptions nothing enforces.
- **Performance.** A query or call inside a loop, a quadratic scan over input
  that can grow, work moved onto a hot or request path.
- **Compatibility.** Changes to anything outside callers depend on: public
  function signatures, CLI flags, config keys, environment variables, database
  schemas and migrations, serialized formats, wire protocols. Ask whether old
  data, old clients, and a rollback all still work.

### Claims versus code
The commit message, PR description, and any new docstring are claims about what
the change does. For each claim, find the line that delivers it. Then invert:
for each behavior the diff actually changes, find the sentence that announces
it. A behavior change nobody mentioned, especially one riding inside a commit
labeled "refactor" or "cleanup", is among the highest-value findings this review
produces. Check the boundaries the change introduces — empty input, the first
and last element, the error path — since those are where a claim and its code
part ways.

### Dead code
For every symbol the change adds or leaves behind, grep the entire repo for
uses. Test-support modules are the usual hiding place: a fake or helper that
nothing imports. Grep, never eyeball. Watch for a symbol whose only "uses" are
its own definition and a same-named local in another file.

### Unrelated churn
Lockfiles, formatter-wide reflows, editor config, dependency bumps nobody asked
for. Check whether each touched file has anything to do with the stated purpose.
Churn bundled into a feature commit makes the change harder to review and harder
to revert. Check for a stripped trailing newline while you're there.

### Comments — four distinct defects, do not conflate them
- **Narration.** Restates what the code plainly says, or names the exact API
  calls a reader can see. Delete.
- **Misdirection.** A docstring on `A` that explains behavior implemented in
  `B`. A reader chasing that mechanism lands in the wrong place and finds
  nothing. Move it to where the decision actually lives.
- **Repetition.** The same rationale restated in many places — module docstring,
  function docstring, README, test docstring. Find the single site that owns the
  fact and cut the rest. Count the copies explicitly; the number is usually
  higher than anyone expects.
- **Overclaim.** A comment asserting something about runtime behavior, library
  defaults, or limits. This is a testable hypothesis. Test it (§5).

Also flag aphorism and editorializing — prose that sounds wise but carries no
information a reader can act on.

### Tests
- **Missing coverage for the risky part.** The error path, the boundary, or
  the compatibility case from the first category, with no test that would fail
  if it regressed.
- **Duplicate coverage.** Two tests exercising the same branch through different
  entry points. Ask what the second one can catch that the first cannot. If the
  answer is nothing, it's redundant.
- **Testing the framework.** Asserting that the serialization library drops
  unknown fields, or that the web framework routes. That's the dependency's job.
  If the contract genuinely matters, the test belongs next to the type it
  constrains, not in a caller's suite.
- **Assertions that cannot fail.** Trace whether the asserted state is reachable.
  An assertion after an expected-raise, checking that nothing happened, when the
  raise occurs on the first line, proves nothing.
- **Names that overpromise.** A name claiming ordering, timing, or causation the
  body never observes. Either strengthen the body or rename.
- **Fixtures with realistic personal data.** Names, emails, street addresses,
  phone numbers. Even when synthetic, they get copied forward into other
  fixtures and read as real. Prefer reserved domains (`example.com`) and
  obviously-fake identities. Flag it; don't silently rewrite.
- **Fixture bulk.** A very large literal used by one assertion. Judge honestly:
  for code whose whole job is passing data through unaltered, a realistic
  payload with a whole-value equality check is the *right* test and should stay.

### Idiom and functional patterns
Look for constructs the language offers a better form of — sentinel checks that
a binding-in-condition removes, parallel collections that should be one
collection with derived views, a loop over a one-element structure, manual
accumulation where a comprehension reads better, configuration threaded through
call after call where partial application or a closure fits.

Two rules govern this category:

- Only propose what is idiomatic *in this language and this codebase*. Check
  whether the pattern already appears in the repo. A functional idiom
  transplanted from another language is a defect, not an improvement.
- Say explicitly where *not* to functionalize. Some loops resist it: early
  return on first failure, an accumulating side effect, two distinct exception
  paths. If you sketched a rewrite and it read worse, report that you tried and
  why the imperative form wins. This stops someone else from attempting it
  later, which makes it as valuable as the changes you do propose.

### References that don't resolve
Links in docs, paths in comments, entry points named in READMEs. Verify each
resolves **at the change's revision**, not merely on disk. A directory present
in the working tree may be untracked leftovers from another branch — check with
`git ls-files` / `jj file list -r <rev>`, and inspect what's actually inside it.

## 5. Verify every finding before reporting it

Kill any finding you cannot reproduce. This section exists because the most
plausible-sounding findings are the ones that turn out to be wrong.

- **Type-checker or linter claims:** reproduce *inside the project tree*, under
  the project's real configuration. A scratch file in a temp directory is
  frequently outside the tool's `include`/`exclude` paths and will pass silently
  under default settings, telling you nothing. If you are about to claim "this
  annotation is unnecessary," delete it in place, run the real command, and read
  the output.
- **Library behavior and defaults:** execute it against the version the project
  actually pins. Defaults change between releases, so memory is not evidence.
- **Behavioral claims, including correctness and risk findings:** drive the
  code path with the input you think breaks it — a throwaway test, a REPL call,
  a script in the scratch directory. A reading of the code is a hypothesis; the
  run is the evidence. Where a run is impossible (a race, a production-only
  path, a migration against real data), report the finding as unverified, say
  what would confirm it, and rank it no higher than its evidence supports.
- **Dead code:** grep the whole repo.
- **File or link existence:** check at the revision, per §4.
- **Duplicate tests:** identify the specific line of production code both reach,
  and confirm nothing sits between them that only one exercises.

If a check contradicts your finding, drop it and say so plainly when you report.
If you already reported it, correct it in one sentence and move on — no
extended apology, no re-litigating.

Clean up scratch files and throwaway tests before moving on; under jj they will
otherwise be snapshotted into the working-copy change.

## 6. Report

Lead with the baseline result, so the user knows what state the change is in
before reading criticism.

Give every finding a severity:

- **Blocking** — wrong behavior, security exposure, data loss, a compatibility
  break, or a new check failure.
- **Should fix** — dead code, misleading or overclaiming comments, tests that
  cannot fail, unannounced but harmless behavior changes, unrelated churn.
- **Nit** — taste: wording, naming, idiom, comment trimming.

Present findings grouped by severity, then by category within each group. For
each: `file:line`, the offending code quoted short, the defect in one sentence,
and — where one exists — the honest counterargument for leaving it alone. A
finding you'd defend only weakly should say so. Mark unverified findings as
such.

Close with a numbered table of every finding (number, severity, category,
location, one-line summary), so the user can direct you to any of them by
number.

**If nothing survived verification**, say that the change looks sound, give the
baseline, and list what you checked. Do not reach for nits to fill the space.
That report is a valid and useful result.

Then stop. Do not start fixing unless the user already asked for fixes in this
session. If the commits belong to someone else or are already pushed, the
default is report-only; fixing them needs the user to say so explicitly for
this change.

## 7. Work the findings

Work in severity order: blocking first. Two modes. Interactive is the default.
Switch to batch when the user says "fix them all", names a set of finding
numbers, or is not present to answer.

**Interactive.** One finding per exchange. For anything involving taste —
wording, naming, how much rationale to keep — present concrete options showing
the *actual resulting code*, and let the user choose; the fix is theirs to pick,
not yours to impose. Grouping a few purely mechanical, behavior-preserving
changes into one exchange is fine — say you're grouping and let the user
object.

**Batch.** No pause between findings. Apply fixes in groups and check each
group once: all the mechanical, behavior-preserving fixes (comments, dead code,
naming, churn) form one group, and each blocking or behavior-changing fix forms
a group of its own, so a failure there points at one finding. On a new failure
in a mechanical group, bisect it: revert half the group, re-check, and repeat
until the culprit is isolated; mark that fix blocked and keep the rest. Taste
findings get the option you would have recommended, applied, with the
alternatives recorded. Close with a table: finding number, outcome (applied /
blocked / skipped), and the commit the fix landed in. Each taste finding's row
names the alternatives, so the user can swap one with a single instruction.

**Checking each group.** Run the fast checks (lint, format, types) plus the
tests covering the touched code after each group, then one full-suite run
after the last group, before absorbing; that run also serves as §8's starting
point. If the full run shows a new failure, bisect
across the groups since the last full green run to find the one responsible.
Report the numbers each time. This is how you catch a "cleanup" that broke
something, and it catches your own wrong findings: a lint or type error
appearing right after your edit usually means the thing you removed was
load-bearing.

**Then absorb the fix into the commit that introduced the code it touches**, so
no commit in the stack ever contains a defect a later one silently repairs. A
fix is applied only once it is green *and* sitting in its originating commit.
The mechanics differ by tool; read the one that applies before the first
absorb:

- jj: `references/jj.md`
- git: `references/git.md`

When a fix is blocked or turns out to be unnecessary, say which and why, and
keep going with the rest.

## 8. Leave the history reviewable

Once every fix is absorbed, verify each commit in the stack is *independently*
green (by the §2 definition) — a stacked review is only useful if every step
stands alone. The per-commit walk is in the same reference file.

**Authorization.**
- Reading history (`log`, `diff`, `status`, `show`, `blame`) never needs
  permission.
- Absorbing a fix into the user's own unpushed jj stack is part of applying the
  fix once they've asked for it — it is local, and `jj undo` reverses it.
- Rewriting git history (`rebase`, `commit --amend`, `reset`), or rewriting any
  commit that is already pushed or authored by someone else, in either tool,
  needs explicit authorization in the current session.
- Pushing, in either tool, is asked for every time and never assumed from an
  earlier yes.
