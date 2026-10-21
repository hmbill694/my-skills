#!/usr/bin/env bash
# Verify a CI/CD setup, or audit an existing one. Run from the repository root.
#
# Checks only what exists: a repo with no Dockerfile is not penalised for it.
#
# Two modes, same checks:
#
#   scripts/verify-setup.sh [repo-root]
#       Phase 4 gate. Exits non-zero if anything failed.
#
#   scripts/verify-setup.sh --audit [repo-root]
#       Phase 1 gap analysis on a repo that is already partly set up.
#       Always exits 0 — findings are input to the interview, not failures.
#       SKIP = absent (build it)  FAIL = present but broken (repair it)
#       PASS = present and sound (leave it alone)

set -uo pipefail

AUDIT=0
if [ "${1:-}" = "--audit" ]; then
  AUDIT=1
  shift
fi

cd "${1:-.}" || exit 1

PASS=0
FAIL=0
SKIP=0

pass() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=$((FAIL + 1)); }
skip() { printf '  \033[90mSKIP\033[0m  %s\n' "$1"; SKIP=$((SKIP + 1)); }
note() { printf '        %s\n' "$1"; }
head_() { printf '\n\033[1m%s\033[0m\n' "$1"; }

have() { command -v "$1" >/dev/null 2>&1; }

# Read JSON with whatever is available.
json_query() { # json_query <file> <python-expression-on-`d`>
  python3 - "$1" "$2" <<'PY' 2>/dev/null
import json, sys
d = json.load(open(sys.argv[1]))
print(eval(sys.argv[2], {"d": d, "json": json}))
PY
}

# ---------------------------------------------------------------- devenv

head_ "devenv"

if [ -f devenv.nix ]; then
  pass "devenv.nix exists"

  if [ -f devenv.yaml ]; then
    pass "devenv.yaml exists"
    if grep -q 'git-hooks\.hooks' devenv.nix && ! grep -q 'git-hooks' devenv.yaml; then
      fail "devenv.nix uses git-hooks.hooks but devenv.yaml has no git-hooks input"
      note "add: inputs.git-hooks.url = github:cachix/git-hooks.nix"
    else
      pass "git-hooks input consistent with git-hooks.hooks usage"
    fi
  else
    fail "devenv.yaml is missing"
  fi

  if [ -f devenv.lock ]; then
    pass "devenv.lock exists"
    if git rev-parse --git-dir >/dev/null 2>&1; then
      if git ls-files --error-unmatch devenv.lock >/dev/null 2>&1; then
        pass "devenv.lock is tracked by git"
      else
        fail "devenv.lock is not tracked — CI will resolve different inputs than you did"
      fi
    fi
  else
    fail "devenv.lock is missing (run 'devenv shell true' once, then commit it)"
  fi

  if grep -qE 'pkgs\.just' devenv.nix; then
    pass "just is in devenv packages"
  else
    fail "pkgs.just not in devenv.nix packages — CI steps calling just will not find it"
  fi

  for ignore in .devenv .direnv; do
    if [ -f .gitignore ] && grep -qE "^/?${ignore}/?$" .gitignore; then
      pass "$ignore is gitignored"
    else
      fail "$ignore is not in .gitignore"
    fi
  done

  if have devenv; then
    if devenv --version >/dev/null 2>&1; then
      note "run 'devenv test' separately — it builds the shell and is slow"
    fi
  else
    skip "devenv not installed locally"
  fi
else
  skip "no devenv.nix"
fi

# ---------------------------------------------------------------- justfile

head_ "justfile"

if [ -f justfile ] || [ -f Justfile ]; then
  if ! have just; then
    skip "just not installed — cannot parse the justfile"
  else
    if just --summary >/dev/null 2>&1; then
      pass "justfile parses"
    else
      fail "justfile does not parse"
      just --summary 2>&1 | sed 's/^/        /' | head -10
    fi

    if just --unstable --fmt --check >/dev/null 2>&1; then
      pass "justfile is formatted"
    else
      fail "justfile is not formatted (run: just --unstable --fmt)"
    fi

    recipes=$(just --summary 2>/dev/null | tr ' ' '\n')
    for r in fmt fmt-check lint test build ci; do
      if printf '%s\n' "$recipes" | grep -qx "$r"; then
        pass "recipe '$r' exists"
      else
        fail "recipe '$r' is missing from the contract"
      fi
    done

    if grep -qE '^set shell' justfile 2>/dev/null; then
      if grep -qE '^set shell.*pipefail' justfile; then
        pass "shell set with pipefail"
      else
        fail "'set shell' present but without pipefail — failing commands are ignored"
      fi
    else
      fail "no 'set shell := [\"bash\", \"-euo\", \"pipefail\", \"-c\"]'"
    fi
  fi
else
  skip "no justfile"
fi

# ------------------------------------------------------- ci.yml vs just ci

head_ "just ci / CI step parity"

if [ -f .github/workflows/ci.yml ] && [ -f justfile ] && have just; then
  # Only the 'check' job mirrors 'just ci'. Other jobs (audit, image) run
  # deliberately different recipes, so slice out that one job's steps.
  ci_steps=$(awk '
      /^  [a-zA-Z0-9_-]+:[[:space:]]*$/ { injob = ($0 ~ /^  check:/) }
      injob && /^[[:space:]]*- run: just / { print }
    ' .github/workflows/ci.yml \
    | sed -E 's/.*just //' | tr '\n' ' ' | sed -E 's/[[:space:]]+$//')
  ci_recipe=$(just --dump --dump-format just 2>/dev/null \
    | grep -E '^ci:' | sed -E 's/^ci:[[:space:]]*//' | tr -s ' ' | sed -E 's/[[:space:]]+$//')

  if [ -z "$ci_recipe" ]; then
    skip "'ci' recipe has no dependency list to compare (it may use a body)"
    note "CI steps run: ${ci_steps:-none}"
  elif [ "$ci_steps" = "$ci_recipe" ]; then
    pass "CI steps match 'just ci' ($ci_recipe)"
  else
    fail "CI steps and 'just ci' disagree"
    note "ci.yml  : ${ci_steps:-none}"
    note "just ci : ${ci_recipe}"
  fi
else
  skip "need both ci.yml and a justfile to compare"
fi

# ---------------------------------------------------------------- workflows

head_ "GitHub Actions"

if [ -d .github/workflows ]; then
  count=$(find .github/workflows -maxdepth 1 -name '*.yml' -o -maxdepth 1 -name '*.yaml' | wc -l | tr -d ' ')
  pass "$count workflow file(s) found"

  actionlint=""
  if have actionlint; then
    actionlint="actionlint"
  elif have nix; then
    actionlint="nix run nixpkgs#actionlint --"
  fi

  if [ -n "$actionlint" ]; then
    if out=$($actionlint 2>&1); then
      pass "actionlint clean"
    else
      fail "actionlint reported problems"
      printf '%s\n' "$out" | sed 's/^/        /' | head -25
    fi
  else
    skip "actionlint unavailable (install it, or run via nix)"
  fi

  for f in .github/workflows/*.yml .github/workflows/*.yaml; do
    [ -f "$f" ] || continue
    if grep -qE '^\s*timeout-minutes:' "$f"; then
      pass "$(basename "$f") sets timeout-minutes"
    else
      fail "$(basename "$f") has no timeout-minutes on any job"
    fi
    if grep -qE '^permissions:|^\s{4}permissions:' "$f"; then
      pass "$(basename "$f") declares permissions"
    else
      fail "$(basename "$f") declares no permissions block"
    fi
  done

  # Every third-party action must be pinned to a 40-char SHA with a version
  # comment. Local actions (./...) and reusable workflows are exempt.
  unpinned=$(grep -rhnE '^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*[^.#]' .github/workflows 2>/dev/null \
    | grep -vE '@[0-9a-f]{40}([[:space:]]|$)' || true)
  if [ -n "$unpinned" ]; then
    fail "action(s) not pinned to a full commit SHA — a mutable tag runs with your secrets"
    printf '%s\n' "$unpinned" | sed 's/^/        /' | head -12
  else
    pass "all actions pinned to full commit SHAs"
  fi

  nocomment=$(grep -rhnE '@[0-9a-f]{40}' .github/workflows 2>/dev/null \
    | grep -vE '@[0-9a-f]{40}[[:space:]]+#' || true)
  if [ -n "$nocomment" ]; then
    fail "SHA-pinned action(s) with no version comment — nobody can tell what they are"
    printf '%s\n' "$nocomment" | sed 's/^/        /' | head -12
  elif [ -z "$unpinned" ]; then
    pass "every pinned action carries a version comment"
  fi

  # Toolchain must come from devenv only. Without devenv this is not yet a
  # defect — it is the thing devenv is about to take over.
  setup=$(grep -rlE 'uses:[[:space:]]*(actions/setup-(node|python|go|java)|dtolnay/rust-toolchain|ruby/setup-ruby)' .github/workflows 2>/dev/null)
  if [ -n "$setup" ]; then
    if [ -f devenv.nix ]; then
      fail "a setup-<lang> action is used alongside devenv — two toolchain sources"
      printf '%s\n' "$setup" | sed 's/^/        /'
    else
      note "CI pins the toolchain itself ($(printf '%s' "$setup" | tr '\n' ' ')) — devenv should take this over"
    fi
  elif [ -f devenv.nix ]; then
    pass "no setup-<lang> actions competing with devenv"
  fi

  # release_created must be compared as a string.
  if grep -rn 'release_created' .github/workflows >/dev/null 2>&1; then
    if grep -rn 'release_created' .github/workflows | grep -qE "release_created\s*==\s*'true'"; then
      pass "release_created compared as a string"
    else
      fail "release_created used without == 'true' — publishes on every push"
      grep -rn 'release_created' .github/workflows | sed 's/^/        /'
    fi
  fi

  # :latest belongs to the main-push image job. metadata-action's default
  # latest=auto adds it to any semver tag, so a release job must opt out.
  for wf in .github/workflows/*.y*ml; do
    grep -q 'docker/metadata-action' "$wf" && grep -q 'type=semver' "$wf" || continue
    if grep -qE 'type=raw,value=latest' "$wf" || ! grep -qE 'latest=false' "$wf"; then
      fail "$(basename "$wf") tags releases :latest — set flavor: latest=false; :latest is the main-push image"
    else
      pass "$(basename "$wf") leaves :latest to the main-push image"
    fi
  done
else
  skip "no .github/workflows"
fi

# ---------------------------------------------------------------- docker

head_ "Docker"

if [ -f Dockerfile ]; then
  pass "Dockerfile exists"

  if [ -f .dockerignore ]; then
    pass ".dockerignore exists"
    for d in .git node_modules target .devenv; do
      grep -qxF "$d" .dockerignore || note "consider adding '$d' to .dockerignore"
    done
  else
    fail ".dockerignore is missing — the build context will include build output"
  fi

  stages=$(grep -cE '^[[:space:]]*FROM[[:space:]]' Dockerfile)
  if [ "$stages" -gt 1 ]; then
    pass "Dockerfile is multi-stage ($stages stages)"
  else
    fail "Dockerfile is single-stage — the image ships the whole toolchain"
  fi

  if grep -qE '^\s*USER\s+' Dockerfile; then
    pass "Dockerfile sets USER"
  else
    fail "Dockerfile never sets USER — the container runs as root"
  fi

  if grep -qE '^\s*(ENTRYPOINT|CMD)\s*\[' Dockerfile; then
    pass "ENTRYPOINT/CMD uses exec form"
  else
    fail "ENTRYPOINT/CMD is in shell form — signals will not reach the process"
  fi

  if grep -qE 'FROM\s+\S+:latest' Dockerfile; then
    fail "a base image is pinned to :latest"
  else
    pass "no :latest base images"
  fi

  # Comments are stripped first — the templates legitimately mention devenv.nix
  # in a "keep in sync" comment. The pattern is narrow on purpose: a bare 'nix'
  # matches GOOS=linux and a bare 'just' matches adjust.
  if grep -vE '^[[:space:]]*#' Dockerfile \
     | grep -qE '(devenv|nix-shell|nix (build|develop|profile|run)|(^|&&|;)[[:space:]]*just )'; then
    fail "Dockerfile references devenv/nix/just — it must build from a plain checkout"
  else
    pass "Dockerfile is independent of devenv"
  fi

  if have docker && docker info >/dev/null 2>&1; then
    if out=$(docker build --check . 2>&1); then
      pass "docker build --check clean"
    else
      fail "docker build --check reported problems"
      printf '%s\n' "$out" | grep -vE '^#[0-9]' | sed 's/^/        /' | head -20
    fi
  else
    skip "docker unavailable — could not lint or build the image"
  fi
else
  skip "no Dockerfile"
fi

# ---------------------------------------------------------------- releases

head_ "release-please"

if [ -f release-please-config.json ]; then
  if json_query release-please-config.json 'len(d["packages"])' >/dev/null 2>&1; then
    pass "release-please-config.json is valid JSON with packages"
  else
    fail "release-please-config.json is not valid JSON, or has no 'packages'"
  fi

  if [ -f .release-please-manifest.json ]; then
    manifest_len=$(json_query .release-please-manifest.json 'len(d)' 2>/dev/null || echo 0)
    if [ "${manifest_len:-0}" -gt 0 ]; then
      pass ".release-please-manifest.json seeds $manifest_len version(s)"
      note "$(cat .release-please-manifest.json | tr -d '\n')"
    else
      fail ".release-please-manifest.json is empty — the first release will restart versioning"
    fi

    cfg_paths=$(json_query release-please-config.json '" ".join(sorted(d["packages"].keys()))' 2>/dev/null)
    man_paths=$(json_query .release-please-manifest.json '" ".join(sorted(d.keys()))' 2>/dev/null)
    if [ "$cfg_paths" = "$man_paths" ]; then
      pass "config and manifest cover the same paths"
    else
      fail "config/manifest path mismatch"
      note "config  : $cfg_paths"
      note "manifest: $man_paths"
    fi
  else
    fail ".release-please-manifest.json is missing"
  fi

  if git rev-parse --git-dir >/dev/null 2>&1; then
    tag=$(git describe --tags --abbrev=0 2>/dev/null || true)
    if [ -n "$tag" ]; then
      note "latest git tag is $tag — confirm the manifest agrees"
    fi
  fi
else
  skip "no release-please-config.json"
fi

# ---------------------------------------------------------------- renovate

head_ "Renovate"

renovate_file=""
for f in renovate.json .github/renovate.json .renovaterc.json; do
  [ -f "$f" ] && renovate_file="$f" && break
done

if [ -n "$renovate_file" ]; then
  pass "$renovate_file exists"

  if grep -q 'semanticCommit' "$renovate_file"; then
    pass "semantic commit presets configured"
  else
    fail "no semanticCommits preset — Renovate PR titles will fail the PR title check"
  fi

  if grep -q 'fileMatch' "$renovate_file"; then
    fail "'fileMatch' is deprecated — use 'managerFilePatterns'"
  fi

  if have npx; then
    # Pin @latest: an npx cache holding an old major rejects current keys such
    # as managerFilePatterns and sends you chasing a config error that is not there.
    if out=$(npx --yes --package renovate@latest -- renovate-config-validator "$renovate_file" 2>&1); then
      pass "renovate config validated"
    else
      fail "renovate config validation failed"
      printf '%s\n' "$out" | grep -vE '^npm (warn|notice)' | sed 's/^/        /' | head -20
    fi
  else
    skip "npx unavailable — could not validate the renovate config"
  fi
else
  skip "no renovate config"
fi

# -------------------------------------------------------- competing tools

head_ "Competing tools"

competing=0

if [ -f Makefile ] || [ -f makefile ]; then
  competing=1
  if [ -f justfile ] || [ -f Justfile ]; then
    note "Makefile AND justfile both present — recipes must delegate to make, not duplicate it"
  else
    note "Makefile owns the commands today — porting to a justfile is the user's decision"
  fi
fi

dependabot=""
for f in .github/dependabot.yml .github/dependabot.yaml; do
  [ -f "$f" ] && dependabot="$f" && break
done
if [ -n "$dependabot" ]; then
  competing=1
  if [ -n "${renovate_file:-}" ]; then
    fail "$dependabot and $renovate_file are both present — duplicate dependency PRs"
  else
    note "$dependabot already does dependency updates — Renovate replaces it; one has to go"
  fi
fi

if [ -f flake.nix ]; then
  competing=1
  note "flake.nix present — devenv can run with flakes; never delete their flake"
fi

if [ -f .pre-commit-config.yaml ] && [ ! -L .pre-commit-config.yaml ]; then
  competing=1
  if [ -f devenv.nix ] && grep -q 'git-hooks\.hooks' devenv.nix; then
    fail ".pre-commit-config.yaml is a real file while devenv also defines git-hooks — two hook sources"
  else
    note ".pre-commit-config.yaml is hand-maintained — devenv's git-hooks would take it over"
  fi
fi

for f in .releaserc .releaserc.json .releaserc.yaml release.config.js .changeset; do
  if [ -e "$f" ]; then
    competing=1
    note "$f present — migrating to release-please is a real migration, not a setup"
  fi
done

for f in .circleci/config.yml .gitlab-ci.yml Jenkinsfile azure-pipelines.yml; do
  if [ -e "$f" ]; then
    competing=1
    note "$f present — moving to GitHub Actions is a platform migration; confirm the intent"
  fi
done

if [ -f CHANGELOG.md ] && [ ! -f release-please-config.json ]; then
  competing=1
  note "CHANGELOG.md is hand-maintained — release-please will take the file over"
fi

if [ "$competing" -eq 0 ]; then
  pass "no competing tools found"
else
  note "see references/gap-analysis.md — none of these may be removed without an explicit yes"
fi

# ---------------------------------------------------------------- summary

head_ "Summary"
printf '  %d passed, %d failed, %d skipped\n\n' "$PASS" "$FAIL" "$SKIP"

if [ "$AUDIT" -eq 1 ]; then
  cat <<'EOF'
Audit mode — nothing above is a failure yet, it is the gap analysis:

  SKIP  absent            -> in scope to build
  FAIL  present, broken   -> in scope to repair (show the user the diff first)
  PASS  present, sound    -> LEAVE IT ALONE; confirm it in the plan, do not regenerate

Two things are never visible from disk and must be asked:
  - whether the Renovate GitHub App is installed
  - whether release PRs need to trigger downstream workflows (the token decision)

Next: references/gap-analysis.md, then scope the interview to the gaps only.
EOF
  exit 0
fi

if [ "$FAIL" -gt 0 ]; then
  echo "Fix the failures above and re-run. Do not report the setup as complete yet."
  exit 1
fi

echo "All applicable checks passed. Remaining work is in references/repo-settings.md"
echo "(merge strategy, branch protection, Renovate app, secrets) — none of it is verifiable from here."
