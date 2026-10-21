---
name: setup-ci
description: Use when a repository needs its CI/CD foundation stood up, completed, or repaired — missing GitHub Actions, no conventional-commit enforcement on PRs, no automated releases or changelog, no dependency update bot, no container image, no single command entrypoint, or a toolchain that only exists on one developer's laptop. Triggers on "setup CI", "set up GitHub Actions", "add release-please", "add renovate", "add a justfile", "add devenv", "dockerize this repo", "make CI match local".
---

# Setup CI

One coherent CI/CD foundation with a strict layering:

| Layer | Owns | Never contains |
|---|---|---|
| `devenv.nix` | the toolchain (compilers, linters, services) | project commands |
| `justfile` | every project command | toolchain version pins |
| GitHub Actions | *when* to run, permissions, secrets | command logic |
| `Dockerfile` | the shipped runtime | dev tooling |

Each fact has one home, so local and CI cannot drift.

## The Iron Rule

**Interview first. Write nothing until the user confirms the plan.**

Invoke the `grill-me` skill, then walk [references/interview.md](references/interview.md) — one question at a time, each with your recommended answer. Facts you read from the repo yourself; decisions are the user's.

**Violating the letter of this rule is violating the spirit of it.** There is no version of "I aligned in a different way" that involves files existing first.

No exceptions:
- Not for "obvious" defaults — confirm them in the Phase 2 plan instead.
- Not by "generating a draft they can edit" — a draft is writing. Delete it and start over.
- Not for an empty or brand-new repo.
- Not when adding only one piece (just Renovate, just Docker) — interview the pieces in scope.
- **Not when the user says "don't ask questions", "use sensible defaults", or "come back with files".** That is permission to move fast and to batch your questions — never permission to decide for them. Ask anyway, in one message, and stop.
- **Not when the user says they are unavailable, in meetings, or unreachable.** Unavailability is the *strongest* reason to ask, not an exemption: nobody can catch a wrong default until they are back. Your questions wait harmlessly in the transcript. An unanswered question costs one message; a wrong default on release seeding, image identity, or a toolchain pin costs a migration.
- **Listing the questions you "would have asked" after writing the files is not the interview.** That is a changelog of decisions you already made for them. Questions precede files, or they are not questions.
- Not because nothing was committed. The working tree is the deliverable; `git status` being dirty *is* the writing.

If you are genuinely blocked from asking — a non-interactive run with no user in the loop at all — say so explicitly, produce the question list **as your entire output**, and write nothing.

### Rationalizations, from real test runs

Every row below is a verbatim excuse an agent used to skip the interview on this exact task.

| Excuse | Reality |
|---|---|
| "You said don't ask, so I used defaults" | They said be fast. Seeding, image name and toolchain pins are not defaults, they are decisions. Ask, then stop. |
| "They're in meetings, asking is pointless" | They will read the transcript. Unavailability raises the cost of a wrong guess; it does not lower the cost of a question. |
| "I skipped the interview this skill mandates, but here are the 4 things I'd have asked" | Then you knew the rule, knew the questions, and wrote the files anyway. Ask the 4 things first. |
| "It's all reversible in two lines" | Reversible by you, today, with the context in your head. Not by them, next quarter. |
| "No git remote, so I inferred the image name from the module path" | An inferred published identity is a guess about what they ship. That is the question. |
| "Nothing is committed, so I haven't really written anything" | 19 files in the working tree is writing. |
| "The defaults are good and CI is green, so the outcome is right" | A correct guess is still a guess. You were asked to align, not to be lucky. |
| "Better than delivering nothing before their deadline" | False choice. The interview **is** the deliverable at that point: a scoped plan with a recommendation per question, answerable with one word. In testing that took ~2 minutes and ~10 tool calls; ploughing ahead took ~15 minutes and ~90. Asking is both correct and faster. |
| "I proceeded with the skill's documented defaults" | The skill documents recommendations *to offer*, not permission to apply. Every default in the references exists so you can put it in a plan, not so you can skip the plan. |

## Phases

**Create a todo per phase.** Finish each before starting the next.

1. **Recon and gap analysis (read-only).** From the repo: language, package manager, workspace layout, the real lint/test/build commands, the artifact and its entrypoint, already-pinned toolchain versions, `gh repo view`. Then run `scripts/verify-setup.sh --audit` and classify every artifact — absent, present-but-broken, or sound — per [references/gap-analysis.md](references/gap-analysis.md). Report the scope arithmetic in one short block. Never ask what the repo already answers.
2. **Interview and plan.** Interview the gaps only — nothing about an artifact that is already sound. **Read a layer's reference before recommending a default for it**, or you will recommend something the templates contradict and the user will approve a plan you then don't follow. Then present, in one message: every decision with its answer, the exact file list marked `new`/`modify`/`keeping as-is`, and what you will *not* do. Stop and wait for an explicit go-ahead.
3. **Generate**, in dependency order: [devenv](references/devenv.md) → [justfile](references/justfile.md) → [Dockerfile](references/docker.md) → [workflows](references/workflows.md) → [release-please](references/releases.md) → [renovate](references/renovate.md) → `.gitignore` and the commit-convention note in `CONTRIBUTING.md`. Run `scripts/resolve-action-versions.sh` before writing any workflow; never type an action version from memory.
4. **Verify.** Run `scripts/verify-setup.sh`, fix, re-run. **REQUIRED SUB-SKILL:** `superpowers:verification-before-completion`. Paste real output — no "should work", no "CI will tell us".
5. **Hand off.** Give the user the manual checklist from [references/repo-settings.md](references/repo-settings.md). CI is not done until those are listed.

## Structural invariants

Contracts, not preferences. Check each before Phase 4.

1. **Every workflow step that does project work is `just <recipe>` and nothing else.** A step containing a pipeline, a loop, or two commands means the logic belongs in a recipe.
2. **The dev toolchain is defined once, in `devenv.nix`.** No `setup-node`/`setup-go`/`rust-toolchain` action alongside devenv. The Dockerfile's base image is a *separate* number — what ships, not what you develop with — and need not match; see [references/docker.md](references/docker.md).
3. **The CI `check` job's `just` steps are exactly `just ci`'s dependency list, in order.** The job splits them for legible failures; `just ci` runs the identical set locally. `audit` and `image` are separate jobs and outside this parity.
4. **The Dockerfile builds from the repo alone** — no devenv, no nix, no `just` inside it. A CI-only build path is a broken build path.
5. **`.release-please-manifest.json` exists and states the current version** before the first release run.
6. **Every third-party dependency in CI is pinned by digest with a version comment** — `uses: owner/repo@<40-char sha> # vX.Y.Z`, and base images as `image:tag@sha256:…`. A tag is mutable and executes with your secrets. Renovate's `helpers:pinGitHubActionDigests` keeps SHA and comment in step; never hand-edit either.
7. **An artifact that already works is not touched.** Repairs are minimal and in place, with the diff shown first; a competing tool (Makefile, dependabot, semantic-release, flake.nix) is never removed without an explicit yes. See [references/gap-analysis.md](references/gap-analysis.md).

## Red flags — stop

- Writing a file before the user said go → delete it, return to Phase 2.
- The phrase "I skipped the interview" forming anywhere in your reasoning.
- Reaching for Write/Edit while your Phase 2 plan has no answers against it.
- Planning to explain your judgement calls in the final report. Those are the interview questions; you are late.
- Any `uses:` line ending in a tag rather than a 40-character SHA, or a SHA you did not get from the resolver script.
- A multi-line `run:` with real logic in it.
- About to say "set up successfully" with no `verify-setup.sh` output.
- Duplicating an existing Makefile or npm scripts into new recipes — recipes delegate or replace; ask which.
- Overwriting a working config because the template differs from it. The template is not the goal.
- Asking a question whose answer is sitting in `go.mod`, `package.json`, or the existing workflow.

## Scope

Generate only what the interview agreed to. If the user wants one piece, do that piece well and note what the rest would add — never quietly build the whole foundation.

Each reference file ends with its own mistakes table; read the one for the layer you are writing.
