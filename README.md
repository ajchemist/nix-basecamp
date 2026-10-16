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
nix run github:ajchemist/nix-basecamp#karabiner-rule   # just the karabiner rule (no-op when Karabiner is off)
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
  Karabiner is on by default and can be turned off (below).
- **Linux** (x86_64): standalone home-manager.

## Karabiner (macOS, on by default)

Karabiner-Elements and its rule are managed unless you turn them off:

```sh
nix run github:ajchemist/nix-basecamp -- --karabiner=off   # or =on
nix run github:ajchemist/nix-basecamp -- --dry-run --karabiner=off
```

Off means basecamp does not install the cask, never runs the rule upsert, and
never touches `karabiner.json`; the plan shows both Karabiner rows as `off`.
The choice is saved in `~/.config/nix-basecamp/karabiner` after a successful
switch and reused by later runs, `#darwin` and `#karabiner-rule`. It is never
asked, and `--yes` never changes it.

Turning it off only stops managing Karabiner: an already installed
Karabiner-Elements stays installed (nix-darwin's Homebrew cleanup is left at
its default, `none`) and an existing `karabiner.json`, including basecamp's
rule, is left as it is. Remove them by hand (`brew uninstall --cask
karabiner-elements`) if you want them gone.

## Emacs moved to emacs-camp

Basecamp no longer installs Emacs ([ADR 0002](docs/adr/0002-application-ownership.md)).
[emacs-camp](https://github.com/ajchemist/emacs-camp) builds and installs it
on top of these builders, along with its configuration. If an older basecamp
saved an Emacs choice (`~/.config/nix-basecamp/emacs` is `gui` or `nox`), the
setup prints a notice: the next switch removes the Emacs basecamp installed.
Delete the file once Emacs comes from emacs-camp.

## Contract for downstream flakes

Applications (such as emacs-camp) and personal setups build on these.
Changing one is a breaking change, recorded in an ADR.

| Provided | What downstream does with it |
|---|---|
| `lib.mkDarwin { user; system ? "aarch64-darwin"; karabiner ? "on"; modules ? []; }` | A nix-darwin system with Home Manager for `user`; application modules go in `modules`. |
| `lib.mkHome { user; homeDirectory ? "/home/${user}"; system ? "x86_64-linux"; modules ? []; }` | A standalone Home Manager configuration (Linux). |
| `basecamp.karabiner.enable` (nix-darwin, default `true`) | Set `false` to drop the Karabiner-Elements cask and the rule upsert; Karabiner is then left unmanaged, not uninstalled. `mkDarwin`'s `karabiner = "off"` only sets the default, so a downstream's own setting wins. |
| `apps.aarch64-darwin.plan --no-karabiner` | Embeds basecamp's plan without its Karabiner rows, for a downstream that sets `basecamp.karabiner.enable` itself. |

## Target user is a runtime parameter

The repo contains no personal usernames. The apps detect the invoking user
(`id -un`) at runtime and evaluate `lib.mkDarwin { user = ...; }` /
`lib.mkHome { user = ...; }` impurely, so the same command works for any
account on any machine. The pure `darwinConfigurations.fixture` (and `fixture-no-karabiner`) /
`homeConfigurations.fixture` outputs exist only for CI and `nix flake check`.

Activation registers the built system closure directly
(`nix-env --profile /nix/var/nix/profiles/system --set` + `activate`), so
there is no PATH/sudo juggling.

## Layout

```
flake.nix                       # inputs + module apps (the CLI surface)
darwin/default.nix              # nix-darwin system config (homebrew, ...)
darwin/karabiner.nix            # basecamp.karabiner.enable: cask + rule (on by default)
home/darwin.nix                 # home-manager (karabiner rule activation, if enabled)
home/linux.nix                  # home-manager (linux)
docs/adr/                       # design decisions
home/karabiner/*.json           # Karabiner rules
lib/karabiner-upsert.nix        # shared jq upsert (app + home-manager activation)
ci/                             # CI test and assertion scripts
.github/workflows/ci.yml        # lint | test -> build -> e2e, path-filtered
```

## Local iteration

```sh
nix run .#plan
nix run .            # or: nix run .#darwin
```

`nix run path:.` includes new, untracked files; a downstream tries an
unpublished checkout with `--override-input basecamp path:../nix-basecamp`.

## Notes

- `nix.enable = false` in nix-darwin: the Determinate installer owns the nix
  daemon and `/etc/nix/nix.conf`.
- Per-host module variation is supported via `lib.mkDarwin { modules = [...]; }`
  but not yet wired to any host detection.
