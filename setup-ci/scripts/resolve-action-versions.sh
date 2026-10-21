#!/usr/bin/env bash
# Resolve every action to a full commit SHA plus the version it corresponds to,
# and print ready-to-paste `uses:` lines.
#
# Run this BEFORE writing any workflow. Never type an action version or SHA from
# memory. A mutable tag (@v4, @main) lets whoever controls that tag change what
# your workflow executes — with your secrets in scope. A 40-character SHA cannot
# be moved; the trailing comment keeps it readable, and Renovate maintains both.
#
# Usage:
#   scripts/resolve-action-versions.sh              # the default action set
#   scripts/resolve-action-versions.sh owner/repo … # specific actions
#
# Output: uses: owner/repo@<sha>  # vX.Y.Z

set -euo pipefail

DEFAULT_ACTIONS=(
  actions/checkout
  actions/cache
  actions/upload-artifact
  actions/attest-build-provenance
  actions/create-github-app-token
  cachix/install-nix-action
  cachix/cachix-action
  amannn/action-semantic-pull-request
  googleapis/release-please-action
  docker/setup-buildx-action
  docker/setup-qemu-action
  docker/login-action
  docker/metadata-action
  docker/build-push-action
  peter-evans/create-pull-request
)

if ! command -v gh >/dev/null 2>&1; then
  echo "error: gh is required. Install the GitHub CLI." >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "error: gh is not authenticated. Run 'gh auth login'." >&2
  exit 1
fi

actions=("$@")
if [ ${#actions[@]} -eq 0 ]; then
  actions=("${DEFAULT_ACTIONS[@]}")
fi

failed=0

for repo in "${actions[@]}"; do
  # Prefer the latest published release; fall back to the newest semver tag for
  # actions that tag without cutting releases.
  tag=$(gh api "repos/${repo}/releases/latest" --jq .tag_name 2>/dev/null || true)

  if [ -z "${tag}" ]; then
    tag=$(gh api "repos/${repo}/tags?per_page=100" \
      --jq '[.[].name | select(test("^v?[0-9]+\\.[0-9]+\\.[0-9]+$"))] | first // empty' 2>/dev/null || true)
  fi

  if [ -z "${tag}" ]; then
    printf '# %-45s UNRESOLVED — check manually\n' "${repo}"
    failed=1
    continue
  fi

  # Resolve the tag to the commit it points at. This dereferences annotated
  # tags, which a git/ref/tags lookup would leave as a tag object.
  sha=$(gh api "repos/${repo}/commits/${tag}" --jq .sha 2>/dev/null || true)

  if [ ${#sha} -ne 40 ]; then
    printf '# %-45s tag %s did not resolve to a commit SHA\n' "${repo}" "${tag}"
    failed=1
    continue
  fi

  printf 'uses: %s@%s # %s\n' "${repo}" "${sha}" "${tag}"
done

cat <<'EOF'

Paste these verbatim, comment included — Renovate's helpers:pinGitHubActionDigests
preset updates the SHA and rewrites the comment together. Editing either by hand
desynchronises them, and then the comment lies about what runs.
EOF

exit "${failed}"
