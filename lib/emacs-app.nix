{ pkgs, lib, self, system, setup ? null, plan ? null }:
let
  emacs = import ./emacs.nix { inherit lib; };
in pkgs.writeShellApplication {
  name = if setup == null then "basecamp-emacs" else "basecamp-setup";
  runtimeInputs = [ pkgs.nix pkgs.coreutils ];
  text = ''
    BASECAMP_STANDALONE=${if setup == null then "1" else "0"}
    BASECAMP_DARWIN=${if pkgs.stdenv.hostPlatform.isDarwin then "1" else "0"}
    BASECAMP_SYSTEM=${lib.escapeShellArg system}
    BASECAMP_FLAKE=${lib.escapeShellArg "path:${self}"}
    BASECAMP_SETUP=${lib.escapeShellArg (if setup == null then "" else lib.getExe setup)}
    BASECAMP_PLAN=${lib.escapeShellArg (if plan == null then "" else lib.getExe plan)}
    BASECAMP_WARM=${emacs.warmProgram pkgs}
    ${builtins.readFile ./emacs-setup.sh}
  '';
}
