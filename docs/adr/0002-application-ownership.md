# ADR 0002: Applications belong to their own flakes

- Status: accepted
- Date: 2026-10-16
- Supersedes: [ADR 0001](0001-emacs-install-layers.md)
- Amended by: [ADR 0003](0003-application-inputs.md) (applications take upstream inputs)

## Context

ADR 0001 split Emacs into an install layer here (the binary, GUI/nox, native
compilation, the Emacs.app takeover and the built-in `.eln` warm-up) and a
runtime layer in a downstream flake. One editor then needed two flakes, and a
change to Emacs itself (a source patch, a build option) coupled their
releases.

## Decision

Emacs moves entirely to [emacs-camp](https://github.com/ajchemist/emacs-camp):
source selection, build options, patches, installation, the app takeover and
the native Lisp warm-up, next to its runtime configuration. The same holds for
any application: its build and configuration live in its own flake, which
builds on basecamp's `lib.mkDarwin` / `lib.mkHome`.

Removed without compatibility aliases: the `basecamp.emacs.*` options,
`darwinModules.emacs`, `homeModules.emacs`, `lib.emacsMajor`,
`lib.emacsPackage`, `lib.emacsWarm`, the builders' `emacs` argument, the setup
apps' `--emacs=` flag and the plan's `--no-emacs`.

## Consequences

- Basecamp keeps the system baseline only: nix-darwin and Home Manager,
  Homebrew, Karabiner, and the builders downstream flakes add modules to.
- A host whose saved choice (`~/.config/nix-basecamp/emacs`) is `gui` or `nox`
  loses basecamp's Emacs on its next switch. The setup apps print a notice
  while that file exists; the file is not read otherwise.
- Applications depend on basecamp, never the other way round, so there is no
  input cycle.
