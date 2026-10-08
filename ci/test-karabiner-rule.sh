#!/usr/bin/env bash
# End-to-end test of the #karabiner-rule app against the invoking user's HOME.
# Intended for CI runners (mutates ~/.config/karabiner/karabiner.json).
# BASECAMP_FLAKE overrides the flake reference (default: .).
set -euo pipefail
flake="${BASECAMP_FLAKE:-.}"
unset BASECAMP_KARABINER

desc="Make left modifiers(control, option, command) key work in Korean mode"
cfg="$HOME/.config/karabiner/karabiner.json"

echo "--- case 1: fresh (no existing karabiner.json)"
rm -f "$cfg"
nix run "$flake#karabiner-rule"
jq -e --arg d "$desc" '
  [.profiles[] | select(.selected == true)
   | .complex_modifications.rules[] | select(.description == $d)]
  | length == 1
' "$cfg" > /dev/null

echo "--- case 2: idempotent (second run must not change the file)"
before="$(cat "$cfg")"
nix run "$flake#karabiner-rule"
[ "$before" = "$(cat "$cfg")" ]

echo "--- case 3: existing config; same-description rule replaced, rest preserved"
mkdir -p "$(dirname "$cfg")"
cat > "$cfg" <<EOF
{
  "global": { "show_in_menu_bar": false },
  "profiles": [
    {
      "name": "Battle",
      "selected": true,
      "complex_modifications": {
        "rules": [
          { "description": "$desc", "manipulators": [] },
          { "description": "Other rule", "manipulators": [] }
        ]
      }
    },
    { "name": "Playground" }
  ]
}
EOF
nix run "$flake#karabiner-rule"
jq -e --arg d "$desc" '
  ([.profiles[] | select(.selected == true)
    | .complex_modifications.rules[] | select(.description == $d)] | length == 1)
  and ([.profiles[] | select(.selected == true)
    | .complex_modifications.rules[] | select(.description == "Other rule")] | length == 1)
  and ((.profiles[] | select(.selected == true)
    | .complex_modifications.rules[] | select(.description == $d)
    | .manipulators | length) == 3)
  and (.global.show_in_menu_bar == false)
  and ((.profiles | length) == 2)
' "$cfg" > /dev/null

echo "--- case 4: Karabiner off; karabiner.json left alone, absent one not created"
before="$(cat "$cfg")"
BASECAMP_KARABINER=off nix run "$flake#karabiner-rule"
[ "$before" = "$(cat "$cfg")" ]
mv "$cfg" "$cfg.case4"
BASECAMP_KARABINER=off nix run "$flake#karabiner-rule"
[ ! -e "$cfg" ]
mv "$cfg.case4" "$cfg"

echo "karabiner-rule: all tests passed"
