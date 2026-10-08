#!/usr/bin/env bash
# macOS only. After `nix run . -- --yes --emacs=gui` on the runner: how long
# the once-per-store-path warm-up of Emacs's built-in .eln takes, and what a
# first dlopen costs with and without it. Results go to the job summary.
set -euo pipefail
emacs="$(readlink -f /run/current-system/sw/bin/emacs)"; pkg="${emacs%/bin/*}"
store_status() { "$(nix eval --raw --impure --expr "(builtins.getFlake \"path:$PWD\").lib.emacsWarm { system = builtins.currentSystem; }")/bin/eln-warm-store" status "$pkg"; }
count="$(find "$pkg/lib/emacs" -name '*.eln' | wc -l | tr -d ' ')"
dl() { /usr/bin/python3 -c 'import ctypes,sys,time;t=time.perf_counter();ctypes.CDLL(sys.argv[1]);print(f"{time.perf_counter()-t:.3f}")' "$1"; }

# A fresh .eln nobody has opened: the vetting cost per file.
d="$(mktemp -d)"; printf ';;; -*- lexical-binding: t -*-\n(defun probe () %s)\n' "$RANDOM$RANDOM" > "$d/p.el"
/run/current-system/sw/bin/emacs --batch --eval "(native-compile \"$d/p.el\" \"$d/p.eln\")" >/dev/null 2>&1
fresh_first="$(dl "$d/p.eln")"; fresh_second="$(dl "$d/p.eln")"

t0=$SECONDS
until [ "$(store_status)" = "done" ]; do
  [ $((SECONDS - t0)) -gt 3000 ] && { echo "warm-up not done after 50 min: $(store_status)"; exit 1; }
  sleep 15
done
took=$((SECONDS - t0))
sample="$(find "$pkg/lib/emacs" -name '*.eln' | sort | awk 'NR % 300 == 0' | head -10)"
after="$(for f in $sample; do dl "$f"; done | sort -n | tail -1)"

echo "eln: $count files, warm-up waited ${took}s; fresh .eln first ${fresh_first}s / second ${fresh_second}s; slowest of 10 warmed store .eln ${after}s"
{
  echo "### Built-in .eln warm-up (macOS runner)"
  echo "| measure | value |"; echo "|---|---|"
  echo "| built-in .eln files | $count |"
  echo "| warm-up wait after setup returned | ${took}s |"
  echo "| fresh .eln, first dlopen | ${fresh_first}s |"
  echo "| fresh .eln, second dlopen | ${fresh_second}s |"
  echo "| warmed store .eln, slowest of 10 | ${after}s |"
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
