# Interview: the decision tree

Invoke the `grill-me` skill first, then work this tree. Rules:

- **One question per message.** Multiple questions at once is bewildering and gets you a partial answer.
- **Always state your recommendation** and why, so the user can say "yes" and move on.
- **Skip anything Phase 1 recon already answered.** Confirm those in the Phase 2 plan instead of asking.
- **Skip whole sections for artifacts that already work.** On a partly-configured repo the gap matrix from [gap-analysis.md](gap-analysis.md) decides which sections are live. A sound Dockerfile means section G is not asked at all — and a repo where everything passes gets two questions, not forty.
- **Follow dependencies.** Section A determines which later branches exist. Don't ask about crates.io publishing for a Go service.
- **Ask the follow-ups that an answer opens up.** This tree is the floor, not the ceiling — if an answer implies a decision not listed here, ask it.

Track answers as you go; you will replay all of them in the Phase 2 plan.

---

## A. Project shape (always)

| # | Question | Recommended default |
|---|---|---|
| A1 | What is the artifact — library, CLI binary, long-running service, or several? | From recon |
| A2 | Single package or workspace/monorepo? If mono, which packages release independently? | Single unless workspace files say otherwise |
| A3 | Which language(s) and which is primary for CI? | From recon |
| A4 | Package manager and lockfile you intend to keep? | Existing lockfile wins; pnpm for new Node |
| A5 | Default branch name, and is it protected today? | `main` |
| A6 | Do the tests need external services (Postgres, Redis, S3-alike)? | No — but ask, it changes devenv and CI |
| A7 | Supported platforms — Linux only, or macOS/Windows too? | `ubuntu-latest` only; add macOS only if the code is platform-sensitive |

## B. Toolchain (always — this is devenv's contract)

| # | Question | Recommended default |
|---|---|---|
| B1 | Exact toolchain version, or a channel? | Pin exact (`stable` + a version), so Renovate can bump it deliberately |
| B2 | Extra dev tools that must be in the shell (protoc, sqlx-cli, golangci-lint, migration tools)? | Only what recipes actually invoke |
| B3 | Git hooks at commit time (format + lint on changed files)? | Yes, via `git-hooks.hooks` — cheap, and `devenv test` reuses them in CI |
| B4 | Use direnv (`.envrc`) for automatic shell entry? | Yes |
| B5 | Own Cachix cache for the Nix store, or public `devenv` cache only? | Public `devenv` cache to start; own cache when cold CI builds get slow |
| B6 | Secrets/env needed for local dev, and where do they come from? | `.env` (gitignored) loaded by devenv; never commit values |

## C. Commands (always — this is the justfile's contract)

| # | Question | Recommended default |
|---|---|---|
| C1 | Exact format, lint, test, build commands as you run them today? | From recon; confirm verbatim |
| C2 | Are there slow/integration tests that should be separate from `just test`? | Yes → `test` (fast) and `test-all` (everything) |
| C3 | Coverage — measure it, and does CI fail below a threshold? | Measure, don't gate, until the number is trusted |
| C4 | Dependency audit / license check in CI? | Yes — `cargo audit` / `pnpm audit` / `govulncheck` as a non-blocking job first |
| C5 | Keep or replace an existing Makefile / npm scripts? | Replace the entrypoint, delegate the internals; never maintain two |
| C6 | What exactly should `just ci` contain, in order? | `fmt-check lint test build` |

## D. PR gates (always)

| # | Question | Recommended default |
|---|---|---|
| D1 | Which conventional-commit types are allowed? | `feat fix docs chore refactor perf test build ci revert` |
| D2 | Require a scope in PR titles? Restrict the scope list? | Not required; restrict only in a monorepo, to package names |
| D3 | Enforce lowercase / no-trailing-period subjects? | Yes — `subjectPattern: ^(?![A-Z]).+[^.]$` |
| D4 | Validate the commit message too on single-commit PRs? | Yes (`validateSingleCommit`) — squash merges pick it up |
| D5 | Build matrix — one runner, or multiple OS/versions? | One (`ubuntu-latest`); a matrix multiplies cold Nix builds |
| D6 | Which checks must be required for merge? | PR title lint + the CI job |
| D7 | Merge queue? | No, until PR volume actually needs it |
| D8 | Job timeout? | 30 min, so a hung job cannot burn an hour |

## E. Releases (always)

| # | Question | Recommended default |
|---|---|---|
| E1 | Manifest mode single package, or multi-package monorepo config? | Single, in manifest mode, so growing to mono needs no rewrite |
| E2 | `release-type` per package (`rust`, `node`, `go`, `simple`)? | Match the language; `simple` for a service with no published version file |
| E3 | Current version to seed `.release-please-manifest.json`? | Latest existing tag, else `0.1.0` |
| E4 | Pre-1.0 semantics — should `feat` bump minor or patch while `0.x`? | Default (`bump-minor-pre-major: true`) |
| E5 | Changelog sections — hide `chore`/`ci`, or show everything? | Hide `chore`, `ci`, `test`; show `feat`, `fix`, `perf`, `docs`, `refactor` |
| E6 | Must merging a release PR trigger downstream workflows (publish, deploy)? | **Yes** → requires a GitHub App token or PAT, not `GITHUB_TOKEN`. Ask which they have |
| E7 | Who is allowed to merge release PRs? | Same protection as any PR |
| E8 | Extra files carrying the version that release-please must bump (Chart.yaml, README badge)? | None unless named |

## F. Publishing (only if E says releases produce artifacts)

| # | Question | Recommended default |
|---|---|---|
| F1 | Push a container image to GHCR on release? | Yes |
| F2 | Multi-arch (`linux/amd64,linux/arm64`)? | amd64 only until arm64 is actually needed — QEMU arm64 builds are slow |
| F3 | Tag policy for images? | `:X.Y.Z`, `:X.Y` on release; `:sha-<sha>` + `:latest` on every main push. `:latest` means tip of `main`, never "latest release" — say so, since users often assume the opposite |
| F4 | Build provenance attestations + SBOM? | Yes, attestations — free with OIDC |
| F5 | Publish to a package registry (crates.io, npm)? Which auth? | Only if the package is public; prefer npm trusted publishing / crates.io trusted publishing over long-lived tokens |
| F6 | Also build the image on PRs (without pushing)? | Yes — catches Dockerfile rot at review time |
| F7 | Deploy anywhere on release? | Out of scope unless asked; say so explicitly |

## G. Docker (only if the artifact ships as an image)

| # | Question | Recommended default |
|---|---|---|
| G1 | Runtime base image? | `gcr.io/distroless/static-debian12:nonroot` (Go/static Rust), `distroless/cc` (dynamic Rust), `distroless/nodejs22` (Node) |
| G2 | Port(s) to expose, and is the port configurable by env? | From recon; expose one, read it from env |
| G3 | Healthcheck — in-image, or left to the orchestrator? | Orchestrator; distroless has no shell |
| G4 | Runtime config: env vars, mounted config file, or both? | Env vars only |
| G5 | Build-time inputs (private registry creds, feature flags)? | None; if needed, BuildKit secrets — never `ARG` for a secret |
| G6 | Does the image need extra runtime assets (migrations, templates, CA certs)? | Ask; forgetting this is the usual distroless failure |
| G7 | Static or dynamic linking? | Static where it is free: Go with `CGO_ENABLED=0`, Rust already using rustls. Do **not** take on musl cross-compilation just to shrink a Rust image — `distroless/cc` is the cheaper answer ([docker.md](docker.md)) |

## H. Renovate (always)

| # | Question | Recommended default |
|---|---|---|
| H1 | Schedule, or fire immediately? | `before 6am on monday` — one weekly batch, not a daily drip |
| H2 | Automerge policy? | Automerge patch + minor for devDependencies and GitHub Actions, once CI passes; humans review majors and runtime deps |
| H3 | Grouping? | Group lockfile maintenance, group all non-major dev deps, separate majors |
| H4 | Concurrent PR limit? | 5 open, 2 per hour |
| H5 | How should the pinned toolchain in `devenv.nix` and `devenv.lock` stay fresh? | Renovate **cannot** read `devenv.lock` — a `customManagers` regex for the version pins in `devenv.nix`, plus a scheduled `devenv update` workflow. See [renovate.md](renovate.md) |
| H6 | Paths to ignore (vendored, examples, fixtures)? | None unless named |
| H7 | Dependency dashboard issue? | Yes |

## I. Confirmation (always)

Replay every answer, the file list, and the manual steps. Ask: *"Anything wrong before I write?"* Wait for the go-ahead.

---

## Handling non-answers

| User says | Do |
|---|---|
| "You decide" | State your recommendation as the decision, in one line, and move to the next question. Do not skip it silently — it goes in the Phase 2 plan. |
| "Just do everything" | Still walk A, C, E — they cannot be guessed. Default the rest and list the defaults in the plan. |
| Answers contradict recon | Say what the repo shows, once, then take their answer. |
| Goes quiet mid-interview | Summarise what is settled and what is open. Don't start writing. |
