{ pkgs, lib, osConfig, ... }:

{
  home.stateVersion = "25.05";
  programs.home-manager.enable = true;

  # Off with the system's basecamp.karabiner.enable (darwin/karabiner.nix):
  # then karabiner.json is not touched at all.
  home.activation = lib.mkIf osConfig.basecamp.karabiner.enable {
    karabinerKoreanRule = lib.hm.dag.entryAfter [ "writeBoundary" ]
      (import ../lib/karabiner-upsert.nix {
        inherit pkgs lib;
        ruleFile = ./karabiner/korean-left-modifiers.json;
      });
  };
}
