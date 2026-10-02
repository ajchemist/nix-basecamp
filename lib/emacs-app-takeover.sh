# bash emacs-app-takeover.sh [KEEP]
# Nix's Emacs.app becomes the only one. Homebrew casks that install an
# Emacs.app are uninstalled through brew (moving their bundle would leave brew
# inconsistent); any other Emacs.app in /Applications or ~/Applications is
# moved to Emacs.app.before-basecamp, never deleted. KEEP is the bundle that
# is ours, if it sits in one of those places. Failures warn, never abort.
# BASECAMP_BREW and BASECAMP_APPS_ROOT exist for the tests.
keep="${1:-}"
brew="${BASECAMP_BREW:-$(command -v brew || echo /opt/homebrew/bin/brew)}"
if [ -x "$brew" ]; then
  for cask in emacs emacs-app emacs-mac; do
    if "$brew" list --cask "$cask" >/dev/null 2>&1; then
      echo "Emacs: uninstalling Homebrew cask $cask (nix's Emacs.app replaces it)"
      "$brew" uninstall --cask "$cask" || echo "Emacs: could not uninstall cask $cask; left as is" >&2
    fi
  done
fi
for app in "${BASECAMP_APPS_ROOT:-}/Applications/Emacs.app" "$HOME/Applications/Emacs.app"; do
  if [ "$app" = "$keep" ] || { [ ! -e "$app" ] && [ ! -L "$app" ]; }; then continue; fi
  if [ -e "$app.before-basecamp" ] || [ -L "$app.before-basecamp" ]; then
    echo "Emacs: $app.before-basecamp already exists; $app left in place" >&2
  elif mv "$app" "$app.before-basecamp"; then
    echo "Emacs: moved $app to $app.before-basecamp"
  else
    echo "Emacs: could not move $app aside; left in place" >&2
  fi
done
true
