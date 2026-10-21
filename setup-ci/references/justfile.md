# justfile: the command layer

Every command anyone runs — developer, CI, or release — is a `just` recipe. CI steps are `just <recipe>` and nothing more.

Verified against just 1.55.1.

## The recipe contract

These names are the interface. CI, the README, and muscle memory all depend on them, so keep the names even when a recipe is a one-liner or a no-op.

| Recipe | Must do | Must not |
|---|---|---|
| `default` | list recipes | do work |
| `setup` | idempotent bootstrap (hooks, deps, fixtures) | be required before `test` works in CI |
| `fmt` | format in place | fail on unformatted code |
| `fmt-check` | verify formatting, write nothing | reformat |
| `lint` | static analysis, warnings as errors | format |
| `test` | fast tests, no external services | need Docker or a database |
| `test-all` | everything, services included | be what CI's fast path runs |
| `build` | build the release artifact | run tests |
| `run` | run locally | be used by CI |
| `check` | `fmt-check lint test build` — the pre-push gate | differ from `ci` in *order* |
| `ci` | exactly what CI runs, in CI's order | contain CI-only plumbing (tokens, uploads) |
| `audit` | dependency vulnerability scan | block on advisories with no fix |
| `docker-build` | build the image locally | push |
| `docker-run` | run the built image | require a registry |
| `update` | refresh lockfiles | bump pinned toolchains silently |
| `clean` | remove build output | remove lockfiles |

**Invariant:** `ci`'s dependency list and the CI job's step list are the same recipes in the same order. When you add a step to one, add it to the other.

## Header (every justfile)

```just
set shell := ["bash", "-euo", "pipefail", "-c"]
set dotenv-load

image := env("IMAGE", "ghcr.io/OWNER/REPO")
version := `git describe --tags --always --dirty 2>/dev/null || echo "0.0.0-dev"`

[doc('List all recipes')]
default:
    @just --list --unsorted
```

Three details that bite:

- `-euo pipefail` is not optional: without it a failing command inside a multi-line recipe is ignored and CI goes green on a broken build.
- `set dotenv-load` — not `set dotenv-load := true`. Both parse, but `just --fmt --check` rejects the second form, and verification runs that check.
- The `version` backtick is evaluated on **every** `just` invocation, before any recipe runs. Without the `|| echo` fallback, every recipe fails outside a git checkout (including inside a Docker build context).

## Rust

```just
[group('dev')]
setup:
    cargo fetch

[group('fmt')]
fmt:
    cargo fmt --all

[group('fmt')]
fmt-check:
    cargo fmt --all -- --check

[group('check')]
lint:
    cargo clippy --all-targets --all-features -- -D warnings

[group('test')]
test *ARGS:
    cargo nextest run --all-features {{ ARGS }}

[group('test')]
test-all *ARGS:
    devenv up -d
    cargo nextest run --all-features --run-ignored all {{ ARGS }}

[group('build')]
build:
    cargo build --release --locked

[group('dev')]
run *ARGS:
    cargo run -- {{ ARGS }}

[group('check')]
audit:
    cargo audit

[group('dev')]
update:
    cargo update

[group('dev')]
clean:
    cargo clean

check: fmt-check lint test build

ci: fmt-check lint test build
```

## Go

```just
setup:
    go mod download

fmt:
    gofmt -w .

fmt-check:
    @test -z "$(gofmt -l .)" || { gofmt -l .; echo "run 'just fmt'"; exit 1; }

lint:
    go vet ./...
    golangci-lint run

test *ARGS:
    gotestsum -- -race -short ./... {{ ARGS }}

test-all *ARGS:
    devenv up -d
    gotestsum -- -race ./... {{ ARGS }}

build:
    CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version={{ version }}" -o dist/app ./cmd/app

run *ARGS:
    go run ./cmd/app {{ ARGS }}

audit:
    govulncheck ./...

update:
    go get -u ./... && go mod tidy

clean:
    rm -rf dist

check: fmt-check lint test build

ci: fmt-check lint test build
```

## TypeScript / Node

```just
setup:
    pnpm install --frozen-lockfile

fmt:
    pnpm prettier --write .

fmt-check:
    pnpm prettier --check .

lint:
    pnpm eslint .
    pnpm tsc --noEmit

test *ARGS:
    pnpm vitest run {{ ARGS }}

test-all *ARGS:
    devenv up -d
    pnpm vitest run --coverage {{ ARGS }}

build:
    pnpm build

run *ARGS:
    pnpm dev {{ ARGS }}

audit:
    pnpm audit --audit-level high

update:
    pnpm update --latest --interactive

clean:
    rm -rf dist node_modules/.cache

check: fmt-check lint test build

ci: setup fmt-check lint test build
```

Node is the one stack where `ci` starts with `setup`: the lockfile install has to happen before any tool exists. Rust and Go get their toolchain from devenv and fetch on demand.

## Docker recipes (any stack)

```just
[group('docker')]
docker-build tag=version:
    docker build \
      --build-arg VERSION={{ tag }} \
      --tag {{ image }}:{{ tag }} \
      --tag {{ image }}:latest \
      .

[group('docker')]
docker-run *ARGS: docker-build
    docker run --rm -it -p 8080:8080 {{ image }}:latest {{ ARGS }}

[confirm('Push image to the registry?')]
[group('docker')]
docker-push tag=version:
    docker push {{ image }}:{{ tag }}
```

Attributes must be in alphabetical order (`[confirm]` before `[group]`): `just --fmt --check` reorders them otherwise, and verification runs that check.

`[confirm]` on push stops an absent-minded local push to a shared registry. CI pushes through `docker/build-push-action`, not this recipe — see [workflows.md](workflows.md).

## Monorepo

Keep one root justfile as the entrypoint and delegate. Every recipe named in a root dependency list must exist at the root:

```just
mod api 'packages/api/justfile'
mod web 'packages/web/justfile'

[doc('Run every package CI in order')]
ci:
    just api::ci
    just web::ci
```

Per-package justfiles implement the same contract. `just --list` at the root then shows the whole repo, and `just web::test` runs one package.

## Common mistakes

| Mistake | Consequence | Fix |
|---|---|---|
| Missing `set shell` with `pipefail` | Multi-line recipe fails silently; CI green on broken code | Add the header |
| `ci` and the CI job list different recipes | "Passes locally, fails in CI" | Keep the lists identical |
| Recipe hardcodes a toolchain version | Two sources of truth with devenv | Call the tool; devenv supplies it |
| `{{ARGS}}` written as `$ARGS` | Args silently dropped | `{{ ARGS }}` |
| `test` needs Postgres | Every contributor's first `just test` fails | Move it to `test-all` |
| Recipe `cd`s and assumes it persists | Each line is a new shell unless the recipe is one line | Use `[working-directory('...')]` or one line joined with `&&` |
| CI step runs `cargo clippy` directly | The layering is broken; the command now lives in two places | `just lint` |
