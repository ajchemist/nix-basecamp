# Basecamp's Emacs contract (docs/adr/0001-emacs-install-layers.md), shared by
# the nix-darwin module (macOS), the Home Manager module (Linux; a read-only
# mirror on macOS) and downstream flakes (through `lib` and the modules'
# read-only options). Downstream follows these; it never names an emacs
# attribute, a warmer or a marker path of its own.
{ lib }:
rec {
  # The one knob. Inside a major every nixpkgs bump (31.1 -> 31.2, rebuilds)
  # is picked up with no edit here: the store path changes, the warm-up runs
  # again for it, nothing else is version-specific. When nixpkgs drops
  # emacs<major>, evaluation fails with nixpkgs' own message; that, or wanting
  # the next major, is the only reason to touch this file.
  major = "31";

  # nativeComp = false drops gcc and libgccjit (~430 MB of the closure) for
  # sandboxes and images; that build is not in the binary cache.
  package = { pkgs, gui ? false, nativeComp ? true }:
    let p = pkgs.${"emacs" + major + lib.optionalString (!gui) "-nox"};
    in if nativeComp then p else p.override { withNativeCompilation = false; };

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

  # The option set both modules declare. `from` is the system's
  # basecamp.emacs when the Home Manager module runs under nix-darwin: there
  # every option mirrors it read-only (the system installs, the user side only
  # reads), so a downstream sets enable/gui in exactly one place per OS.
  options = { pkgs, cfg, from ? null }:
    let
      ro = from != null;
      pick = name: fallback: if ro then from.${name} else fallback;
    in {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = pick "enable" false;
        readOnly = ro;
        description = "Install basecamp's Emacs (opt-in).";
      };
      gui = lib.mkOption {
        type = lib.types.bool;
        default = pick "gui" pkgs.stdenv.hostPlatform.isDarwin;
        readOnly = ro;
        description = "The GUI build instead of emacs-nox.";
      };
      nativeComp = lib.mkOption {
        type = lib.types.bool;
        default = pick "nativeComp" true;
        readOnly = ro;
        description = "Native Lisp compilation; false for a lighter Emacs (sandboxes, images).";
      };
      major = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        default = major;
        description = "The Emacs major basecamp pins; downstream follows it.";
      };
      package = lib.mkOption {
        type = lib.types.package;
        readOnly = true;
        default = pick "package" (package { inherit pkgs; inherit (cfg) gui nativeComp; });
        description = "The Emacs package (emacs<major> or emacs<major>-nox); downstream compiles against this one.";
      };
      warmProgram = lib.mkOption {
        type = lib.types.package;
        readOnly = true;
        default = pick "warmProgram" (warm pkgs);
        description = "macOS native Lisp warmer: bin/eln-warm DIR... and bin/eln-warm-store start|status EMACS.";
      };
    };

  # Nix's Emacs.app is the only one: when the GUI build is set up, other
  # bundles named Emacs.app in /Applications and ~/Applications are displaced.
  appTakeover = ./emacs-app-takeover.sh;
}
