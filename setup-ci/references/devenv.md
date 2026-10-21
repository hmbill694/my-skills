# devenv: the toolchain layer

devenv owns **every version of every tool**. Nothing else in the repo pins a toolchain version.

Verified against devenv 2.2.0. Reference: <https://devenv.sh/reference/options/>

## Files

| File | Committed | Purpose |
|---|---|---|
| `devenv.nix` | yes | the environment |
| `devenv.yaml` | yes | flake inputs (nixpkgs, git-hooks) |
| `devenv.lock` | yes | pinned inputs — Renovate refreshes it |
| `.envrc` | yes | direnv auto-entry |
| `.devenv/`, `.direnv/`, `.pre-commit-config.yaml` | no | add to `.gitignore` |

`.pre-commit-config.yaml` is a symlink into the Nix store. Never commit it, never hand-edit it.

## `.envrc`

Prefer the hash-free form. It always matches the installed devenv, and there is no URL or hash to rot:

```bash
eval "$(devenv direnvrc)"

use devenv
```

The widely copied pinned form also works:

```bash
source_url "https://raw.githubusercontent.com/cachix/devenv/82c0147677e510b247d8b9165c54f73d32dfd899/direnvrc" "sha256-7u4iDd1nZpxL4tCzmPG0dQgC5V+/44Ba+tHkPob1v2k="

use devenv
```

That URL and hash are verified as of this writing — do **not** "correct" them from memory, and do not invent a different rev. If you change the rev you must recompute the hash (`curl -sL <url> | openssl dgst -sha256 -binary | openssl base64 -A`), because a wrong one makes direnv fail on every `cd` into the repo. Writing a fabricated URL or hash here is a common and very annoying failure; the `eval` form avoids the whole class.

## `devenv.yaml`

```yaml
# yaml-language-server: $schema=https://devenv.sh/devenv.schema.json
inputs:
  nixpkgs:
    url: github:cachix/devenv-nixpkgs/rolling
  git-hooks:
    url: github:cachix/git-hooks.nix
    inputs:
      nixpkgs:
        follows: nixpkgs
```

The `git-hooks` input is **required** for `git-hooks.hooks` to exist. Without it you get a confusing "option does not exist" error.

## Shared skeleton

```nix
{ pkgs, ... }:

{
  # Tools every recipe in the justfile needs.
  packages = [
    pkgs.just
    pkgs.git
  ];

  # <language block goes here>

  # Runs at commit time; `devenv test` replays them in CI.
  git-hooks.hooks = {
    # <language hooks>
  };

  enterShell = ''
    just --list
  '';
}
```

`packages` must contain `pkgs.just` — CI calls `just` from inside the devenv shell, so it has to come from the environment, not the runner image.

## Rust

```nix
  languages.rust = {
    enable = true;
    channel = "stable";
    components = [ "rustc" "cargo" "clippy" "rustfmt" "rust-analyzer" ];
  };

  packages = [
    pkgs.just
    pkgs.git
    pkgs.cargo-nextest
    pkgs.cargo-audit
    pkgs.pkg-config
    pkgs.openssl
  ];

  git-hooks.hooks = {
    rustfmt.enable = true;
    clippy = {
      enable = true;
      settings.allFeatures = true;
    };
  };
```

Pin an exact version with `channel = "stable"` plus `rustToolchain.version`, or keep a `rust-toolchain.toml` and set `channel = "stable"` — **pick one**; two sources of truth is the failure this layer exists to prevent.

## Go

```nix
  # No version pin: Go comes from nixpkgs, which devenv.lock pins and the
  # weekly `devenv update` workflow refreshes. Everything is a binary-cache hit.
  languages.go.enable = true;

  packages = [
    pkgs.just
    pkgs.git
    pkgs.golangci-lint
    pkgs.govulncheck
    pkgs.gotestsum
  ];

  git-hooks.hooks = {
    gofmt.enable = true;
    govet = {
      enable = true;
      pass_filenames = false;
    };
    golangci-lint = {
      enable = true;
      pass_filenames = false;
    };
  };
```

`pass_filenames = false` matters: these tools take packages, not file paths, and pre-commit passes file paths by default.

**Do not reach for `languages.go.version` by reflex.** Reading devenv's `src/modules/languages/go.nix`, that option does two things people do not expect:

1. It resolves through a **`go-overlay` input** (`github:purpleclay/go-overlay`) which must be declared in `devenv.yaml`, or evaluation fails with a confusing missing-input error.
2. It sets `buildGoModule` to the pinned Go and rebuilds the whole Go tool suite — `gopls`, `delve`, `go-tools` — **from source**, because the binary cache only has them built against nixpkgs' default Go. That is minutes of compilation on every cold CI run, and it can fail outright when the pinned Go is older than the tools require.

Only pin an exact patch when you genuinely need one, and then take all three costs knowingly:

```nix
  # devenv.yaml must also declare:
  #   go-overlay:
  #     url: github:purpleclay/go-overlay
  #     inputs: { nixpkgs: { follows: nixpkgs } }
  languages.go = {
    enable = true;
    version = "1.26.7";
  };
```

For nearly every project the unpinned form is right: the exact Go that *ships* is pinned by the Dockerfile's base image, which is a separate number and the one that matters in production.

## TypeScript / Node

```nix
  languages.javascript = {
    enable = true;
    package = pkgs.nodejs_22;
    pnpm = {
      enable = true;
      install.enable = true;   # keeps node_modules in sync on shell entry
    };
  };

  packages = [
    pkgs.just
    pkgs.git
  ];

  git-hooks.hooks = {
    eslint.enable = true;
    prettier.enable = true;
  };
```

Swap `pnpm` for `npm`/`yarn`/`bun` to match the lockfile in the repo — never introduce a second package manager.

Node linters come from `node_modules` via the lockfile, not from nixpkgs. That is the one intentional exception to "devenv owns every version": the *runtime* is pinned in `devenv.nix`, the *libraries* in the lockfile.

## Services for tests

```nix
  services.postgres = {
    enable = true;
    package = pkgs.postgresql_17;
    initialDatabases = [ { name = "app_test"; } ];
    listen_addresses = "127.0.0.1";
  };

  env.DATABASE_URL = "postgres://127.0.0.1:5432/app_test";
```

Started by `devenv up`, not by `devenv shell`. If integration tests need it, the recipe must start it — see `test-all` in [justfile.md](justfile.md).

## Using it from CI

The canonical pattern (from devenv's own GitHub Actions docs):

```yaml
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
        shell: bash            # required: devenv does not exist yet
        run: nix profile add nixpkgs#devenv

      - run: just fmt-check
```

Three things break if you get them wrong:

1. `nix profile add`, not `nix profile install` (renamed in Nix 2.30).
2. The install step needs `shell: bash` explicitly, because `defaults.run` would otherwise try to use a devenv shell that does not exist yet.
3. `cachix-action` with `name: devenv` reads the **public** devenv cache — no token, no account. Only set `authToken` if the user has their own cache (B5).

## Common mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| `git-hooks` input missing from `devenv.yaml` | "The option `git-hooks.hooks` does not exist" | Add the input |
| `just` not in `packages` | CI step fails with `just: command not found` | Add `pkgs.just` |
| `devenv.lock` not committed | Every CI run resolves different inputs; builds are unreproducible | Commit it |
| A `setup-<lang>` action also in the workflow | Two toolchains on PATH; the wrong one wins | Delete the action |
| Channel `nightly` for a production service | Random breakage on unrelated PRs | `stable`, pinned |
| `languages.go.version` without the `go-overlay` input | Evaluation fails on a missing input, with no hint which one | Declare it, or drop the pin |
| Pinning an **older** toolchain than the tooling needs | The shell fails to build: the pin rebuilds `gopls`/`staticcheck`/`delve` from source, and current versions need Go ≥ 1.26 | Prefer no pin; leave `go.mod`'s `go` directive (your minimum *language* version) alone — it is a different number and need not match |
| Assuming `go.mod`'s `go` directive must equal the devenv toolchain | Chasing a mismatch that is not a bug | Three independent numbers: `go.mod` = minimum language version, devenv = dev toolchain, Dockerfile base = what ships |
| Fabricated `.envrc` URL or hash | direnv fails on every `cd` into the repo | Use `eval "$(devenv direnvrc)"` |
| Services declared but nothing starts them | Integration tests fail only in CI | `devenv up -d` in the recipe |
