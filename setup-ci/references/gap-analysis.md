# Gap analysis: repos that are already partly set up

Most repos are not empty. Classify what exists **before** asking anything, then interview only the gaps. Regenerating a working file is not neutral — it discards decisions someone made on purpose.

## Start with the audit

```bash
scripts/verify-setup.sh --audit
```

The result is the gap matrix:

| Result | State | What it means for scope |
|---|---|---|
| `SKIP` | absent | In scope to **build**. Interview it. |
| `FAIL` | present but broken or incomplete | In scope to **repair**. Interview only what bears on the repair. |
| `PASS` | present and sound | **Leave it alone.** Name it in the plan as "keeping as-is". Ask nothing. |

Two things never show up on disk and must always be asked:

- Is the Renovate GitHub App actually installed? (`gh api "repos/{owner}/{repo}/installation" --jq .app_slug`)
- Do release PRs need to trigger downstream workflows? (the token decision, E6)

## What "complete" means per artifact

| Artifact | Complete when | Typical partial state |
|---|---|---|
| devenv | `devenv.nix` + `devenv.yaml` + committed `devenv.lock`, `just` in `packages`, `.devenv`/`.direnv` ignored | `flake.nix` but no devenv; `devenv.nix` with no lock; toolchain *also* pinned by a setup-action |
| justfile | contract recipes present, `set shell` with pipefail, parity with the CI `check` job | `Makefile` or npm scripts instead; a justfile missing `fmt-check`/`ci`; no `set shell` |
| PR title lint | workflow exists, fires on `edited`, types superset of the changelog types | `commitlint` on commits only; lint fires on `opened` only |
| CI | lint+test+build run on PR, timeouts, explicit permissions, no setup-action beside devenv | `setup-go`/`setup-node` doing the toolchain; no permissions block; test step only |
| Dockerfile | multi-stage, non-root, exec-form entrypoint, `.dockerignore`, built in CI | single-stage running as root; no `.dockerignore`; never built in CI |
| release-please | config + manifest + workflow, manifest agrees with the latest tag | config with no manifest; tags exist but no config; `semantic-release`/`changesets` in place |
| Renovate | config present **and app installed**, semantic commit presets | `dependabot.yml`; bare onboarding config; no `:semanticCommits` |

## Competing tools — never replace unilaterally

A tool already doing the job is a **migration decision**, and it is the user's. Surface it, recommend, wait.

| Found | Conflicts with | Ask |
|---|---|---|
| `Makefile` | justfile | Port the targets and delete it, or have recipes call `make`? Default: port, but only with a yes |
| npm/pnpm scripts | justfile | Keep the scripts as the implementation and have recipes delegate. Do **not** duplicate the command text |
| `flake.nix` | devenv | devenv runs *with* flakes — never delete their flake. Ask whether devenv wraps it or they keep `nix develop` |
| `semantic-release`, `changesets` | release-please | A real migration: current version, tag format compatibility, changelog preservation, deleting the old workflow. Offer to leave it in place instead |
| `dependabot.yml` | Renovate | Running both produces duplicate PRs. One has to go |
| `.pre-commit-config.yaml` (a real file, not the devenv symlink) | `git-hooks.hooks` | Same hooks from two sources will fight. Pick one |
| CircleCI / GitLab CI / Jenkins config | GitHub Actions | A platform migration, not a CI setup. Confirm the intent explicitly |
| Hand-maintained `CHANGELOG.md` | release-please | It will take the file over. Confirm, and set `bootstrap-sha` so it does not rewrite history |

When the repo's existing convention contradicts the template and the team is happy with it, **the template loses**. Say what the template would do differently, once, and move on.

## Read these instead of asking

| Question | Read it from |
|---|---|
| A3/A4 language, package manager | `go.mod`, `Cargo.toml`, `package.json` + which lockfile exists |
| B1 toolchain version | `rust-toolchain.toml`, `.nvmrc`, `go.mod`, `.tool-versions`, an existing setup-action's `with:` |
| C1 lint/test/build commands | `package.json` scripts, `Makefile`, the existing CI workflow's `run:` lines |
| C2 slow vs fast tests | test tags/`-short`, a separate integration job, `testcontainers` in deps |
| D1 allowed commit types | `commitlint.config.js`, or measure the history (below) |
| E3 current version | `git describe --tags --abbrev=0`, else the version field in the manifest file |
| F3 image tag policy | existing tags: `gh api "user/packages/container/<name>/versions"` |
| G2 port | `EXPOSE` in an existing Dockerfile, or the listen call in the code |
| G6 runtime assets | what the code opens at startup: migrations, templates, static dirs |

Measure how conventional the history already is — it decides whether the convention is new and where `bootstrap-sha` goes:

```bash
git log --oneline -50 \
  | grep -cE '^[0-9a-f]+ (feat|fix|chore|docs|refactor|perf|test|build|ci|revert)(\(.+\))?!?: '
```

A low count means the convention starts now: set `bootstrap-sha` to the first commit that follows it, or the changelog will be a dump of everything.

## Rules for touching what exists

1. **Never overwrite a `PASS` artifact.** Not to "align it with the template", not for consistency.
2. **Repair `FAIL` artifacts in place, minimally.** Show the specific defect and the proposed diff before writing. Do not replace their file with the template version.
3. **Preserve their choices**: file names, recipe names, step ordering, extra recipes, comments. A repair that reorders a working file is a rewrite wearing a diff.
4. **Never delete a competing tool's config** without an explicit yes, in this conversation.
5. **Adding is safer than changing.** A missing `permissions:` block is an addition; a rewritten `ci.yml` is a risk.

## Report scope before interviewing

Lead with the arithmetic so the user knows how much of their time this costs:

> `devenv`, `justfile` and the Dockerfile are already in good shape — I'll leave them alone.
> Missing: PR title linting, release-please, Renovate.
> Broken: `ci.yml` pins Go with `setup-go` while devenv also pins it, and no job has a timeout.
> That leaves me 6 questions, then a plan.

Then interview only those. On a repo where everything passes, the honest output is "nothing to do except the two settings I can't see from here" — not a regenerated set of files.
