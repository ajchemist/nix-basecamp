# ADR 0001: Emacs install layers

- Status: accepted
- Date: 2026-10-02

## Context

Basecamp brings Emacs onto a machine; a downstream flake adds a
personal configuration on top. Until now basecamp had two install paths for
the same binary: a standalone app (its own GC root, `~/.local/bin` links,
`~/Applications` link) and a Home Manager module. That meant two ways to get
Emacs on one machine, two places for `Emacs.app`, and code to hand one over to
the other. The setup already activates nix-darwin (macOS, with sudo) and Home
Manager (both OSes), so a separate path bought nothing.

Two concerns are macOS-only: warming the first-`dlopen` check of the ~3000
built-in `.eln` files (macOS vets every Mach-O once, ~0.3 s each, serialised),
and making nix's `Emacs.app` the only one. Linux has neither.

## Decision

1. **Responsibility split.** Basecamp brings Emacs into the *system*: the
   binary, `Emacs.app`, the built-in native Lisp warm-up, displacing other
   `Emacs.app` bundles. The downstream owns the *home*: init files, compiling
   them, packages. Basecamp never touches `~/.emacs`, `~/.emacs.d` or
   `~/.config/emacs`.
2. **One install path per OS.**
   - macOS: the nix-darwin module (`darwin/emacs.nix`). The package is a
     system package; nix-darwin copies `Emacs.app` into
     `/Applications/Nix Apps` (a real copy, so Spotlight finds it).
   - Linux: the Home Manager module (`home/emacs`), since there is no
     nix-darwin.
   - Under nix-darwin the Home Manager module installs nothing and mirrors the
     system's options read-only, so a downstream reads the same options on
     both OSes and sets `enable`/`gui` only where the install happens.
3. **No standalone install.** Removed, with its GC root, links and handover.
4. **Version.** Basecamp pins the Emacs major in `lib/emacs.nix`
   (`emacs31`/`emacs31-nox`). Inside a major nothing in basecamp changes;
   only a new major, or nixpkgs dropping the pinned one, edits that file.
   Downstream never names an `emacs*` attribute and follows basecamp's lock.
5. **macOS-only work runs in nix-darwin's activation**, the per-user parts as
   `system.primaryUser` (as nix-darwin's homebrew step does): Homebrew casks
   that install an `Emacs.app` are uninstalled through brew (brew refuses
   root); any other `Emacs.app` in `/Applications` or `~/Applications` is
   moved to `Emacs.app.before-basecamp`; the warm-up runs once per Emacs store
   path in the background. The warmer is a small C program (libSystem only):
   no perl or python is required on the host.
6. **Opt-in.** `gui`, `nox` or `none` (installs nothing; also the default
   when undecided), chosen once by the setup app and saved.

## Contract for downstream

Read-only: `basecamp.emacs.major`, `.package`, `.warmProgram` (both modules),
`lib.emacsMajor`, `lib.emacsPackage`, `lib.emacsWarm`. Settable:
`basecamp.emacs.enable`, `.gui` (nix-darwin config on macOS, Home Manager on
Linux). `apps.<system>.plan --no-emacs` embeds basecamp's plan without its
Emacs row.

## Consequences

- Emacs on macOS changes with `#darwin` (sudo), not with a Home Manager-only
  switch.
- Downstream home work (init compile, warming its own `.eln` with
  `warmProgram`'s `bin/eln-warm`) stays in Home Manager on both OSes.
- Adding Linux-specific behaviour later touches only the Home Manager module;
  macOS-specific behaviour only the nix-darwin module.
