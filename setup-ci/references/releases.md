# release-please: automated versioning and changelog

release-please reads conventional commits on the default branch, maintains an open **release PR** with the version bump and changelog, and on merge tags the release. Nothing releases until a human merges that PR.

Always use **manifest mode** (a config file plus a manifest file). Inline `release-type` works for one package and has to be torn out the day a second appears.

## `release-please-config.json` — single package

```json
{
  "$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json",
  "packages": {
    ".": {
      "release-type": "rust",
      "changelog-path": "CHANGELOG.md",
      "bump-minor-pre-major": true,
      "bump-patch-for-minor-pre-major": false,
      "include-component-in-tag": false,
      "changelog-sections": [
        { "type": "feat", "section": "Features" },
        { "type": "fix", "section": "Bug Fixes" },
        { "type": "perf", "section": "Performance" },
        { "type": "revert", "section": "Reverts" },
        { "type": "refactor", "section": "Refactors" },
        { "type": "docs", "section": "Documentation" },
        { "type": "build", "section": "Build System" },
        { "type": "chore", "hidden": true },
        { "type": "ci", "hidden": true },
        { "type": "test", "hidden": true }
      ]
    }
  }
}
```

## `.release-please-manifest.json`

```json
{
  ".": "0.1.0"
}
```

**This file must exist and hold the current version before the first run.** Without it release-please assumes a fresh project: on a repo that already has `v0.4.2` tagged it will happily propose `1.0.0` or restart at `0.1.0`.

Seed it from the real history:

```bash
git describe --tags --abbrev=0        # e.g. v0.4.2  ->  manifest value "0.4.2"
```

No tags at all? Use the version in `Cargo.toml` / `package.json` / the last release notes, else `0.1.0`.

On a repo with a long pre-conventional history, also set `"bootstrap-sha"` at the top level of the config to the first commit that follows the convention. Otherwise the first changelog is an unreadable dump of every commit ever made.

## `release-type` by stack

| Stack | `release-type` | Bumps |
|---|---|---|
| Rust | `rust` | `Cargo.toml`, `Cargo.lock` (workspace members too) |
| Node / TS | `node` | `package.json`, lockfile version field |
| Go | `go` | nothing — Go versions live in git tags only |
| Service with no version file | `simple` | `version.txt` (it creates one) |

Go modules at `v2` or above need the major suffix in the module path; release-please will not edit `go.mod` for you.

## Monorepo

```json
{
  "$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json",
  "separate-pull-requests": false,
  "plugins": ["cargo-workspace"],
  "packages": {
    "crates/api": {
      "release-type": "rust",
      "component": "api"
    },
    "crates/worker": {
      "release-type": "rust",
      "component": "worker"
    }
  }
}
```

```json
{
  "crates/api": "0.3.1",
  "crates/worker": "0.1.4"
}
```

- `component` gives each package its own tag prefix (`api-v0.3.1`). With `include-component-in-tag: true` (the default for non-root packages) tags stay unambiguous.
- Workspace plugins (`cargo-workspace`, `node-workspace`) propagate a bump to internal dependents. Without one, releasing `api` leaves `worker`'s dependency pointing at the old version.
- `"separate-pull-requests": false` keeps one release PR for the whole repo — usually what people want. `true` means one PR per package.
- Use `"linked-versions"` only when packages must share a single version number.
- Downstream jobs then read path-prefixed outputs: `steps.release.outputs['crates/api--release_created']`.

## Outputs

| Output | Meaning |
|---|---|
| `releases_created` | `"true"` if any release happened |
| `paths_released` | JSON array of released paths |
| `release_created`, `tag_name`, `version`, `major`, `minor`, `patch`, `sha`, `body` | root package only (path `.`) |
| `<path>--release_created`, `<path>--tag_name`, … | per-package, monorepo |

All outputs are **strings**. `if: needs.x.outputs.release_created == 'true'` — a bare truthiness check passes on the string `"false"` and publishes on every push to main.

## The token problem

By design, anything done with the default `GITHUB_TOKEN` does not trigger other workflows. So when release-please merges its PR and pushes a tag using `GITHUB_TOKEN`, **no publish or deploy workflow starts**. The release silently produces no artifacts.

Two fixes, best first:

### GitHub App token (recommended)

Create a small GitHub App owned by the user or org, with repository permissions `contents: write` and `pull_requests: write`, installed on the repo. Store `app-id` as a variable and the private key as a secret, then:

```yaml
      - uses: actions/create-github-app-token@bcd2ba49218906704ab6c1aa796996da409d3eb1 # v3.2.0
        id: app-token
        with:
          app-id: ${{ vars.RELEASE_APP_ID }}
          private-key: ${{ secrets.RELEASE_APP_PRIVATE_KEY }}

      - uses: googleapis/release-please-action@45996ed1f6d02564a971a2fa1b5860e934307cf7 # v5.0.0
        id: release
        with:
          token: ${{ steps.app-token.outputs.token }}
          config-file: release-please-config.json
          manifest-file: .release-please-manifest.json
```

Tokens are short-lived, scoped to one repo, and attributed to the app rather than a person.

### Classic PAT (fallback)

A fine-grained PAT with `contents: write` + `pull_requests: write` stored as `RELEASE_TOKEN`. Simpler, but it expires, it is tied to one human's account, and it acts with that human's permissions everywhere.

### Staying on `GITHUB_TOKEN`

Acceptable when nothing downstream needs to fire. It still requires **Settings → Actions → General → Allow GitHub Actions to create and approve pull requests** to be enabled, or release-please fails with a 403 it does not explain well.

## Interaction with the other pieces

- The PR title lint's allowed `types` must cover every type in `changelog-sections`, or a legal PR title yields an empty changelog entry.
- Renovate's commits are `chore(deps):` / `fix(deps):`. `chore` hidden + `fix` visible means dependency *fixes* appear in the changelog and routine bumps do not. That is usually right; the alternative is a `deps` section.
- `release-please` only reads the default branch. A PR merged into a release branch does nothing until it reaches `main`.

## Verifying without releasing

```bash
npx --yes release-please release-pr \
  --token "$(gh auth token)" \
  --repo-url "$(gh repo view --json nameWithOwner -q .nameWithOwner)" \
  --config-file release-please-config.json \
  --manifest-file .release-please-manifest.json \
  --dry-run
```

Read the proposed version and changelog before the first real run. This is the cheapest way to catch a wrong manifest seed.

## Common mistakes

| Mistake | Consequence | Fix |
|---|---|---|
| Missing manifest file | Version restarts or jumps to 1.0.0 | Seed it from the latest tag |
| Truthy check on `release_created` | Publishes on every push to main | `== 'true'` |
| `GITHUB_TOKEN` with a publish job | Release tagged, nothing published | App token |
| No `bootstrap-sha` on legacy history | First changelog contains the entire git history | Set it |
| Workspace plugin omitted in a monorepo | Internal version references go stale | Add `cargo-workspace` / `node-workspace` |
| `include-component-in-tag` left on for a single root package | Tags become `root-v1.0.0` | `false` for the root package |
| Editing `CHANGELOG.md` by hand | Next release PR conflicts and needs manual surgery | Never touch it |
