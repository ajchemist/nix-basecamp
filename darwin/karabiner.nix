# macOS: Karabiner-Elements and basecamp's complex-modification rule. On by
# default; basecamp.karabiner.enable = false drops the cask and the rule
# upsert (home/darwin.nix reads this option). Turning it off only stops
# managing Karabiner: nix-darwin's homebrew cleanup stays at its default
# ("none"), so an installed Karabiner-Elements and karabiner.json are left
# as they are.
{ lib, config, ... }:
{
  options.basecamp.karabiner.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Install Karabiner-Elements (Homebrew cask) and upsert basecamp's rule into karabiner.json.";
  };

  config = lib.mkIf config.basecamp.karabiner.enable {
    homebrew.casks = [ "karabiner-elements" ];
  };
}
