# GitHub Actions: the orchestration layer

Workflows decide **when** things run, what permissions they get, and which secrets they see. They never contain command logic — every step that does project work is `just <recipe>`.

**Every `uses:` is pinned to a full 40-character commit SHA with the version in a trailing comment.** A tag — `@v4`, `@main`, even `@v4.3.0` — is mutable: whoever controls that tag can change what your workflow executes, and it executes with your secrets in scope. A SHA cannot be moved.

The comment is not decoration. It is the only readable record of *which* version that SHA is, and Renovate's `helpers:pinGitHubActionDigests` preset rewrites the SHA and the comment together. Hand-editing either one desynchronises them, and then the comment lies.

The SHAs below were current when this skill was written. **Always re-resolve them with `scripts/resolve-action-versions.sh` before writing** — it emits ready-to-paste `uses:` lines.

## `.github/workflows/pr-title.yml`

```yaml
name: PR Title

on:
  pull_request:
    types: [opened, edited, reopened, synchronize]

permissions:
  pull-requests: read

jobs:
  conventional-title:
    name: Conventional Commits
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: amannn/action-semantic-pull-request@48f256284bd46cdaab1048c3721360e808335d50 # v6.1.1
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          types: |
            feat
            fix
            docs
            chore
            refactor
            perf
            test
            build
            ci
            revert
          requireScope: false
          subjectPattern: ^(?![A-Z]).+[^.]$
          subjectPatternError: >-
            The subject "{subject}" is invalid: start with a lowercase letter and
            do not end with a period.
          validateSingleCommit: true
```

- `types` must include `edited`, or a title fixed after opening is never re-checked.
- `validateSingleCommit: true` also validates the commit message on single-commit PRs, because GitHub offers that message instead of the PR title when squashing. Pair it with the repo setting in [repo-settings.md](repo-settings.md) that forces squash titles to come from the PR.
- The `types` list must be a superset of the types release-please recognises in `release-please-config.json`, or a valid PR title can produce an empty changelog entry.

## `.github/workflows/ci.yml`

```yaml
name: CI

on:
  pull_request:
  push:
    branches: [main]

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

permissions:
  contents: read

jobs:
  check:
    name: Check
    runs-on: ubuntu-latest
    timeout-minutes: 30
    defaults:
      run:
        shell: devenv shell bash -- -e {0}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1

      - uses: cachix/install-nix-action@13d8dd58da0234aa297dedd986986ccb8e7f3e24 # v31.11.1
      - uses: cachix/cachix-action@38b082610b782e7e93e209c35fd730d399dee866 # v17
        with:
          name: devenv
      - name: Install devenv
        shell: bash
        run: nix profile add nixpkgs#devenv

      - name: Cache build artifacts
        uses: actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6.1.0
        with:
          path: |
            ~/.cargo/registry
            ~/.cargo/git
            target
          key: ${{ runner.os }}-build-${{ hashFiles('**/Cargo.lock') }}
          restore-keys: ${{ runner.os }}-build-

      - run: just fmt-check
      - run: just lint
      - run: just test
      - run: just build

  audit:
    name: Audit
    runs-on: ubuntu-latest
    timeout-minutes: 15
    continue-on-error: true
    defaults:
      run:
        shell: devenv shell bash -- -e {0}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: cachix/install-nix-action@13d8dd58da0234aa297dedd986986ccb8e7f3e24 # v31.11.1
      - uses: cachix/cachix-action@38b082610b782e7e93e209c35fd730d399dee866 # v17
        with:
          name: devenv
      - name: Install devenv
        shell: bash
        run: nix profile add nixpkgs#devenv
      - run: just audit

  image:
    name: Image
    runs-on: ubuntu-latest
    timeout-minutes: 30
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1

      - name: Resolve lowercase image name
        run: echo "IMAGE=ghcr.io/${GITHUB_REPOSITORY,,}" >> "$GITHUB_ENV"

      - uses: docker/setup-buildx-action@37fe631027851001ddb9b187196cc803df7f5f0e # v4.3.0

      - name: Log in to GHCR
        if: github.event_name == 'push'
        uses: docker/login-action@dbcb813823bdd20940b903addbd779551569679f # v4.6.0
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - uses: docker/build-push-action@53b7df96c91f9c12dcc8a07bcb9ccacbed38856a # v7.3.0
        with:
          context: .
          push: ${{ github.event_name == 'push' }}
          # :latest = tip of main. Main runs are serialized by `concurrency`, so it
          # only moves forward; release.yml must not write it or it could roll back.
          tags: |
            ${{ env.IMAGE }}:sha-${{ github.sha }}
            ${{ env.IMAGE }}:latest
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

Notes that matter:

- **`defaults.run` + the `shell: bash` override.** Every `run:` step uses the devenv shell; the step that *installs* devenv must opt out, or it tries to run inside a shell that does not exist yet.
- **`nix profile add`**, not `nix profile install` — renamed in Nix 2.30.
- **`cachix-action` with `name: devenv`** reads the public devenv cache. No token. Add `authToken: ${{ secrets.CACHIX_AUTH_TOKEN }}` and your own cache name only if the user set one up.
- **The `image` job has no devenv.** The Dockerfile must build from a plain checkout; if it needs nix or just, the build is broken.
- **`:latest` is the tip of `main`, and only this job moves it.** PRs build both tags but push neither. Releases are addressed by version (`:X.Y.Z`, `:X.Y`) and never touch `:latest` — see the release job below. CI runs on `main` are serialized by their concurrency group, so `:latest` only moves forward. The release workflow is outside that group; if it also wrote `:latest`, a slow release build could land after a newer commit's image and roll `:latest` back.
- **`${GITHUB_REPOSITORY,,}`** lowercases the name. GHCR rejects uppercase paths, and plenty of owners have capitals.
- **`continue-on-error` on audit** keeps a new advisory with no fix available from blocking every PR in the repo. Make it blocking once the backlog is clean.
- **The `check` job's step list matches `just ci`'s dependency list, exactly and in order.** Separate steps so a failure names itself in the UI; `just ci` exists so the same set runs locally. `audit` and `image` are separate jobs precisely because they are *not* part of that parity — `audit` is advisory and `image` needs no devenv. `verify-setup.sh` enforces this on the `check` job only, so if you rename that job, update the script.

Adjust the `cache` paths per stack: `~/.cargo` + `target` (Rust), `~/go/pkg/mod` + `~/.cache/go-build` (Go), the pnpm store path (Node). Wrong paths are not an error — they are a silent slowdown, so verify the cache hit rate on the second run.

## `.github/workflows/release.yml`

```yaml
name: Release

on:
  push:
    branches: [main]

permissions:
  contents: write
  pull-requests: write

concurrency:
  group: release-${{ github.ref }}
  cancel-in-progress: false

jobs:
  release-please:
    name: Release PR
    runs-on: ubuntu-latest
    timeout-minutes: 10
    outputs:
      release_created: ${{ steps.release.outputs.release_created }}
      tag_name: ${{ steps.release.outputs.tag_name }}
      version: ${{ steps.release.outputs.version }}
    steps:
      - uses: googleapis/release-please-action@45996ed1f6d02564a971a2fa1b5860e934307cf7 # v5.0.0
        id: release
        with:
          token: ${{ secrets.RELEASE_TOKEN || github.token }}
          config-file: release-please-config.json
          manifest-file: .release-please-manifest.json

  publish-image:
    name: Publish image
    needs: release-please
    if: needs.release-please.outputs.release_created == 'true'
    runs-on: ubuntu-latest
    timeout-minutes: 30
    permissions:
      contents: read
      packages: write
      id-token: write
      attestations: write
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          ref: ${{ needs.release-please.outputs.tag_name }}

      - name: Resolve lowercase image name
        run: echo "IMAGE=ghcr.io/${GITHUB_REPOSITORY,,}" >> "$GITHUB_ENV"

      - uses: docker/setup-buildx-action@37fe631027851001ddb9b187196cc803df7f5f0e # v4.3.0

      - uses: docker/login-action@dbcb813823bdd20940b903addbd779551569679f # v4.6.0
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - id: meta
        uses: docker/metadata-action@dc802804100637a589fabce1cb79ff13a1411302 # v6.2.0
        with:
          images: ${{ env.IMAGE }}
          tags: |
            type=semver,pattern={{version}},value=${{ needs.release-please.outputs.tag_name }}
            type=semver,pattern={{major}}.{{minor}},value=${{ needs.release-please.outputs.tag_name }}
          flavor: |
            latest=false

      - id: build
        uses: docker/build-push-action@53b7df96c91f9c12dcc8a07bcb9ccacbed38856a # v7.3.0
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          build-args: |
            VERSION=${{ needs.release-please.outputs.version }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
          provenance: mode=max
          sbom: true

      - uses: actions/attest-build-provenance@4d101475d8b20a2381f78447822ac1eab6504dd8 # v4.2.2
        with:
          subject-name: ${{ env.IMAGE }}
          subject-digest: ${{ steps.build.outputs.digest }}
          push-to-registry: true
```

`flavor: latest=false` is required, not tidiness: `docker/metadata-action` defaults to `latest=auto`, which adds `:latest` to any `type=semver` tag on its own. Dropping a `type=raw,value=latest` line without it still moves `:latest` on every release. `verify-setup.sh` checks this.

`release_created` is a **string**, so compare against `'true'`. `if: needs.release-please.outputs.release_created` alone is truthy for the string `"false"` and publishes on every push.

`secrets.RELEASE_TOKEN || github.token` degrades gracefully: with no secret set, release PRs still open — they just do not trigger this workflow's downstream jobs when merged. See [releases.md](releases.md) for why that matters and how to fix it properly.

## Multi-arch (only if the interview asked for it)

Add before `setup-buildx-action`:

```yaml
      - uses: docker/setup-qemu-action@1f40c72289eff860ee54a304f1438e3cff362e0a # v4.3.0
```

and to the build step:

```yaml
          platforms: linux/amd64,linux/arm64
```

QEMU-emulated arm64 compilation is slow — often 5-10x. Only pay for it if arm64 is actually consumed.

## Workflow rules

| Rule | Why |
|---|---|
| `permissions:` declared at workflow level, widened per job | Default token permissions are repo-configurable and often too broad |
| `timeout-minutes` on every job | A hung job otherwise burns 6 hours |
| `concurrency` with `cancel-in-progress` on PRs only | Never cancel a release mid-tag |
| Pin every action to a full SHA + version comment | A tag is mutable and runs with your secrets; Renovate keeps the SHA and comment in step |
| No `pull_request_target` | It runs fork code with write permissions; PR title linting does not need it |
| Secrets only in the job that needs them | A compromised build step cannot reach a publish token in another job |
| `if: github.event_name == 'push'` around registry login | Fork PRs have no access to secrets; the job would fail for outside contributors |
