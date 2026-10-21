# Repository settings: what files cannot do

Several parts of this setup depend on GitHub settings that live outside the repo. Skipping them produces the worst failure mode: everything looks configured and nothing works.

Hand the user this list explicitly in Phase 5. Offer to run the `gh` commands; some need admin rights you may not have.

## 1. Merge strategy — squash, title from the PR

The whole conventional-commit chain assumes the commit that lands on `main` carries the PR title.

```bash
gh api -X PATCH "repos/{owner}/{repo}" \
  -F allow_squash_merge=true \
  -F allow_merge_commit=false \
  -F allow_rebase_merge=false \
  -F allow_auto_merge=true \
  -F delete_branch_on_merge=true \
  -f squash_merge_commit_title=PR_TITLE \
  -f squash_merge_commit_message=PR_BODY
```

Without `squash_merge_commit_title=PR_TITLE`, GitHub uses the branch's commit message instead. A PR titled `feat: add retries` then lands as `wip fix stuff`, the PR title check passes, and release-please sees nothing to release. This single setting is the most common reason "conventional commits are set up" but no releases ever appear.

`allow_auto_merge=true` is also what Renovate's `platformAutomerge` needs.

## 2. Let Actions open pull requests

release-please needs this whenever it runs with the default `GITHUB_TOKEN`:

```bash
gh api -X PUT "repos/{owner}/{repo}/actions/permissions/workflow" \
  -f default_workflow_permissions=read \
  -F can_approve_pull_request_reviews=true
```

UI path: **Settings → Actions → General → Workflow permissions**. Without it release-please fails with a 403 whose message does not mention this setting.

`default_workflow_permissions=read` is the safe default because every workflow in [workflows.md](workflows.md) declares the permissions it needs.

## 3. Branch protection with the right check names

Required check contexts are the **job `name:` values**, not the workflow names or file names. From the templates: `Check`, `Conventional Commits`, `Image`, `Audit`.

```json
{
  "name": "main",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] }
  },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false,
        "allowed_merge_methods": ["squash"]
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": true,
        "required_status_checks": [
          { "context": "Check" },
          { "context": "Conventional Commits" }
        ]
      }
    }
  ]
}
```

```bash
gh api -X POST "repos/{owner}/{repo}/rulesets" --input ruleset.json
```

Decisions to raise with the user rather than assume:

- **Required approvals vs Renovate automerge are mutually exclusive.** `required_approving_review_count: 1` blocks every automerged dependency PR. Either drop the requirement, or add Renovate as a `bypass_actors` entry, or accept that nothing automerges.
- **A solo repo with required reviews cannot merge anything** unless the author bypasses. For a single-maintainer repo, use `required_approving_review_count: 0` and rely on the status checks.
- **`strict_required_status_checks_policy: true`** forces branches up to date before merge. Correct for a small repo, painful at high PR volume.
- Never require a check that is `continue-on-error` and might not report — `Audit` is deliberately left out above.

## 4. GHCR package

The first successful push creates the package. Until then there is nothing to configure.

After the first push:

- **Package settings → Manage Actions access**: confirm the repository has `Write`. Repo-scoped `GITHUB_TOKEN` pushes normally work without touching this; a package that predates the repo link often does not.
- **Visibility**: new packages are private even in a public repo. A public image needs to be set public explicitly.
- **Retention**: untagged `sha-` layers accumulate forever. Add a cleanup workflow or a retention policy once the registry gets large.

## 5. Install Renovate

<https://github.com/apps/renovate> → Install → pick the repository. Committing `renovate.json` alone does nothing. See [renovate.md](renovate.md) for what to expect from the onboarding PR.

## 6. Secrets and variables

| Name | Kind | Needed for |
|---|---|---|
| `RELEASE_APP_ID` | variable | release-please via a GitHub App (recommended) |
| `RELEASE_APP_PRIVATE_KEY` | secret | same |
| `RELEASE_TOKEN` | secret | release-please via a PAT (fallback) |
| `CACHIX_AUTH_TOKEN` | secret | only with a private/own Cachix cache |

```bash
gh variable set RELEASE_APP_ID --body "123456"
gh secret set RELEASE_APP_PRIVATE_KEY < private-key.pem
```

Never paste a private key into a command line — it lands in shell history. Read it from a file and delete the file afterwards.

## 7. Labels

release-please creates `autorelease: pending` and `autorelease: tagged` itself. Renovate needs `dependencies`, `security`, and `major-update` to exist, or it silently skips labelling:

```bash
gh label create dependencies --color 0366d6 --force
gh label create security --color d93f0b --force
gh label create major-update --color fbca04 --force
```

## Verification

```bash
gh api "repos/{owner}/{repo}" \
  --jq '{squash_title: .squash_merge_commit_title, auto_merge: .allow_auto_merge, merge_commit: .allow_merge_commit}'
gh api "repos/{owner}/{repo}/actions/permissions/workflow"
gh ruleset list
gh api "repos/{owner}/{repo}/installation" --jq .app_slug   # is Renovate installed?
```

Report the actual values back to the user. "You should enable squash merges" is not a handoff; "squash_merge_commit_title is currently COMMIT_OR_PR_TITLE, it needs to be PR_TITLE — run this" is.
