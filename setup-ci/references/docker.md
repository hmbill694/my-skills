# Dockerfile: the runtime layer

Multi-stage, non-root, minimal runtime. The image ships the artifact and nothing else — no compiler, no package manager, no nix, no `just`.

**On the toolchain version appearing twice:** the builder base image pins a toolchain, and so does `devenv.nix`. These are *not* required to be equal, and chasing equality causes real pain (see the Go section of [devenv.md](devenv.md)). They serve different purposes:

| Number | Purpose |
|---|---|
| `devenv.nix` | the toolchain developers and CI build *with* |
| Dockerfile base image | the toolchain the shipped artifact is built *by* — the one that matters in production |
| `go.mod` `go` / `rust-version` / `engines` | the **minimum** language version the code claims to support |

Keep them in the same major/minor unless you have a reason, let Renovate move each on its own, and say in a comment which is which — otherwise the next person "fixes" a mismatch that was intentional.

## Rules

| Rule | Why |
|---|---|
| Base images written as literal `image:tag`, never composed from `ARG`s | Renovate expands a single `ARG` holding a whole tag, but a tag built from two variables (`${VER}-slim-${RELEASE}`) falls outside that — it silently stops being updated or digest-pinned |
| Every base image ends up digest-pinned (`image:tag@sha256:…`) | A tag is mutable; the digest is the only thing that fixes what you actually built on. Let Renovate add and maintain it rather than writing digests by hand |
| `# syntax=docker/dockerfile:1` on line 1 | Enables cache mounts, heredocs, `COPY --link`. Renovate manages this one too — it is a `syntax` image dependency |
| Dependencies copied and resolved before source | One layer that survives every source edit |
| `--mount=type=cache` for package caches | Rebuilds drop from minutes to seconds |
| Runtime stage starts `FROM` a distroless/minimal image | No shell, no package manager, tiny CVE surface |
| `USER nonroot` (or an explicit uid) | Root in a container is one escape away from root on the host |
| `ENTRYPOINT` exec-form, never shell-form | Signals reach PID 1; the container stops on SIGTERM |
| No secrets in `ARG` or `ENV` | Both are readable in `docker history` forever |
| Build must work from a plain checkout | A build that needs devenv is a build only CI can do |

## `.dockerignore`

Write this **first** — without it the build context includes `target/`, `node_modules/`, and `.devenv/`, which can be gigabytes.

```gitignore
.git
.github
.devenv
.direnv
target
dist
node_modules
**/node_modules
*.log
.env
.env.*
Dockerfile
.dockerignore
devenv.*
justfile
```

## Rust

```dockerfile
# syntax=docker/dockerfile:1

# This is the Rust that SHIPS — independent of the dev toolchain in devenv.nix.
# Renovate bumps the tag and appends/maintains the @sha256 digest.
FROM rust:1.90-slim-bookworm AS planner
WORKDIR /src
RUN cargo install cargo-chef --locked
COPY . .
RUN cargo chef prepare --recipe-path recipe.json

FROM rust:1.90-slim-bookworm AS builder
WORKDIR /src
RUN apt-get update \
    && apt-get install -y --no-install-recommends pkg-config libssl-dev \
    && rm -rf /var/lib/apt/lists/*
RUN cargo install cargo-chef --locked
COPY --from=planner /src/recipe.json recipe.json
# Dependencies only: this layer is reused until Cargo.lock changes.
RUN cargo chef cook --release --recipe-path recipe.json
COPY . .
ARG VERSION=0.0.0-dev
ENV APP_VERSION=${VERSION}
RUN cargo build --release --locked --bin app \
    && strip target/release/app

FROM gcr.io/distroless/cc-debian12:nonroot
COPY --from=builder /src/target/release/app /usr/local/bin/app
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/app"]
```

`distroless/cc` carries glibc and libstdc++, which a normal Rust binary needs. Use `distroless/static` **only** with a fully static build: `rustls` instead of native OpenSSL, plus `--target x86_64-unknown-linux-musl`. Do not reach for musl just to shrink the image — dynamic OpenSSL against musl is a well-known time sink.

Drop the `planner`/`chef` stages for a small crate; keep them the moment dependency compile time is felt.

## Go

```dockerfile
# syntax=docker/dockerfile:1

# This is the Go that SHIPS. It is deliberately independent of the dev toolchain
# in devenv.nix and of go.mod's `go` directive — three numbers, three purposes.
# Renovate bumps the tag and appends/maintains the @sha256 digest.
FROM golang:1.26-bookworm AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY . .
ARG VERSION=0.0.0-dev
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux go build \
      -trimpath \
      -ldflags "-s -w -X main.version=${VERSION}" \
      -o /out/app ./cmd/app

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /out/app /usr/local/bin/app
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/app"]
```

`CGO_ENABLED=0` is what makes `distroless/static` viable. If anything in the dependency tree needs cgo, the binary will build and then fail at runtime with a missing-loader error — switch to `distroless/base` and keep cgo on.

`distroless/static` includes CA certificates, so outbound HTTPS works. A `scratch` base does not; you would have to copy `ca-certificates.crt` yourself.

## TypeScript / Node

```dockerfile
# syntax=docker/dockerfile:1

# This is the Node that SHIPS — independent of the dev toolchain in devenv.nix.
# Renovate bumps the tag and appends/maintains the @sha256 digest.
FROM node:22-bookworm-slim AS base
ENV PNPM_HOME=/pnpm
ENV PATH=${PNPM_HOME}:${PATH}
RUN corepack enable
WORKDIR /src

FROM base AS deps
COPY package.json pnpm-lock.yaml ./
RUN --mount=type=cache,id=pnpm,target=/pnpm/store \
    pnpm install --frozen-lockfile

FROM deps AS builder
COPY . .
ARG VERSION=0.0.0-dev
RUN pnpm build
RUN --mount=type=cache,id=pnpm,target=/pnpm/store \
    pnpm install --frozen-lockfile --prod --ignore-scripts

FROM gcr.io/distroless/nodejs22-debian12:nonroot
WORKDIR /app
COPY --from=builder /src/node_modules ./node_modules
COPY --from=builder /src/dist ./dist
COPY --from=builder /src/package.json ./package.json
USER nonroot
EXPOSE 3000
CMD ["dist/index.js"]
```

The distroless nodejs image's `ENTRYPOINT` is already `node`, so `CMD` is the script path — **not** `["node", "dist/index.js"]`, which would try to run node inside node.

Re-running `pnpm install --prod` after the build is what drops devDependencies. `pnpm prune --prod` also works; with workspaces use `pnpm deploy --filter <pkg> --prod /out` and copy `/out`.

## Healthchecks

`HEALTHCHECK CMD curl ...` cannot work on distroless — there is no shell and no curl. Options, in order of preference:

1. Let the orchestrator probe it (Kubernetes `livenessProbe`, ECS health check, Compose with an external checker).
2. Ship a `--health-check` flag in your own binary and use exec form: `HEALTHCHECK CMD ["/usr/local/bin/app", "--health-check"]`.
3. Move to `distroless/base` + a static healthcheck binary, if 1 and 2 are both impossible.

## Labels

Do not hand-write OCI labels. `docker/metadata-action` generates them in CI, and its output feeds `labels:` in the build step — see [workflows.md](workflows.md). Locally they are simply absent, which is fine.

## Verifying

```bash
docker build --check .                       # lint the Dockerfile, no build
just docker-build                            # real build
docker run --rm <image> --version            # the binary starts
docker image inspect <image> --format '{{.Config.User}}'   # must not be empty or "root"
docker image ls <image>                      # sanity-check the size
```

A build that succeeds but produces an image that cannot start is the most common outcome of a first Dockerfile. Always run it.

## Common mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| No `.dockerignore` | Build context is gigabytes; cache never hits | Write it first |
| Shell-form `ENTRYPOINT` | `docker stop` takes 10s and kills the process | Exec form |
| `COPY . .` before dependency install | Every source edit reinstalls all dependencies | Copy manifests first |
| Runtime stage missing a needed asset (migrations, templates, certs) | Works locally, crashes in the image | Interview question G6 |
| `USER` omitted | Container runs as root | `USER nonroot:nonroot` |
| `latest` base image tag | Unreproducible builds; Renovate cannot track it | A literal `image:tag`, digest-pinned by Renovate |
| Base image tag composed from two `ARG`s | Renovate stops updating it, with no error anywhere | One literal reference per `FROM` |
| Secret passed as `ARG` | Permanently in `docker history` | `--mount=type=secret` |
| Building inside devenv/nix | CI-only build path | Plain checkout only |
