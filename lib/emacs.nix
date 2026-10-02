# Basecamp's Emacs contract, shared by the standalone app, the Home Manager
# module and downstream flakes (through `lib` and the module's read-only
# options). Downstream follows these; it never names an emacs attribute, a
# warmer or a marker path of its own.
{ lib }:
rec {
  # The one knob. Inside a major every nixpkgs bump (31.1 -> 31.2, rebuilds)
  # is picked up with no edit here: the store path changes, the warm-up runs
  # again for it, nothing else is version-specific. When nixpkgs drops
  # emacs<major>, evaluation fails with nixpkgs' own message; that, or wanting
  # the next major, is the only reason to touch this file.
  major = "31";

  package = { pkgs, gui ? false }:
    pkgs.${"emacs" + major + lib.optionalString (!gui) "-nox"};

  # macOS vets every Mach-O on its first dlopen (~0.3s each, serialised in
  # syspolicyd, then cached per file): the AOT eln in the store make that a
  # stall on the first use of each built-in feature. A C program (libSystem
  # only, no interpreter on the host) pays it ahead.
  #   bin/eln-warm DIR...                dlopen every .eln below DIR, foreground
  #   bin/eln-warm-store start EMACS     once per Emacs store path, background
  #   bin/eln-warm-store status EMACS    done | running <pid> | pending
  warm = pkgs: pkgs.runCommandCC "basecamp-eln-warm" { } ''
    mkdir -p $out/bin
    $CC -O2 -o $out/bin/eln-warm ${./eln-warm.c}
    substitute ${./eln-warm-store.sh} $out/bin/eln-warm-store \
      --replace-fail "#!/bin/sh" "#!${pkgs.runtimeShell}" \
      --replace-fail @shell@ ${pkgs.runtimeShell} \
      --replace-fail @eln_warm@ $out/bin/eln-warm
    chmod +x $out/bin/eln-warm-store
  '';

  # Nix's Emacs.app is the only one: when the GUI build is set up, other
  # bundles named Emacs.app in /Applications and ~/Applications are displaced.
  appTakeover = ./emacs-app-takeover.sh;
}
