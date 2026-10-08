#!/usr/bin/env bash
# macOS runners only, after `nix run . -- --yes [--karabiner=off]`.
# assert-karabiner.sh on|off: the applied system manages Karabiner (cask
# installed, rule in karabiner.json, plan says so) or leaves it entirely
# alone (no cask, karabiner.json absent/unchanged, plan says off).
# For "off", pass the karabiner.json state expected: absent, or a file whose
# content must be unchanged (KARABINER_SNAPSHOT).
set -euo pipefail
want="${1:?on|off}"
desc="Make left modifiers(control, option, command) key work in Korean mode"
cfg="$HOME/.config/karabiner/karabiner.json"
plan="$(nix run .#plan)"
printf '%s\n' "$plan"
rows="$(printf '%s\n' "$plan" | grep -E '\] karabiner(-rule)? ')"
[ "$(printf '%s\n' "$rows" | wc -l | tr -d ' ')" = 2 ] || { echo "expected two karabiner plan rows" >&2; exit 1; }

case "$want" in
  on)
    brew list --cask karabiner-elements >/dev/null || { echo "karabiner-elements cask not installed" >&2; exit 1; }
    jq -e --arg d "$desc" '[.profiles[] | select(.selected == true)
        | .complex_modifications.rules[] | select(.description == $d)] | length == 1' "$cfg" >/dev/null \
      || { echo "rule missing from $cfg" >&2; exit 1; }
    if printf '%s\n' "$rows" | grep -q ' off '; then echo "plan shows Karabiner off" >&2; exit 1; fi
    ;;
  off)
    if brew list --cask karabiner-elements >/dev/null 2>&1; then echo "karabiner-elements cask installed" >&2; exit 1; fi
    if [ -n "${KARABINER_SNAPSHOT:-}" ]; then
      cmp -s "$KARABINER_SNAPSHOT" "$cfg" || { echo "$cfg was modified" >&2; exit 1; }
    elif [ -e "$cfg" ]; then
      echo "$cfg was created" >&2; exit 1
    fi
    [ "$(printf '%s\n' "$rows" | grep -c ' off ')" = 2 ] || { echo "plan does not show Karabiner off" >&2; exit 1; }
    [ "$(cat "$HOME/.config/nix-basecamp/karabiner")" = off ] || { echo "off choice not saved" >&2; exit 1; }
    ;;
  *) echo "usage: assert-karabiner.sh on|off" >&2; exit 2 ;;
esac
echo "karabiner: $want as expected"
