# Agent Instructions: nix-basecamp

nix-basecamp brings a machine to a known baseline with one command:
nix-darwin + Home Manager on macOS, standalone Home Manager on Linux,
Homebrew casks and Karabiner rules. `README.md` is the
user-facing description; `docs/adr/` holds the decisions. Read both before a
change that touches what they describe.

## Scope

Basecamp owns the *system*: what is installed and how the host is set up.
It does not own anyone's *home configuration*. Application builds and runtime
configuration belong in separate application flakes. Something only some users
want is opt-in, with a default that a stranger would keep.

## Public repository

- No personal usernames, host names, IPs or other identifying details in
  code, comments, commits, issues or PRs. The target user is a runtime
  parameter (`id -un`); CI and `nix flake check` use only the `fixture`
  configurations.
- Nothing may assume a particular downstream flake exists.

## Downstream contract

The options and `lib` values listed under "Contract for downstream flakes" in
`README.md` and ADR 0002 are a public API that downstream flakes build on.
Settable: `basecamp.karabiner.enable` (nix-darwin, default true).
Builders: `lib.mkDarwin` (`user`, `system`, `karabiner`, `modules`) and
`lib.mkHome` (`user`, `homeDirectory`, `system`, `modules`).
Status: `apps.aarch64-darwin.plan --no-karabiner`.

- Changing or removing any of them is a breaking change: record it in an ADR
  (new, or amend the existing one) and update the README table in the same
  commit.
- Adding an option: default it so existing downstreams see no change, and
  set it only with `lib.mkDefault` from the setup apps so downstream settings
  win.

## Design rules

- One install path per OS: nix-darwin on macOS, Home Manager on Linux.
- Optional parts are off or keep today's behaviour by default, and the setup
  apps never opt a user in on `--yes`.
- Activation steps are idempotent and safe against hand-edited state (see the
  Karabiner jq upsert). Never delete user files; move them aside.
- Nothing extra on the host at runtime: no perl or python. macOS-only helpers
  are native programs built by nix.

## Checks before pushing

```sh
nix flake check --all-systems --no-build
nix build .#darwinConfigurations.fixture.system           # darwin changes
nix build .#darwinConfigurations.fixture-no-karabiner.system
nix build .#homeConfigurations.fixture.activationPackage  # Linux changes
nix run .#plan && nix run . -- --dry-run                  # setup app changes
```

Test an unpublished checkout with `nix run path:.` so untracked files are
included. CI (`.github/workflows/ci.yml`) runs the same checks plus lint
(actionlint, shellcheck, deadnix) and full activations on a macOS runner,
with and without Karabiner. Its jobs are path-filtered: when you add a file
outside `flake.nix`, `flake.lock`, `darwin/`, `home/`, `lib/`, `ci/` or
`.github/`, add it to the `paths` lists and the `changes` filters there.
`flake-update.yml` calls `ci.yml`, so a new check reaches both.

## Commits

- One subject line, imperative mood, in English, prefixed with the area:
  `feat(karabiner): …`, `CI: …`, `plan: …`. Say what changed
  and why.
- `flake.lock` updates come from the `flake-update` workflow; do not bump
  the lock by hand.

## Issue tracker

GitHub Issues for ajchemist/nix-basecamp, via `gh`.
