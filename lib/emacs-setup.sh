# Sourced into a writeShellApplication with BASECAMP_* supplied by Nix.
assume_yes=0
dry_run=0
explicit=0
mode=""
for arg in "$@"; do
  case "$arg" in
    -y|--yes) assume_yes=1 ;;
    -n|--dry-run) dry_run=1 ;;
    --emacs=gui|--emacs=nox|--emacs=none) mode="${arg#--emacs=}"; explicit=1 ;;
    -h|--help)
      echo 'Usage: [--emacs=gui|nox|none] [--yes] [--dry-run]'
      echo 'Emacs is opt-in. Choices are remembered; --yes does not enable it.'
      exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 1 ;;
  esac
done
choice="$HOME/.config/nix-basecamp/emacs"
root="$HOME/.local/state/nix-basecamp/emacs"
profile="$root/package"
if [ "$explicit" = 0 ] && [ -f "$choice" ]; then
  mode="$(cat "$choice")"
  case "$mode" in gui|nox|none) ;; *) echo "invalid Emacs choice in $choice" >&2; exit 1 ;; esac
fi
if [ -z "$mode" ] && [ "$dry_run" = 0 ] && [ "$assume_yes" = 0 ]; then
  if ( : </dev/tty ) 2>/dev/null; then
    printf 'Optional Emacs setup: gui / nox / none [none]: ' >/dev/tty
    read -r mode </dev/tty || mode=none
    mode="${mode:-none}"
    case "$mode" in gui|nox|none) explicit=1 ;; *) echo 'Expected gui, nox, or none.' >&2; exit 1 ;; esac
  fi
fi
if [ -z "$mode" ] && [ "$BASECAMP_STANDALONE" = 1 ] && [ "$dry_run" = 0 ]; then
  echo 'Choose explicitly: --emacs=gui or --emacs=nox (or run from a terminal).' >&2
  exit 1
fi
mode="${mode:-none}"
if [ -n "$BASECAMP_PLAN" ]; then "$BASECAMP_PLAN"; fi
echo "Emacs: $mode · dedicated basecamp installation · existing init files preserved"
if [ "$mode" != none ]; then
  echo "  binaries: $HOME/.local/bin/{emacs,emacsclient} (add ~/.local/bin to PATH)"
  if [ "$BASECAMP_DARWIN" = 1 ] && [ "$mode" = gui ]; then
    echo "  application: $HOME/Applications/Emacs.app (other Emacs.app bundles are moved aside)"
  fi
fi
if [ "$dry_run" = 1 ]; then
  echo '(dry run — nothing was changed)'
  exit 0
fi
if [ "$assume_yes" = 0 ]; then
  if ! ( : </dev/tty ) 2>/dev/null; then
    echo 'no terminal for confirmation; pass --yes' >&2
    exit 1
  fi
  printf 'Proceed? [y/N] ' >/dev/tty
  read -r answer </dev/tty || answer=""
  case "$answer" in y|Y|yes|YES) ;; *) exit 1 ;; esac
fi
app="$HOME/Applications/Emacs.app"
owned_link() { [ -L "$1" ] && [ "$(readlink "$1")" = "$2" ]; }
# The standalone app's name before Emacs.app; only an owned link is removed.
old_app="$HOME/Applications/Nix Basecamp Emacs.app"
# Check all destinations before changing any of them or the main setup.
if [ "$mode" != none ]; then
  for bin in emacs emacsclient; do
    dest="$HOME/.local/bin/$bin"
    if { [ -e "$dest" ] || [ -L "$dest" ]; } && ! owned_link "$dest" "$profile/bin/$bin"; then
      echo "Emacs: refusing to replace $dest; move it aside explicitly first." >&2
      exit 1
    fi
  done
fi
if [ -n "$BASECAMP_SETUP" ]; then "$BASECAMP_SETUP" --yes; fi
if [ "$mode" = none ]; then
  for bin in emacs emacsclient; do
    dest="$HOME/.local/bin/$bin"
    if owned_link "$dest" "$profile/bin/$bin"; then rm "$dest"; fi
  done
  for a in "$app" "$old_app"; do
    if owned_link "$a" "$profile/Applications/Emacs.app"; then rm "$a"; fi
  done
  # This link is the GC root of the standalone install, not a user profile.
  if [ -L "$profile" ]; then rm "$profile"; fi
else
  mkdir -p "$root" "$HOME/.local/bin"
  gui=false
  if [ "$mode" = gui ]; then gui=true; fi
  nix build --impure --out-link "$profile" \
    --extra-experimental-features 'nix-command flakes' \
    --expr "(builtins.getFlake \"$BASECAMP_FLAKE\").lib.emacsPackage { system = \"$BASECAMP_SYSTEM\"; gui = $gui; }"
  for bin in emacs emacsclient; do
    ln -sfn "$profile/bin/$bin" "$HOME/.local/bin/$bin"
  done
  if [ "$BASECAMP_DARWIN" = 1 ]; then
    if owned_link "$old_app" "$profile/Applications/Emacs.app"; then rm "$old_app"; fi
    if [ "$mode" = gui ]; then
      # Nix's Emacs.app is the only one: others are moved aside (casks via brew).
      keep=""
      if owned_link "$app" "$profile/Applications/Emacs.app"; then keep="$app"; fi
      bash "$BASECAMP_APP_TAKEOVER" "$keep"
      mkdir -p "$HOME/Applications"
      ln -sfn "$profile/Applications/Emacs.app" "$app"
    elif owned_link "$app" "$profile/Applications/Emacs.app"; then
      rm "$app"
    fi
    "$BASECAMP_WARM" start "$(readlink -f "$profile")"
  fi
  "$profile/bin/emacs" --batch -Q --eval '(princ (concat "Emacs ready: " emacs-version "\n"))'
fi
# Persist only after success; --yes without a choice leaves first-run undecided.
if [ "$explicit" = 1 ]; then
  mkdir -p "$(dirname "$choice")"
  choice_tmp="$(mktemp "$choice.XXXXXX")"
  printf '%s\n' "$mode" >"$choice_tmp"
  mv "$choice_tmp" "$choice"
fi
echo "Emacs setup complete: $mode"
