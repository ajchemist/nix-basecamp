# nix-basecamp

A basecamp for expeditions into any machine — including temporary ones.
One command deploys my pre-arranged minimal setup, so work on a fresh or
borrowed system starts from a safe, fast, systematic base instead of zero.

Nix-native, for macOS and Linux. The flake **is** the CLI.

```sh
# 1) Nix (once per machine)
curl -fsSL https://install.determinate.systems/nix | sh -s -- install

# 2) Everything else — shows the module plan, asks, applies
nix run github:ajchemist/nix-basecamp
```

> **429 fallback**: `github:` fetches the repo via GitHub's archive API, which
> can rate-limit shared IPs (HTTP 429). If that happens, use the plain-git
> form — the result is bit-for-bit identical, only the transport differs:
>
> ```sh
> nix run 'git+https://github.com/ajchemist/nix-basecamp.git'
> ```
>
> (The heavy inputs are pinned in `flake.lock` and largely fetched over git
> already, so only the top-level repo fetch is affected either way.)

## Discoverability

Every module is a flake app, so the standard nix commands reveal everything:

```sh
nix flake show github:ajchemist/nix-basecamp          # list all modules/outputs
nix run  github:ajchemist/nix-basecamp#plan           # status table, read-only
nix run  github:ajchemist/nix-basecamp -- --dry-run   # same, via the default app
```

Apply everything, or a single module:

```sh
nix run github:ajchemist/nix-basecamp                  # plan -> confirm -> apply all
nix run github:ajchemist/nix-basecamp -- --yes         # no prompt
nix run github:ajchemist/nix-basecamp#karabiner-rule   # just the karabiner rule
nix run github:ajchemist/nix-basecamp#darwin           # just nix-darwin activation
nix run github:ajchemist/nix-basecamp#homebrew         # just homebrew
```

The plan looks like:

```
nix-basecamp · Darwin (arm64) · target user: alice

  [•] homebrew        Homebrew package manager                       install
  [•] nix-darwin      system profile                                 activate new generation
  [✓] karabiner       Karabiner-Elements (homebrew cask)             converge on switch
  [✓] karabiner-rule  Korean-mode left modifiers -> karabiner.json   converge on switch

Proceed? [y/N]
```

## What is managed

- **macOS** (aarch64): nix-darwin + home-manager, Homebrew casks
  (Karabiner-Elements), and Karabiner complex-modification rules upserted into
  the selected profile of `~/.config/karabiner/karabiner.json`
  (idempotent jq merge — safe against an existing, hand-edited config).
- **Linux** (x86_64): standalone home-manager.

## Optional Emacs

Emacs is **off by default**. Interactive `nix run github:ajchemist/nix-basecamp`
asks for `gui`, `nox` (terminal only), or `none`. The choice is saved after a
successful setup in `~/.config/nix-basecamp/emacs` and reused on subsequent runs.
`--yes` skips confirmation; it does not opt you into an undecided module.

For an Emacs-only setup, without applying Homebrew, Karabiner, nix-darwin, or
Home Manager:

```sh
nix run github:ajchemist/nix-basecamp#emacs -- --emacs=gui --dry-run
nix run github:ajchemist/nix-basecamp#emacs -- --emacs=gui
# Terminal-only, including a Linux server:
nix run github:ajchemist/nix-basecamp#emacs -- --emacs=nox --yes
# Reapply the saved choice:
nix run github:ajchemist/nix-basecamp#emacs -- --yes
# Remove only the standalone Emacs installation:
nix run github:ajchemist/nix-basecamp#emacs -- --emacs=none --yes
```

The same `--emacs=gui|nox|none` flags work with the default setup command.
`--dry-run` never prompts, writes choices, builds Emacs, or activates anything.
A fresh Emacs-only `--yes` run needs an explicit choice.

The standalone app owns a dedicated GC root at
`~/.local/state/nix-basecamp/emacs/package`, plus symlinks at
`~/.local/bin/emacs` and `~/.local/bin/emacsclient`. Ensure `~/.local/bin` is on
PATH, or run `~/.local/bin/emacs` directly. macOS GUI installs also appear at
`~/Applications/Nix Basecamp Emacs.app`; open that app in Finder or with:

```sh
open "$HOME/Applications/Nix Basecamp Emacs.app"
```

Existing binaries at those destinations are reported as conflicts and preserved.
Other Homebrew/Nix Emacs installations are left in place. The setup preserves
`~/.emacs`, `~/.emacs.d`, XDG init files, packages, and Custom state. It provides
no init, theme, keybindings, or package archive policy. On macOS it warms the
built-in native Lisp first-load checks in the background once per package path;
you can use Emacs while this runs. Removal leaves user config and caches intact.

Downstream Home Manager configurations can use the public module directly:

```nix
{
  imports = [ basecamp.homeModules.emacs ];
  basecamp.emacs = {
    enable = true;
    gui = true; # false for emacs-nox
    # warmNativeLisp = false; # optional; defaults to true on macOS
  };
}
```

`basecamp.emacs.package` exposes the selected package for compiling downstream
init files; `basecamp.emacs.warmProgram` exposes the macOS native Lisp warmer.
The module installs into the existing Home Manager profile and retires symlinks
from an earlier standalone install so they cannot shadow its selected build.
It never deploys or relocates init files. A downstream flake uses this module and adds
its own configuration and optimizations.

For testing an unpublished checkout, use `nix run path:.#emacs` (the `path:`
form includes new, untracked module files).

## Target user is a runtime parameter

The repo contains no personal usernames. The apps detect the invoking user
(`id -un`) at runtime and evaluate `lib.mkDarwin { user = ...; }` /
`lib.mkHome { user = ...; }` impurely, so the same command works for any
account on any machine. The pure `darwinConfigurations.fixture` /
`homeConfigurations.fixture` outputs exist only for CI and `nix flake check`.

Activation registers the built system closure directly
(`nix-env --profile /nix/var/nix/profiles/system --set` + `activate`), so
there is no PATH/sudo juggling.

## Layout

```
flake.nix                       # inputs + module apps (the CLI surface)
darwin/default.nix              # nix-darwin system config (homebrew casks, ...)
home/darwin.nix                 # home-manager (karabiner rule activation)
home/linux.nix                  # home-manager (linux)
home/karabiner/*.json           # Karabiner rules
lib/karabiner-upsert.nix        # shared jq upsert (app + home-manager activation)
```

## Local iteration

```sh
nix run .#plan
nix run .            # or: nix run .#darwin
```

## Notes

- `nix.enable = false` in nix-darwin: the Determinate installer owns the nix
  daemon and `/etc/nix/nix.conf`.
- Per-host module variation is supported via `lib.mkDarwin { modules = [...]; }`
  but not yet wired to any host detection.
