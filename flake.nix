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

      ruleFile = ./home/karabiner/korean-left-modifiers.json;
      ruleDesc = (builtins.fromJSON (builtins.readFile ruleFile)).description;

      # The target user is a RUNTIME parameter: the apps detect the invoking
      # user (`id -un`) and evaluate these builders impurely, so this repo
      # contains no personal usernames. The `fixture` configurations below
      # exist only so CI and `nix flake check` have a pure, neutral instance.
      # Karabiner is on by default: karabiner = "on" | "off" (the apps pass
      # the saved choice). Only defaulted, so a downstream's own
      # basecamp.karabiner.enable wins.
      karabinerChoiceModule = mode: {
        basecamp.karabiner.enable = lib.mkDefault (mode != "off");
      };

      mkDarwin = { user, system ? "aarch64-darwin", karabiner ? "on", modules ? [ ] }:
        nix-darwin.lib.darwinSystem {
          modules = [
            ./darwin/default.nix
            ./darwin/karabiner.nix
            (karabinerChoiceModule karabiner)
            home-manager.darwinModules.home-manager
            {
              nixpkgs.hostPlatform = system;
              system.primaryUser = user;
              users.users.${user}.home = "/Users/${user}";
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.${user}.imports = [ ./home/darwin.nix ];
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

      # The Karabiner choice (macOS): --karabiner=on|off in the setup app, else
      # BASECAMP_KARABINER (the setup app exports it for its steps), else the
      # saved one, else on. Never asked: it is on unless turned off. Saved
      # only after a successful switch and only when given on the command
      # line, so --yes never changes it.
      karabinerSaved = ''
        kchoice="$HOME/.config/nix-basecamp/karabiner"
        karabiner="''${BASECAMP_KARABINER:-$(cat "$kchoice" 2>/dev/null || echo on)}"
        case "$karabiner" in on|off) ;; *) echo "invalid Karabiner choice: $karabiner" >&2; exit 1 ;; esac
      '';
      karabinerChoice = karabinerSaved + ''
        karabiner_new=0
        for a in "$@"; do
          case "$a" in
            --karabiner=on|--karabiner=off) karabiner="''${a#--karabiner=}" karabiner_new=1 ;;
            --karabiner=*) echo "expected --karabiner=on|off" >&2; exit 1 ;;
          esac
        done
        export BASECAMP_KARABINER="$karabiner"
      '';
      karabinerSave = ''
        if [ "$karabiner_new" = 1 ]; then
          mkdir -p "''${kchoice%/*}"
          printf '%s\n' "$karabiner" >"$kchoice.tmp" && mv "$kchoice.tmp" "$kchoice"
        fi
      '';

      # Emacs moved to emacs-camp (docs/adr/0002). A gui/nox choice saved by an
      # older basecamp no longer installs anything, and the next switch drops
      # the Emacs it installed: say so rather than remove it silently.
      emacsMoved = ''
        case "$(cat "$HOME/.config/nix-basecamp/emacs" 2>/dev/null || true)" in
          gui|nox)
            echo "note: basecamp no longer installs Emacs (docs/adr/0002); this switch removes the one it installed." >&2
            echo "      Install it with github:ajchemist/emacs-camp, then delete ~/.config/nix-basecamp/emacs." >&2 ;;
        esac
      '';

      mkApp = desc: drv: {
        type = "app";
        program = lib.getExe drv;
        meta.description = desc;
      };
    in
    {
      lib = { inherit mkDarwin mkHome; };

      darwinConfigurations.fixture = mkDarwin { user = "fixture"; };
      darwinConfigurations.fixture-no-karabiner = mkDarwin { user = "fixture"; karabiner = "off"; };
      homeConfigurations.fixture = mkHome { user = "fixture"; };

      checks = lib.genAttrs [ "aarch64-darwin" "x86_64-linux" ] (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          darwinOf = args: (mkDarwin ({ user = "fixture"; } // args)).config;
          kDefault = darwinOf { };
          kOff = darwinOf { karabiner = "off"; };
          kDownstream = darwinOf { modules = [ { basecamp.karabiner.enable = false; } ]; };
          kDownstreamOn = darwinOf { karabiner = "off"; modules = [ { basecamp.karabiner.enable = true; } ]; };
          casks = c: map (k: k.name) c.homebrew.casks;
          hmSteps = c: lib.concatMapStrings (e: e.data) (builtins.attrValues c.home-manager.users.fixture.home.activation);
          systemSteps = c: lib.concatMapStrings (e: e.text or "") (builtins.attrValues c.system.activationScripts);
          managesKarabiner = c:
            lib.elem "karabiner-elements" (casks c)
            && c.home-manager.users.fixture.home.activation ? karabinerKoreanRule
            && lib.hasInfix "karabiner.json" (hmSteps c);
          leavesKarabiner = c:
            !(lib.elem "karabiner-elements" (casks c))
            && !(lib.hasInfix "karabiner" (hmSteps c))
            && !(lib.hasInfix "karabiner" (systemSteps c))
            && !(lib.hasInfix "karabiner" c.homebrew.brewfile);
        in {
          karabiner =
            assert kDefault.basecamp.karabiner.enable && managesKarabiner kDefault;
            assert lib.hasInfix "karabiner-elements" kDefault.homebrew.brewfile;
            assert !kOff.basecamp.karabiner.enable && leavesKarabiner kOff;
            assert !kDownstream.basecamp.karabiner.enable && leavesKarabiner kDownstream;
            assert kDownstreamOn.basecamp.karabiner.enable && managesKarabiner kDownstreamOn;
            pkgs.runCommand "karabiner-checks" { } "touch $out";

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
            # Respects the Karabiner choice: off leaves karabiner.json alone.
            text = karabinerSaved + ''
              if [ "$karabiner" = off ]; then
                echo "karabiner-rule: Karabiner is off (--karabiner=on to manage it); karabiner.json left alone"
                exit 0
              fi
            '' + import ./lib/karabiner-upsert.nix { inherit pkgs lib ruleFile; };
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

              ${karabinerSaved}
              echo "darwin: building system configuration for user $user (karabiner: $karabiner)"
              toplevel="$(${nixBin}/nix build --impure --no-link --print-out-paths \
                --extra-experimental-features "nix-command flakes" \
                --expr "((builtins.getFlake \"path:${self}\").lib.mkDarwin { user = \"$user\"; karabiner = \"$karabiner\"; }).system")"

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
              no_karabiner=0
              for a in "$@"; do
                case "$a" in
                  --no-karabiner) no_karabiner=1 ;;
                esac
              done
              ${karabinerSaved}
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
              if [ "$no_karabiner" = 1 ]; then
                :
              elif [ "$karabiner" = off ]; then
                row "✓" karabiner "Karabiner-Elements (homebrew cask)" "off · not managed · --karabiner=on to enable"
                row "✓" karabiner-rule "Korean-mode left modifiers -> karabiner.json" "off · karabiner.json left alone"
              else
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
                  --karabiner=*) ;;
                  *) echo "unknown argument: $a" >&2; exit 1 ;;
                esac
              done
              ${karabinerChoice}

              ${lib.getExe plan}
              echo "karabiner for this run: $karabiner"
              ${emacsMoved}
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
              ${karabinerSave}
              # The darwin step exits early when the system closure is already
              # current, but state outside the nix store (karabiner.json) can
              # still have drifted — converge it unconditionally (idempotent;
              # a no-op when Karabiner is off).
              ${lib.getExe karabiner-rule}
              echo ""
              echo "result:"
              ${lib.getExe plan}
            '';
          };
        in
        {
          default = mkApp "Plan, confirm, and apply the macOS setup (Karabiner: --karabiner=on|off)" bootstrap;
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
                  *) echo "unknown argument: $a" >&2; exit 1 ;;
                esac
              done
              row() { printf '  [%s] %-15s %-46s %s\n' "$@"; }
              echo ""
              echo "nix-basecamp · $(uname -s) ($(uname -m)) · target user: $(id -un)"
              echo ""
              row "•" home-manager "standalone home-manager" "activate new generation"
              ${emacsMoved}
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
              ${lib.getExe home}
            '';
          };
        in
        {
          default = mkApp "Plan, confirm, and apply the Linux setup" setup;
          home = mkApp "Build and activate the home-manager configuration for the invoking user" home;
        };
    };
}
