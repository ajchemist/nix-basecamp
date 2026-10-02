# Home Manager side of basecamp's Emacs (docs/adr/0001).
# - Linux: installs it (nix-darwin does not exist there).
# - Under nix-darwin: installs nothing; every option mirrors the system's
#   basecamp.emacs read-only, so a downstream reads package/major/warmProgram
#   here on both OSes and sets enable/gui where the install happens.
# Never owns the user's init files.
{ lib, config, pkgs, osConfig ? null, ... }:
let
  cfg = config.basecamp.emacs;
  emacs = import ../../lib/emacs.nix { inherit lib; };
  from = if osConfig != null && osConfig ? basecamp.emacs then osConfig.basecamp.emacs else null;
in
{
  options.basecamp.emacs = emacs.options { inherit pkgs cfg from; };

  config = lib.mkIf (cfg.enable && from == null) {
    home.packages = [ cfg.package ];
  };
}
