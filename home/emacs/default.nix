# Installation and OS integration only; never owns the user's init files.
# Everything downstream needs is a read-only option here: the package (major
# pinned in lib/emacs.nix) and the warmer. Downstream sets enable/gui only.
{ lib, config, pkgs, ... }:
let
  cfg = config.basecamp.emacs;
  emacs = import ../../lib/emacs.nix { inherit lib; };
  darwin = pkgs.stdenv.hostPlatform.isDarwin;
in
{
  options.basecamp.emacs = {
    enable = lib.mkEnableOption "the basecamp Emacs installation";
    gui = lib.mkOption {
      type = lib.types.bool;
      default = darwin;
      description = "Use the GUI build instead of emacs-nox.";
    };
    major = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = emacs.major;
      description = "Emacs major version basecamp pins; downstream follows it.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = emacs.package { inherit pkgs; inherit (cfg) gui; };
      description = "The Emacs package (emacs<major> or emacs<major>-nox); downstream compiles against this one.";
    };
    warmNativeLisp = lib.mkOption {
      type = lib.types.bool;
      default = darwin;
      description = "Warm macOS's first-load checks for the built-in native Lisp in the background.";
    };
    warmProgram = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = emacs.warm pkgs;
      description = ''
        macOS native Lisp warmer: bin/eln-warm DIR... (foreground, any .eln
        downstream produces) and bin/eln-warm-store start|status EMACS.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
    # Ours lives in ~/Applications/Home Manager Apps; every other Emacs.app goes.
    home.activation.basecampEmacsApp = lib.mkIf (darwin && cfg.gui)
      (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${pkgs.bash}/bin/bash ${emacs.appTakeover}
      '');
    home.activation.emacsElnWarm = lib.mkIf (darwin && cfg.warmNativeLisp)
      (lib.hm.dag.entryAfter [ "installPackages" ] ''
        run ${cfg.warmProgram}/bin/eln-warm-store start ${cfg.package}
      '');
  };
}
