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

Emacs is **off by default** and installed through Home Manager like the rest
of the setup (one way, both OSes: the user profile, and on macOS
`~/Applications/Home Manager Apps/Emacs.app`). The setup command asks once on a
terminal for `gui`, `nox` (terminal only) or `none`; the answer is saved in
`~/.config/nix-basecamp/emacs` after a successful switch and reused afterwards.

```sh
nix run github:ajchemist/nix-basecamp -- --emacs=gui      # or nox / none
nix run github:ajchemist/nix-basecamp -- --dry-run        # shows the choice, changes nothing
```

`--yes` skips confirmation; it does not opt you into an undecided Emacs (it
stays `none` and is asked again on the next interactive run). `#darwin` and
Linux `#home` use the saved choice.

A GUI setup makes nix's `Emacs.app` the only one: Homebrew casks that install
an `Emacs.app` (`emacs`, `emacs-app`, `emacs-mac`) are uninstalled through brew,
and any other `Emacs.app` in `/Applications` or `~/Applications` is moved to
`Emacs.app.before-basecamp` (never deleted). A `nox` setup leaves them alone.
Basecamp provides no init, theme, keybindings, or package archive policy, and
never touches `~/.emacs`, `~/.emacs.d` or `~/.config/emacs`.

### Native Lisp warm-up (macOS)

macOS vets every Mach-O the first time it is `dlopen`ed (~0.3 s per file,
serialised, then cached per file). Emacs ships ~3000 ahead-of-time compiled
`.eln` files, so without help the first use of each built-in feature stalls.
Basecamp pays this once per Emacs store path, in the background (~15 min, no
CPU; Emacs is usable meanwhile), with a small C program (libSystem only; no
perl or python on the host). A second run while one is going is a no-op; a run
cut short by a reboot restarts on the next setup.

### Version policy

Basecamp pins the Emacs **major** (`lib/emacs.nix`, currently 31:
`emacs31` / `emacs31-nox`). Inside a major, nixpkgs updates flow through with
no change here. Basecamp's Emacs code changes only to move to the next major,
or when nixpkgs drops the pinned one (evaluation then fails with nixpkgs' own
message).

### Contract for downstream flakes

Downstream Home Manager configurations import the module and set only
`enable` and `gui`; everything else is read-only and must be used as given:

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

| Provided | What downstream does with it |
|---|---|
| `basecamp.emacs.major` (read-only) | Labels; never pins its own Emacs. |
| `basecamp.emacs.package` (read-only) | The only Emacs: compile init files against it, never name an `emacs*` attribute. |
| `basecamp.emacs.warmProgram` (read-only) | `bin/eln-warm DIR...` for any `.eln` it produces (init files, packages); `bin/eln-warm-store status EMACS` for status. |
| `lib.emacsMajor`, `lib.emacsPackage { system; gui; }`, `lib.emacsWarm { system; }` | The same values for code evaluated outside the module (a status command). |
| `apps.<system>.plan` with `--no-emacs` | Embedding basecamp's plan without its Emacs row, which shows the setup app's choice rather than the downstream's settings. |

`lib.mkDarwin`/`lib.mkHome` already import the module (`emacs = "gui" | "nox" |
"none"` sets its defaults); a downstream flake that imports it again is
deduplicated, and its own `enable`/`gui` win over those defaults. The module
never deploys or relocates init files. A downstream flake uses this module and adds
its own configuration on top.

For testing an unpublished checkout, use `nix run path:.` (the `path:` form
includes new, untracked files).

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
home/emacs/default.nix          # opt-in Emacs module (both OSes)
lib/emacs.nix                   # Emacs contract: major, package, warmer, app takeover
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
