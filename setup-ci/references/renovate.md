# Renovate: dependency updates

Renovate opens PRs for dependency updates. CI judges them; automerge lands the boring ones. Enable it **after** CI is green — otherwise you get thirty PRs and no gate to evaluate them with.

Default setup is the hosted GitHub App plus a committed `renovate.json`. No workflow, no token, no secret.

## `renovate.json`

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "config:recommended",
    "helpers:pinGitHubActionDigests",
    ":dependencyDashboard",
    ":semanticCommits",
    ":semanticCommitTypeAll(chore)"
  ],
  "timezone": "Etc/UTC",
  "schedule": ["before 6am on monday"],
  "prConcurrentLimit": 5,
  "prHourlyLimit": 2,
  "labels": ["dependencies"],
  "rangeStrategy": "bump",
  "platformAutomerge": true,
  "lockFileMaintenance": {
    "enabled": true,
    "schedule": ["before 6am on monday"]
  },
  "vulnerabilityAlerts": {
    "labels": ["dependencies", "security"],
    "schedule": ["at any time"],
    "automerge": false
  },
  "packageRules": [
    {
      "description": "GitHub Actions: automerge non-major",
      "matchManagers": ["github-actions"],
      "matchUpdateTypes": ["minor", "patch", "digest"],
      "groupName": "github actions",
      "automerge": true
    },
    {
      "description": "Dev dependencies: group and automerge non-major",
      "matchDepTypes": ["devDependencies", "dev-dependencies", "build-dependencies"],
      "matchUpdateTypes": ["minor", "patch"],
      "groupName": "dev dependencies",
      "automerge": true
    },
    {
      "description": "Runtime dependencies: a human reads these",
      "matchDepTypes": ["dependencies", "require"],
      "automerge": false
    },
    {
      "description": "Majors wait a week and always get a review",
      "matchUpdateTypes": ["major"],
      "addLabels": ["major-update"],
      "minimumReleaseAge": "7 days",
      "automerge": false
    },
    {
      "description": "Docker base images: pin to digests too",
      "matchManagers": ["dockerfile"],
      "groupName": "docker base images",
      "pinDigests": true,
      "automerge": false
    },
    {
      "description": "Action digest bumps are mechanical once the version is unchanged",
      "matchManagers": ["github-actions"],
      "matchUpdateTypes": ["digest", "pin", "pinDigest"],
      "automerge": true
    }
  ]
}
```

Why each piece is there:

- `helpers:pinGitHubActionDigests` is what makes SHA pinning maintainable. It sets `pinDigests` for dep types `action` and `workflow`, so Renovate pins any tag it finds to a digest and then keeps the SHA **and** its trailing version comment in step on every update. Without this preset, SHA-pinned actions silently freeze forever — the worst of both worlds, since you also stop getting security fixes.

  There is a stricter sibling, `helpers:pinGitHubActionDigestsToSemver`, which makes the maintained comment a full `vX.Y.Z` instead of whatever tag the action publishes. It matches the exact-version comments the resolver script emits, but it assumes every action tags full semver — and some do not (`cachix/cachix-action` ships a bare `v17`). Use it only if every action in the repo tags `vX.Y.Z`, and re-verify after the first Renovate run.
- `:semanticCommits` + `:semanticCommitTypeAll(chore)` makes every Renovate commit `chore(deps): …`, which the PR title lint accepts and release-please hides from the changelog. Without it, Renovate's titles fail the PR title check and every dependency PR is red.
- `platformAutomerge: true` uses GitHub's own auto-merge, so the PR merges when required checks pass instead of Renovate polling. It requires auto-merge to be enabled in repo settings.
- `minimumReleaseAge` on majors means you are not the one who discovers a release was yanked.
- **`matchDepTypes` values are ecosystem-specific** — trim the rule to the ones your repo actually has. Node uses `dependencies`/`devDependencies`, Rust uses `dependencies`/`dev-dependencies`/`build-dependencies`, and **Go has no dev-dependency concept at all**: every `require` in `go.mod` is one depType. Left as-is in a Go repo, the dev-dependency rule is inert config that reads as if dev deps automerge when nothing does. Either delete it or replace it with an explicit `matchManagers: ["gomod"]` rule saying what you actually want.
- `rangeStrategy: "bump"` updates the manifest range as well as the lockfile, so the pin and the lock stay consistent.

## devenv and Nix: what Renovate can and cannot do

Renovate's `nix` manager supports **`flake.lock` only** — input updates and `lockFileMaintenance`. It does **not** read `devenv.lock` or `devenv.yaml`. Anyone who tells you `lockFileMaintenance` keeps devenv fresh is wrong.

Two mechanisms cover the gap.

### 1. Custom manager for version pins in `devenv.nix`

Annotate each pin, then let one generic regex manager handle all of them:

```nix
  # renovate: datasource=golang-version depName=go
  goVersion = "1.26.3";
```

```json
  "customManagers": [
    {
      "customType": "regex",
      "description": "Version pins annotated with a renovate comment in devenv.nix",
      "managerFilePatterns": ["/^devenv\\.nix$/"],
      "matchStrings": [
        "#\\s*renovate:\\s*datasource=(?<datasource>\\S+)\\s+depName=(?<depName>\\S+)(\\s+versioning=(?<versioning>\\S+))?\\s*\\n\\s*\\S+\\s*=\\s*\"(?<currentValue>[^\"]+)\""
      ],
      "versioningTemplate": "{{#if versioning}}{{{versioning}}}{{else}}semver{{/if}}"
    }
  ]
```

`managerFilePatterns` replaced `fileMatch` in Renovate 40. Use `managerFilePatterns` for the hosted app; only fall back to `fileMatch` for a self-hosted runner pinned below 40.

### 2. Scheduled `devenv update`

`devenv.lock` can only be refreshed by devenv itself, so run it on a schedule and let it open a PR:

```yaml
name: devenv update

on:
  schedule:
    - cron: "0 5 * * 1"
  workflow_dispatch:

permissions:
  contents: read

jobs:
  update:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    permissions:
      contents: write
      pull-requests: write
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: cachix/install-nix-action@13d8dd58da0234aa297dedd986986ccb8e7f3e24 # v31.11.1
      - uses: cachix/cachix-action@38b082610b782e7e93e209c35fd730d399dee866 # v17
        with:
          name: devenv
      - name: Install devenv
        run: nix profile add nixpkgs#devenv

      - name: Update devenv inputs
        run: devenv update

      - name: Verify the environment still builds
        run: devenv test

      - uses: peter-evans/create-pull-request@5f6978faf089d4d20b00c7766989d076bb2fc7f1 # v8.1.1
        with:
          branch: chore/devenv-update
          title: "chore(deps): update devenv inputs"
          commit-message: "chore(deps): update devenv inputs"
          body: |
            Automated `devenv update`. `devenv test` passed.
          labels: dependencies
          delete-branch: true
```

`devenv test` in the same job is the point — an unverified lock bump is worse than a stale one. Note this workflow's PR will not trigger other workflows if it uses `GITHUB_TOKEN`; give it the same app token as release-please if CI must run on it (see [releases.md](releases.md)).

## Enabling it

Renovate is enabled by installing the app, not by committing the file:

1. <https://github.com/apps/renovate> → Install → select the repository.
2. Renovate opens an onboarding PR ("Configure Renovate"). Because `renovate.json` already exists, that PR only confirms detection — read it, then merge or close it.
3. The Dependency Dashboard issue appears. It is the control surface: check a box there to force a PR outside the schedule.

Validate before committing:

```bash
npx --yes --package renovate -- renovate-config-validator renovate.json
```

Run this against a current Renovate — an old npx cache will reject `managerFilePatterns` and send you chasing a non-problem.

## Automerge prerequisites

Automerge silently does nothing unless all of these hold:

- **Settings → General → Allow auto-merge** is on.
- Branch protection requires at least one status check (otherwise there is nothing to wait for, and Renovate declines to merge).
- Required checks actually run on Renovate branches — they do, since Renovate pushes as an app, not with `GITHUB_TOKEN`.
- The rule does not also require a human review. A required approval and automerge are mutually exclusive; pick one per dependency class.

## Interaction with the other pieces

| Piece | Interaction |
|---|---|
| PR title lint | `:semanticCommitTypeAll(chore)` is what keeps Renovate titles valid |
| release-please | `chore(deps)` hidden from the changelog; `fix(deps)` for vulnerability fixes shows up |
| devenv | Pins in `devenv.nix` via custom manager; `devenv.lock` via the scheduled workflow |
| Dockerfile | `dockerfile` manager bumps the `ARG`-pinned base images — keep them equal to the devenv versions |
| GitHub Actions | `helpers:pinGitHubActionDigests` is what makes full-SHA pinning survivable — it maintains the SHA and its version comment together |

## Common mistakes

| Mistake | Consequence | Fix |
|---|---|---|
| Expecting Renovate to update `devenv.lock` | Toolchain quietly rots for a year | Scheduled `devenv update` |
| No `:semanticCommits` with PR title linting | Every dependency PR is red | Add the presets |
| Renovate enabled before CI exists | Thirty unreviewable PRs | CI first |
| Automerge on with no required checks | Nothing ever merges, no error anywhere | Require a check |
| No `prConcurrentLimit` | The queue floods on the first run | 5 |
| Committing `renovate.json` and assuming it is live | Nothing happens; the app was never installed | Install the app |
| `fileMatch` on hosted Renovate | Deprecated key, custom manager ignored | `managerFilePatterns` |
| SHA-pinned actions without `helpers:pinGitHubActionDigests` | Actions freeze forever — including their security fixes | Add the preset |
| Hand-editing a pinned SHA or its comment | The two desynchronise; the comment then lies about what runs | Let Renovate do it |
