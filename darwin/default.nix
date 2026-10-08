{ pkgs, ... }:

{
  # The Determinate Systems installer owns the nix daemon and /etc/nix/nix.conf;
  # letting nix-darwin manage nix as well would conflict.
  nix.enable = false;

  environment.systemPackages = with pkgs; [
    git
    jq
  ];

  # Casks come from the modules that want them (darwin/karabiner.nix).
  homebrew.enable = true;

  programs.zsh.enable = true;

  # Skip building manpages/options docs for the system: faster switches, and
  # avoids the options.json store-path-context warning with git-fetched flakes.
  documentation.enable = false;

  system.stateVersion = 6;
}
