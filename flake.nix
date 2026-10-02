{
  description = "nix-basecamp: one-command basecamp setup for any machine, including temporary ones";

  inputs = {
    # nixpkgs uses the GitHub tarball fetcher: a shallow git clone of nixpkgs
    # is hundreds of MB vs a ~40MB archive. The small inputs below stay on
    # git+https, which avoids GitHub's archive-API rate limits on shared IPs.
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "git+https://github.com/nix-darwin/nix-darwin.git?ref=master&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "git+https://github.com/nix-community/home-manager.git?ref=master&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nix-darwin, home-manager, ... }:
    let
      lib = nixpkgs.lib;
      emacs = import ./lib/emacs.nix { inherit lib; };

      ruleFile = ./home/karabiner/korean-left-modifiers.json;
      ruleDesc = (builtins.fromJSON (builtins.readFile ruleFile)).description;

      # The target user is a RUNTIME parameter: the apps detect the invoking
      # user (`id -un`) and evaluate these builders impurely, so this repo
      # contains no personal usernames. The `fixture` configurations below
      # exist only so CI and `nix flake check` have a pure, neutral instance.
      mkDarwin = { user, system ? "aarch64-darwin", modules ? [ ] }:
        nix-darwin.lib.darwinSystem {
          modules = [
            ./darwin/default.nix
            home-manager.darwinModules.home-manager
            {
              nixpkgs.hostPlatform = system;
              system.primaryUser = user;
              users.users.${user}.home = "/Users/${user}";
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.${user} = import ./home/darwin.nix;
            }
          ] ++ modules;
        };

      mkHome = { user, homeDirectory ? "/home/${user}", system ? "x86_64-linux", modules ? [ ] }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          modules = [
            ./home/linux.nix
            {
              home.username = user;
              home.homeDirectory = homeDirectory;
            }
          ] ++ modules;
        };

      mkApp = desc: drv: {
        type = "app";
        program = lib.getExe drv;
        meta.description = desc;
      };
    in
    {
      # Basecamp's Emacs contract for flakes that evaluate outside the module
      # (a downstream plan, the standalone app): the pinned major, the package,
      # the warmer. Same values as the module's read-only options.
      lib = {
        inherit mkDarwin mkHome;
        emacsMajor = emacs.major;
        emacsPackage = { system, gui ? false }:
          emacs.package { pkgs = nixpkgs.legacyPackages.${system}; inherit gui; };
        emacsWarm = { system }: emacs.warm nixpkgs.legacyPackages.${system};
      };
      homeModules.emacs = import ./home/emacs;

      darwinConfigurations.fixture = mkDarwin { user = "fixture"; };
      homeConfigurations.fixture = mkHome { user = "fixture"; };

      checks = lib.genAttrs [ "aarch64-darwin" "x86_64-linux" ] (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          fixture = extra: (home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [ self.homeModules.emacs {
              home.username = "fixture";
              home.homeDirectory = "/tmp/basecamp-fixture";
              home.stateVersion = "25.05";
            } extra ];
          }).config;
          disabled = fixture { };
          gui = fixture { basecamp.emacs = { enable = true; gui = true; }; };
          nox = fixture { basecamp.emacs = { enable = true; gui = false; }; };
          warm = emacs.warm pkgs;
        in {
          emacs-setup =
            assert !disabled.basecamp.emacs.enable;
            assert !(lib.elem pkgs.emacs disabled.home.packages);
            assert gui.basecamp.emacs.package == pkgs.${"emacs" + emacs.major};
            assert nox.basecamp.emacs.package == pkgs.${"emacs" + emacs.major + "-nox"};
            assert lib.versions.major gui.basecamp.emacs.package.version == emacs.major;
            assert lib.all (name: !(lib.hasPrefix "emacs/" name)) (builtins.attrNames gui.xdg.configFile);
            assert lib.all (name: !(lib.hasPrefix "emacs/" name)) (builtins.attrNames nox.xdg.configFile);
            assert !(gui.home.file ? ".emacs");
            assert !(gui.home.file ? ".emacs.d");
            pkgs.runCommand "emacs-setup-tests" {
              nativeBuildInputs = [ pkgs.python3 pkgs.bash pkgs.coreutils ];
              BASECAMP_WARM_REAL = "${warm}/bin/eln-warm-store";
              BASECAMP_HANDOVER = pkgs.writeShellScript "emacs-handover" (
                ''run() { "$@"; }
'' + gui.home.activation.basecampEmacsStandalone.data
              );
            } ''
              cp -r ${./ci} ci
              cp -r ${./lib} lib
              python3 ci/test-emacs-setup.py
              touch "$out"
            '';
        });

      # ------------------------------------------------------------------ macOS
      apps.aarch64-darwin =
        let
          pkgs = nixpkgs.legacyPackages.aarch64-darwin;
          nixBin = "${pkgs.nix}/bin";

          karabiner-rule = pkgs.writeShellApplication {
            name = "karabiner-rule";
            # SC2016: single-quoted jq programs intentionally contain $vars
            excludeShellChecks = [ "SC2016" ];
            text = import ./lib/karabiner-upsert.nix { inherit pkgs lib ruleFile; };
          };

          homebrew = pkgs.writeShellApplication {
            name = "homebrew";
            text = ''
              if command -v brew >/dev/null 2>&1; then
                echo "homebrew: already installed ($(brew --version | head -n1))"
                exit 0
              fi
              echo "homebrew: installing"
              NONINTERACTIVE=1 /bin/bash -c \
                "$(${pkgs.curl}/bin/curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            '';
          };

          darwin = pkgs.writeShellApplication {
            name = "darwin";
            text = ''
              user="$(id -un)"
              if ! printf '%s' "$user" | grep -Eq '^[A-Za-z_][A-Za-z0-9._-]*$'; then
                echo "darwin: unsupported username: $user" >&2
                exit 1
              fi

              echo "darwin: building system configuration for user $user"
              toplevel="$(${nixBin}/nix build --impure --no-link --print-out-paths \
                --extra-experimental-features "nix-command flakes" \
                --expr "((builtins.getFlake \"path:${self}\").lib.mkDarwin { user = \"$user\"; }).system")"

              current="$(readlink /run/current-system 2>/dev/null || true)"
              if [ "$current" = "$toplevel" ]; then
                echo "darwin: already up to date"
                exit 0
              fi

              # nix-darwin refuses to activate over these pre-existing files;
              # move them aside once (they are replaced by symlinks).
              for f in /etc/bashrc /etc/zshrc /etc/zshenv; do
                if [ -f "$f" ] && [ ! -L "$f" ]; then
                  echo "darwin: moving $f -> $f.before-nix-darwin"
                  sudo mv "$f" "$f.before-nix-darwin"
                fi
              done

              echo "darwin: activating $toplevel"
              sudo ${nixBin}/nix-env --profile /nix/var/nix/profiles/system --set "$toplevel"
              sudo "$toplevel/activate"
            '';
          };

          # Read-only status. Deliberately does NOT evaluate or build the
          # system closure, so `nix run .#plan` stays instant.
          plan = pkgs.writeShellApplication {
            name = "plan";
            text = ''
              row() { printf '  [%s] %-15s %-46s %s\n' "$@"; }
              echo ""
              echo "nix-basecamp · $(uname -s) ($(uname -m)) · target user: $(id -un)"
              echo ""
              if command -v brew >/dev/null 2>&1; then
                row "✓" homebrew "Homebrew package manager" "up to date"
              else
                row "•" homebrew "Homebrew package manager" "install"
              fi
              if [ -e /run/current-system ]; then
                row "✓" nix-darwin "system profile" "installed · converge on switch"
              else
                row "•" nix-darwin "system profile" "activate new generation"
              fi
              if [ -d /Applications/Karabiner-Elements.app ]; then
                row "✓" karabiner "Karabiner-Elements (homebrew cask)" "converge on switch"
              else
                row "•" karabiner "Karabiner-Elements (homebrew cask)" "via nix-darwin switch"
              fi
              if grep -qF ${lib.escapeShellArg ruleDesc} "$HOME/.config/karabiner/karabiner.json" 2>/dev/null; then
                row "✓" karabiner-rule "Korean-mode left modifiers -> karabiner.json" "converge on switch"
              else
                row "•" karabiner-rule "Korean-mode left modifiers -> karabiner.json" "via nix-darwin switch"
              fi
              echo ""
            '';
          };

          bootstrap = pkgs.writeShellApplication {
            name = "bootstrap";
            text = ''
              assume_yes=0
              dry_run=0
              for a in "$@"; do
                case "$a" in
                  -y|--yes) assume_yes=1 ;;
                  -n|--dry-run) dry_run=1 ;;
                  *) echo "unknown argument: $a" >&2; exit 1 ;;
                esac
              done

              ${lib.getExe plan}
              if [ "$dry_run" = 1 ]; then
                echo "(dry run — nothing was changed)"
                exit 0
              fi

              if [ "$assume_yes" != 1 ]; then
                if [ -r /dev/tty ]; then
                  printf 'Proceed? [y/N] ' > /dev/tty
                  read -r ans < /dev/tty || ans=""
                  case "$ans" in
                    y|Y|yes|YES) ;;
                    *) exit 1 ;;
                  esac
                else
                  echo "no terminal for confirmation; pass --yes" >&2
                  exit 1
                fi
              fi

              ${lib.getExe homebrew}
              ${lib.getExe darwin}
              # The darwin step exits early when the system closure is already
              # current, but state outside the nix store (karabiner.json) can
              # still have drifted — converge it unconditionally (idempotent).
              ${lib.getExe karabiner-rule}
              echo ""
              echo "result:"
              ${lib.getExe plan}
            '';
          };
        in
        {
          default = mkApp "Set up macOS with optional Emacs" (import ./lib/emacs-app.nix {
            inherit pkgs lib self plan;
            system = "aarch64-darwin";
            setup = bootstrap;
          });
          emacs = mkApp "Install optional Emacs without changing system or Home Manager profiles" (import ./lib/emacs-app.nix {
            inherit pkgs lib self;
            system = "aarch64-darwin";
          });
          plan = mkApp "Show module status (read-only)" plan;
          homebrew = mkApp "Install Homebrew if missing" homebrew;
          darwin = mkApp "Build and activate the nix-darwin system for the invoking user" darwin;
          karabiner-rule = mkApp "Upsert the Korean-mode left-modifier rule into karabiner.json" karabiner-rule;
        };

      # ------------------------------------------------------------------ Linux
      apps.x86_64-linux =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          home = pkgs.writeShellApplication {
            name = "home";
            text = ''
              user="$(id -un)"
              if ! printf '%s' "$user" | grep -Eq '^[A-Za-z_][A-Za-z0-9._-]*$'; then
                echo "home: unsupported username: $user" >&2
                exit 1
              fi

              echo "home: building home-manager configuration for $user ($HOME)"
              out="$(${pkgs.nix}/bin/nix build --impure --no-link --print-out-paths \
                --extra-experimental-features "nix-command flakes" \
                --expr "((builtins.getFlake \"path:${self}\").lib.mkHome { user = \"$user\"; homeDirectory = \"$HOME\"; }).activationPackage")"

              exec "$out/activate"
            '';
          };
        in
        {
          default = mkApp "Set up Linux with optional Emacs" (import ./lib/emacs-app.nix {
            inherit pkgs lib self;
            system = "x86_64-linux";
            setup = home;
          });
          emacs = mkApp "Install optional Emacs without changing Home Manager profiles" (import ./lib/emacs-app.nix {
            inherit pkgs lib self;
            system = "x86_64-linux";
          });
          home = mkApp "Build and activate the home-manager configuration for the invoking user" home;
        };
    };
}
