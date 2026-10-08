# Agent Instructions: nix-basecamp

nix-basecamp brings a machine to a known baseline with one command:
nix-darwin + Home Manager on macOS, standalone Home Manager on Linux,
Homebrew casks, Karabiner rules, and an optional Emacs. `README.md` is the
user-facing description; `docs/adr/` holds the decisions. Read both before a
change that touches what they describe.

## Scope

Basecamp owns the *system*: what is installed and how the host is set up.
It does not own anyone's *home configuration*. In particular it never writes
`~/.emacs`, `~/.emacs.d` or `~/.config/emacs`, and provides no init, theme,
keybindings or package policy (ADR 0001). Something only some users want is
opt-in, with a default that a stranger would keep.

## Public repository

- No personal usernames, host names, IPs or other identifying details in
  code, comments, commits, issues or PRs. The target user is a runtime
  parameter (`id -un`); CI and `nix flake check` use only the `fixture`
  configurations.
- Nothing may assume a particular downstream flake exists.

## Downstream contract

The options and `lib` values listed under "Contract for downstream flakes" in
`README.md` and in ADR 0001 are a public API that downstream flakes build on.
Settable: `basecamp.emacs.enable`, `.gui`, `.nativeComp`;
`basecamp.karabiner.enable` (nix-darwin, default true). Read-only:
`basecamp.emacs.major`, `.package`, `.warmProgram`, `lib.emacs*`; also
`lib.mkDarwin` (`emacs`, `karabiner` arguments)/`lib.mkHome` and
`apps.<system>.plan --no-emacs` / `--no-karabiner`.

- Changing or removing any of them is a breaking change: record it in an ADR
  (new, or amend the existing one) and update the README table in the same
  commit.
- Adding an option: default it so existing downstreams see no change, and
  set it only with `lib.mkDefault` from the setup apps so downstream settings
  win.

## Design rules

- One install path per OS: nix-darwin on macOS, Home Manager on Linux. Under
  nix-darwin the Home Manager module only mirrors the system's values.
- Optional parts are off or keep today's behaviour by default, and the setup
  apps never opt a user in on `--yes`.
- Activation steps are idempotent and safe against hand-edited state (see the
  Karabiner jq upsert). Never delete user files; move them aside.
- Nothing extra on the host at runtime: no perl or python. macOS-only helpers
  are native programs built by nix.
- The Emacs major is pinned in `lib/emacs.nix`; only a new major, or nixpkgs
  dropping the pinned one, changes it.

## Checks before pushing

```sh
nix flake check --all-systems --no-build
nix build ".#checks.$(nix eval --impure --raw --expr builtins.currentSystem).emacs"
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
  `feat(emacs): …`, `CI: …`, `plan: …`, `eln-warm.c: …`. Say what changed
  and why.
- `flake.lock` updates come from the `flake-update` workflow; do not bump
  the lock by hand.

## Issue tracker

GitHub Issues for ajchemist/nix-basecamp, via `gh`.
