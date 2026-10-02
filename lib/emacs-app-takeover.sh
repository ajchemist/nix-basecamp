# bash emacs-app-takeover.sh
# Nix's Emacs.app becomes the only one. Homebrew casks that install an
# Emacs.app are uninstalled through brew (moving their bundle would leave brew
# inconsistent); any other Emacs.app in /Applications or ~/Applications is
# moved to Emacs.app.before-basecamp, never deleted (nix's own lives in
# /Applications/Nix Apps, untouched here). Failures warn, never abort.
# Run from nix-darwin's activation (root) with HOME set to the primary user's
# home and BASECAMP_BREW_USER to that user: brew refuses to run as root, so it
# runs as the user the way nix-darwin's own homebrew step does.
# BASECAMP_BREW and BASECAMP_APPS_ROOT exist for the tests.
brew="${BASECAMP_BREW:-$(command -v brew || echo /opt/homebrew/bin/brew)}"
as_user=()
if [ -n "${BASECAMP_BREW_USER:-}" ]; then as_user=(sudo --user="$BASECAMP_BREW_USER" --set-home --); fi
if [ -x "$brew" ]; then
  for cask in emacs emacs-app emacs-mac; do
    if "${as_user[@]}" "$brew" list --cask "$cask" >/dev/null 2>&1; then
      echo "Emacs: uninstalling Homebrew cask $cask (nix's Emacs.app replaces it)"
      "${as_user[@]}" "$brew" uninstall --cask "$cask" || echo "Emacs: could not uninstall cask $cask; left as is" >&2
    fi
  done
fi
for app in "${BASECAMP_APPS_ROOT:-}/Applications/Emacs.app" "$HOME/Applications/Emacs.app"; do
  if [ ! -e "$app" ] && [ ! -L "$app" ]; then continue; fi
  if [ -e "$app.before-basecamp" ] || [ -L "$app.before-basecamp" ]; then
    echo "Emacs: $app.before-basecamp already exists; $app left in place" >&2
  elif mv "$app" "$app.before-basecamp"; then
    echo "Emacs: moved $app to $app.before-basecamp"
  else
    echo "Emacs: could not move $app aside; left in place" >&2
  fi
done
true
