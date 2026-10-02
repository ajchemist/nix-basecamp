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
      # Emacs is opt-in per machine: emacs = "gui" | "nox" | "none" (the apps
      # pass the saved choice). One install path per OS (docs/adr/0001): the
      # nix-darwin module on macOS (Home Manager only mirrors it), the Home
      # Manager module on Linux. Only defaulted here, so a downstream that sets
      # basecamp.emacs.* itself wins without passing anything.
      emacsChoiceModule = mode: {
        basecamp.emacs.enable = lib.mkDefault (mode != "none");
        basecamp.emacs.gui = lib.mkDefault (mode == "gui");
      };

      mkDarwin = { user, system ? "aarch64-darwin", emacs ? "none", modules ? [ ] }:
        nix-darwin.lib.darwinSystem {
          modules = [
            ./darwin/default.nix
            ./darwin/emacs.nix
            (emacsChoiceModule emacs)
            home-manager.darwinModules.home-manager
            {
              nixpkgs.hostPlatform = system;
              system.primaryUser = user;
              users.users.${user}.home = "/Users/${user}";
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.${user}.imports = [ ./home/darwin.nix ./home/emacs ];
            }
          ] ++ modules;
        };

      mkHome = { user, homeDirectory ? "/home/${user}", system ? "x86_64-linux", emacs ? "none", modules ? [ ] }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          modules = [
            ./home/linux.nix
            ./home/emacs
            (emacsChoiceModule emacs)
            {
              home.username = user;
              home.homeDirectory = homeDirectory;
            }
          ] ++ modules;
        };

      # The Emacs choice for the setup apps: --emacs=gui|nox|none, else the
      # saved one, else asked once on a terminal (default none). Saved only
      # after a successful switch, so --yes never opts in and a failed build
      # records nothing. Expects $assume_yes/$dry_run; sets $emacs, $emacs_new.
      emacsChoice = ''
        choice="$HOME/.config/nix-basecamp/emacs"
        emacs="" emacs_new=0
        for a in "$@"; do
          case "$a" in
            --emacs=gui|--emacs=nox|--emacs=none) emacs="''${a#--emacs=}" emacs_new=1 ;;
            --emacs=*) echo "expected --emacs=gui|nox|none" >&2; exit 1 ;;
          esac
        done
        if [ -z "$emacs" ] && [ -f "$choice" ]; then
          emacs="$(cat "$choice")"
          case "$emacs" in gui|nox|none) ;; *) echo "invalid Emacs choice in $choice" >&2; exit 1 ;; esac
        fi
        if [ -z "$emacs" ] && [ "$dry_run" = 0 ] && [ "$assume_yes" = 0 ] && ( : </dev/tty ) 2>/dev/null; then
          printf 'Optional Emacs: gui / nox / none [none]: ' >/dev/tty
          read -r emacs </dev/tty || emacs=""
          emacs="''${emacs:-none}"
          case "$emacs" in gui|nox|none) emacs_new=1 ;; *) echo "expected gui, nox or none" >&2; exit 1 ;; esac
        fi
        emacs="''${emacs:-none}"
      '';
      emacsSave = ''
        if [ "$emacs_new" = 1 ]; then
          mkdir -p "''${choice%/*}"
          printf '%s\n' "$emacs" >"$choice.tmp" && mv "$choice.tmp" "$choice"
        fi
      '';
      emacsPlanRow = layer: ''
        e="$(cat "$HOME/.config/nix-basecamp/emacs" 2>/dev/null || true)"
        case "$e" in
          gui|nox) row "✓" emacs "Emacs ${emacs.major} ($e, ${layer})" "converge on switch" ;;
          none) row "✓" emacs "Emacs (opt-in)" "off · --emacs=gui|nox to enable" ;;
          *) row "•" emacs "Emacs (opt-in)" "undecided · asked on setup, or --emacs=gui|nox|none" ;;
        esac
      '';
      # For the single-step apps (#darwin, #home): the env from the setup app,
      # else the saved choice, else none.
      emacsSaved = ''
        emacs="''${BASECAMP_EMACS:-$(cat "$HOME/.config/nix-basecamp/emacs" 2>/dev/null || echo none)}"
        case "$emacs" in gui|nox|none) ;; *) echo "invalid Emacs choice: $emacs" >&2; exit 1 ;; esac
      '';

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
      # Paths, not imported functions: the builders above import them too, and
      # the module system dedups a path imported twice.
      darwinModules.emacs = ./darwin/emacs.nix;
      homeModules.emacs = ./home/emacs;

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
          # macOS: the system installs, Home Manager mirrors read-only and
          # installs nothing; a downstream's own setting wins over the choice.
          darwinOf = args: (mkDarwin ({ user = "fixture"; } // args)).config;
          chosen = darwinOf { emacs = "gui"; };
          chosenHm = chosen.home-manager.users.fixture;
          off = darwinOf { };
          downstream = darwinOf { emacs = "gui"; modules = [ { basecamp.emacs = { enable = true; gui = false; }; } ]; };
          isEmacs = p: (p.pname or "") == "emacs";
          # Linux builder: the choice reaches the Home Manager module.
          linuxChosen = (mkHome { user = "fixture"; emacs = "nox"; }).config.basecamp.emacs;
        in {
          emacs =
            assert chosen.basecamp.emacs.enable && chosen.basecamp.emacs.gui;
            assert lib.any isEmacs chosen.environment.systemPackages;
            assert lib.hasInfix "emacs-app-takeover" chosen.system.activationScripts.postActivation.text;
            assert lib.hasInfix "eln-warm-store start" chosen.system.activationScripts.postActivation.text;
            assert chosenHm.basecamp.emacs.package == chosen.basecamp.emacs.package;
            assert !(lib.any isEmacs chosenHm.home.packages);
            assert !off.basecamp.emacs.enable && !(lib.any isEmacs off.environment.systemPackages);
            assert downstream.basecamp.emacs.enable && !downstream.basecamp.emacs.gui;
            assert !(lib.hasInfix "emacs-app-takeover" downstream.system.activationScripts.postActivation.text);
            assert linuxChosen.enable && !linuxChosen.gui;
            assert !disabled.basecamp.emacs.enable;
            assert !(lib.elem pkgs.emacs disabled.home.packages);
            assert gui.basecamp.emacs.package == pkgs.${"emacs" + emacs.major};
            assert nox.basecamp.emacs.package == pkgs.${"emacs" + emacs.major + "-nox"};
            assert lib.versions.major gui.basecamp.emacs.package.version == emacs.major;
            assert lib.all (name: !(lib.hasPrefix "emacs/" name)) (builtins.attrNames gui.xdg.configFile);
            assert lib.all (name: !(lib.hasPrefix "emacs/" name)) (builtins.attrNames nox.xdg.configFile);
            assert !(gui.home.file ? ".emacs");
            assert !(gui.home.file ? ".emacs.d");
            pkgs.runCommand "emacs-tests" {
              nativeBuildInputs = [ pkgs.python3 pkgs.bash pkgs.coreutils ];
              BASECAMP_WARM = "${warm}/bin/eln-warm-store";
            } ''
              cp -r ${./ci} ci
              cp -r ${./lib} lib
              python3 ci/test-emacs.py
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

              ${emacsSaved}
              echo "darwin: building system configuration for user $user (emacs: $emacs)"
              toplevel="$(${nixBin}/nix build --impure --no-link --print-out-paths \
                --extra-experimental-features "nix-command flakes" \
                --expr "((builtins.getFlake \"path:${self}\").lib.mkDarwin { user = \"$user\"; emacs = \"$emacs\"; }).system")"

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
          # --no-emacs: for a downstream flake that sets basecamp.emacs itself
          # (the row shows the setup app's choice, which it does not use).
          plan = pkgs.writeShellApplication {
            name = "plan";
            text = ''
              no_emacs=0
              for a in "$@"; do [ "$a" = --no-emacs ] && no_emacs=1; done
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
              if [ "$no_emacs" = 0 ]; then
                ${emacsPlanRow "nix-darwin, /Applications/Nix Apps"}
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
                  --emacs=*) ;;
                  *) echo "unknown argument: $a" >&2; exit 1 ;;
                esac
              done
              ${emacsChoice}

              ${lib.getExe plan}
              echo "emacs for this run: $emacs"
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
              BASECAMP_EMACS="$emacs" ${lib.getExe darwin}
              ${emacsSave}
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
          default = mkApp "Plan, confirm, and apply the macOS setup (Emacs optional: --emacs=gui|nox|none)" bootstrap;
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

              ${emacsSaved}
              echo "home: building home-manager configuration for $user ($HOME, emacs: $emacs)"
              out="$(${pkgs.nix}/bin/nix build --impure --no-link --print-out-paths \
                --extra-experimental-features "nix-command flakes" \
                --expr "((builtins.getFlake \"path:${self}\").lib.mkHome { user = \"$user\"; homeDirectory = \"$HOME\"; emacs = \"$emacs\"; }).activationPackage")"

              "$out/activate"
            '';
          };

          setup = pkgs.writeShellApplication {
            name = "setup";
            text = ''
              assume_yes=0
              dry_run=0
              for a in "$@"; do
                case "$a" in
                  -y|--yes) assume_yes=1 ;;
                  -n|--dry-run) dry_run=1 ;;
                  --emacs=*) ;;
                  *) echo "unknown argument: $a" >&2; exit 1 ;;
                esac
              done
              ${emacsChoice}
              row() { printf '  [%s] %-15s %-46s %s\n' "$@"; }
              echo ""
              echo "nix-basecamp · $(uname -s) ($(uname -m)) · target user: $(id -un)"
              echo ""
              row "•" home-manager "standalone home-manager" "activate new generation"
              ${emacsPlanRow "home-manager"}
              echo "emacs for this run: $emacs"
              if [ "$dry_run" = 1 ]; then
                echo "(dry run — nothing was changed)"
                exit 0
              fi
              if [ "$assume_yes" != 1 ]; then
                if ( : </dev/tty ) 2>/dev/null; then
                  printf 'Proceed? [y/N] ' >/dev/tty
                  read -r ans </dev/tty || ans=""
                  case "$ans" in y|Y|yes|YES) ;; *) exit 1 ;; esac
                else
                  echo "no terminal for confirmation; pass --yes" >&2
                  exit 1
                fi
              fi
              BASECAMP_EMACS="$emacs" ${lib.getExe home}
              ${emacsSave}
            '';
          };
        in
        {
          default = mkApp "Plan, confirm, and apply the Linux setup (Emacs optional: --emacs=gui|nox|none)" setup;
          home = mkApp "Build and activate the home-manager configuration for the invoking user" home;
        };
    };
}
