# macOS: basecamp brings Emacs into the system (docs/adr/0001). nix-darwin puts
# the package on the system PATH and copies Emacs.app into
# /Applications/Nix Apps. Everything in the user's home (init, packages,
# compiling them) is the downstream's, through Home Manager.
{ lib, config, pkgs, ... }:
let
  cfg = config.basecamp.emacs;
  emacs = import ../lib/emacs.nix { inherit lib; };
  user = config.system.primaryUser;
in
{
  options.basecamp.emacs = emacs.options { inherit pkgs cfg; } // {
    warmNativeLisp = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Warm macOS's first-load checks for the built-in native Lisp in the background.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    # Root activation; the per-user parts run as the primary user, as
    # nix-darwin's own homebrew step does (brew refuses root; the warm-up
    # marker lives in that user's ~/.cache).
    system.activationScripts.postActivation.text = lib.mkAfter (''
      echo "basecamp: Emacs ${cfg.package.version} (${if cfg.gui then "gui" else "nox"})" >&2
    '' + lib.optionalString cfg.gui ''
      HOME=~${user} BASECAMP_BREW_USER=${lib.escapeShellArg user} ${pkgs.bash}/bin/bash ${emacs.appTakeover}
    '' + lib.optionalString cfg.warmNativeLisp ''
      sudo --user=${lib.escapeShellArg user} --set-home -- ${cfg.warmProgram}/bin/eln-warm-store start ${cfg.package}
    '');
  };
}
