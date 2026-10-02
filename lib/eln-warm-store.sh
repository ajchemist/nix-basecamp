#!/bin/sh
# eln-warm-store start|status EMACS-STORE-PATH
# The built-in eln of one Emacs store path, warmed once in the background.
# The marker is per store path, so an upgrade warms again and a second start
# while one runs (another switch) is a no-op; a run cut short by a reboot
# leaves a stale pid and is restarted by the next start.
set -eu
cmd="${1:?start|status}" pkg="${2:?emacs store path}"
mark="$HOME/.cache/emacs/eln-warmed.${pkg##*/}"
running() { kill -0 "$(cat "$mark.pid" 2>/dev/null)" 2>/dev/null; }
case "$cmd" in
  status)
    if [ -e "$mark" ]; then echo "done"
    elif running; then echo "running $(cat "$mark.pid")"
    else echo pending; fi ;;
  start)
    if [ ! -e "$mark" ] && ! running; then
      mkdir -p "${mark%/*}"
      # shellcheck disable=SC2016 # expanded by the child shell
      nohup @shell@ -c 'echo $$ >"$2.pid"; "$0" "$1" && mv "$2.pid" "$2"' \
        @eln_warm@ "$pkg/lib/emacs" "$mark" >/dev/null 2>&1 </dev/null &
    fi ;;
  *) echo "usage: eln-warm-store start|status EMACS-STORE-PATH" >&2; exit 2 ;;
esac
