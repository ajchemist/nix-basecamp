# Installation and OS integration only; never owns the user's init files.
{ lib, config, pkgs, ... }:
let
  cfg = config.basecamp.emacs;
  emacs = import ../../lib/emacs.nix { inherit lib; };
in
{
  options.basecamp.emacs = {
    enable = lib.mkEnableOption "the basecamp Emacs installation";
    gui = lib.mkOption {
      type = lib.types.bool;
      default = pkgs.stdenv.hostPlatform.isDarwin;
      description = "Use the GUI build instead of emacs-nox.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = emacs.package { inherit pkgs; inherit (cfg) gui; };
      description = "Emacs package; shared with downstream compilation.";
    };
    warmNativeLisp = lib.mkOption {
      type = lib.types.bool;
      default = pkgs.stdenv.hostPlatform.isDarwin;
      description = "Warm macOS's first-load checks for built-in native Lisp in the background.";
    };
    warmProgram = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = emacs.warmProgram pkgs;
      description = "Reusable native Lisp warmer for downstream config and packages.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
    # A previous standalone installation must not shadow this module's build.
    # Only links owned by the standalone app are removed; user files stay put.
    home.activation.basecampEmacsStandalone = lib.hm.dag.entryAfter [ "installPackages" ] ''
      profile="$HOME/.local/state/nix-basecamp/emacs/package"
      for bin in emacs emacsclient; do
        dest="$HOME/.local/bin/$bin"
        if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$profile/bin/$bin" ]; then
          run rm "$dest"
        fi
      done
      app="$HOME/Applications/Nix Basecamp Emacs.app"
      if [ -L "$app" ] && [ "$(readlink "$app")" = "$profile/Applications/Emacs.app" ]; then
        run rm "$app"
      fi
      if [ -L "$profile" ]; then run rm "$profile"; fi
    '';
    home.activation.emacsElnWarm = lib.mkIf (pkgs.stdenv.hostPlatform.isDarwin && cfg.warmNativeLisp)
      (lib.hm.dag.entryAfter [ "installPackages" ] (emacs.warmActivation {
        package = cfg.package;
        program = cfg.warmProgram;
      }));
  };
}
