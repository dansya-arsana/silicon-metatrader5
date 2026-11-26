#!/bin/bash
# More MT5 terminals side by side in the native mode: one instance per broker
# account, each with its own MT5 (login, history), Python bridge, status API,
# ports and background job. They share the default instance's Wine download.
#
#   instances.sh add <name> [--port N]   create and install (bridge N, status API N+1; default: next free from 8011)
#   instances.sh start|stop|restart <name>
#   instances.sh status <name> [--json]
#   instances.sh list                    every instance with its ports and phase
#   instances.sh start-all|stop-all
#   instances.sh remove <name>           stop and delete the instance (its MT5 login and history too)
#   instances.sh env <name>              the variables that select the instance (for native.sh or scripts)
#
# The default instance (smt5 / the app, bridge 8001) stays as it is and must be
# installed first: instances use its Wine. Python bots reach an instance with
#   MetaTrader5(host="127.0.0.1", port=<its bridge port>)
# Folders: ~/Library/Application Support/SiliconMT5-instances/<name> (macOS),
# ~/.local/share/siliconmt5-instances/<name> (Linux); SMT5_INSTANCES_HOME overrides.
set -uo pipefail

SELF="$0"
while [ -L "$SELF" ]; do                  # called through a link (e.g. ~/.local/bin/smt5-instances): find the real file
  t="$(readlink "$SELF")"; case "$t" in /*) SELF="$t" ;; *) SELF="$(dirname "$SELF")/$t" ;; esac
done
HERE="$(cd "$(dirname "$SELF")" && pwd)"
NATIVE="$HERE/native.sh"
OS="$(uname -s)"
if [ "$OS" = Darwin ]; then DEFAULT_BASE="$HOME/Library/Application Support/SiliconMT5"; else DEFAULT_BASE="${XDG_DATA_HOME:-$HOME/.local/share}/siliconmt5"; fi
INSTANCES_HOME="${SMT5_INSTANCES_HOME:-$DEFAULT_BASE-instances}"
FIRST_PORT=8011

die() { echo "instances.sh: $*" >&2; exit 1; }
valid_name() { case "${1:-}" in ''|*[!a-z0-9-]*|-*) return 1 ;; esac; [ "${#1}" -le 24 ]; }
home_of() { echo "$INSTANCES_HOME/$1"; }
names() { [ -d "$INSTANCES_HOME" ] && for d in "$INSTANCES_HOME"/*/; do [ -f "$d/.env" ] && basename "$d"; done; return 0; }
get() { sed -n "s/^$2=//p" "$(home_of "$1")/.env" 2>/dev/null | tail -1 | tr -d '"'"'"; }
port_open() { (exec 3<>"/dev/tcp/127.0.0.1/$1") >/dev/null 2>&1; }

used_ports() {
  grep -E '^SMT5_(BRIDGE|STATUS)_PORT=' "$DEFAULT_BASE/.env" 2>/dev/null | sed 's/^[^=]*=//' | tr -d '"'"'"
  echo 8001; echo 8002
  local n; for n in $(names); do get "$n" SMT5_BRIDGE_PORT; get "$n" SMT5_STATUS_PORT; done
}
free_pair() {  # free_pair <port>: true when <port> and <port>+1 are unused and closed
  local p used; used=" $(used_ports | tr '\n' ' ') "
  for p in "$1" "$(( $1 + 1 ))"; do
    case "$used" in *" $p "*) return 1 ;; esac
    port_open "$p" && return 1
  done
  return 0
}

# Run native.sh as instance <name>.
run_as() {
  local n="$1"; shift
  local h; h="$(home_of "$n")"
  [ -f "$h/.env" ] || die "no instance '$n' (instances.sh list)"
  SMT5_NATIVE_HOME="$h" SMT5_LABEL="com.siliconmt5.runtime.$n" SMT5_UNIT="siliconmt5-runtime-$n" \
  SMT5_WINE_HOME="$DEFAULT_BASE/wine" SMT5_ENV_FILE="$h/.env" SMT5_INSTANCES_HOME="$INSTANCES_HOME" \
    /bin/bash "$NATIVE" "$@"
}

cmd_add() {
  local n="${1:-}" port=""; shift || true
  valid_name "$n" || die "name: lowercase letters, digits and '-', up to 24 characters (e.g. exness-demo)"
  while [ $# -gt 0 ]; do
    case "$1" in --port) port="${2:-}"; shift 2 ;; *) die "unknown option $1" ;; esac
  done
  [ -d "$DEFAULT_BASE/wine" ] || die "install the default instance first (smt5 build, or native.sh install): instances share its Wine"
  local h; h="$(home_of "$n")"
  [ -e "$h/.env" ] && die "instance '$n' exists already"
  if [ -n "$port" ]; then
    case "$port" in *[!0-9]*) die "--port: a number" ;; esac
    [ "$port" -ge 1024 ] && [ "$port" -le 65534 ] || die "--port: 1024 to 65534"
    free_pair "$port" || die "port $port or $((port + 1)) is in use"
  else
    port=$FIRST_PORT
    until free_pair "$port"; do port=$((port + 10)); [ "$port" -le 65000 ] || die "no free port pair"; done
  fi
  mkdir -p "$h" && chmod 0700 "$h"
  local token; token="$(openssl rand -hex 24 2>/dev/null || head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  ( umask 077
    # the default instance's settings (bars, algo trading, ...) without its ports and token
    grep -E '^SMT5_[A-Z0-9_]+=' "$DEFAULT_BASE/.env" 2>/dev/null | grep -vE '^SMT5_(BRIDGE_PORT|STATUS_PORT|DISPLAY_PORT|API_TOKEN|PROVIDER)=' >"$h/.env"
    printf 'SMT5_PROVIDER=mac-native\nSMT5_BRIDGE_PORT=%s\nSMT5_STATUS_PORT=%s\nSMT5_DISPLAY_PORT=%s\nSMT5_API_TOKEN=%s\n' "$port" "$((port + 1))" "$((port + 2))" "$token" >>"$h/.env" )
  echo "instance '$n': bridge 127.0.0.1:$port, status API 127.0.0.1:$((port + 1)) — installing MT5 (a few minutes)"
  run_as "$n" install || { echo "install failed; the folder stays for a retry: instances.sh start $n" >&2; exit 1; }
  echo "done. Start it with: instances.sh start $n   (then log in to the broker in its MT5 window)"
}

cmd_list() {
  local n st any=0
  printf '%-24s %-7s %-7s %s\n' NAME BRIDGE STATUS PHASE
  printf '%-24s %-7s %-7s %s\n' "(default)" "$(sed -n 's/^SMT5_BRIDGE_PORT=//p' "$DEFAULT_BASE/.env" 2>/dev/null | tr -d '"'"'" | grep . || echo 8001)" \
    "$(sed -n 's/^SMT5_STATUS_PORT=//p' "$DEFAULT_BASE/.env" 2>/dev/null | tr -d '"'"'" | grep . || echo 8002)" \
    "$(/bin/bash "$NATIVE" status --json 2>/dev/null | sed -n 's/.*"phase": *"\([^"]*\)".*/\1/p' | head -1)"
  for n in $(names); do
    any=1
    st="$(run_as "$n" status --json 2>/dev/null | sed -n 's/.*"phase": *"\([^"]*\)".*/\1/p' | head -1)"
    printf '%-24s %-7s %-7s %s\n' "$n" "$(get "$n" SMT5_BRIDGE_PORT)" "$(get "$n" SMT5_STATUS_PORT)" "${st:-stopped}"
  done
  [ "$any" = 1 ] || echo "(no other instances: instances.sh add <name>)"
}

cmd_remove() {
  local n="${1:-}"
  valid_name "$n" && [ -f "$(home_of "$n")/.env" ] || die "no instance '$n'"
  run_as "$n" uninstall
  rm -rf "$(home_of "$n")"
  echo "instance '$n' removed (the shared Wine stays)"
}

case "${1:-}" in
  add) shift; cmd_add "$@" ;;
  start|stop|restart) c="$1"; shift; valid_name "${1:-}" || die "which instance?"; run_as "$1" "$c" ;;
  status) shift; valid_name "${1:-}" || die "which instance?"; n="$1"; shift; run_as "$n" status "${1:-}" ;;
  list) cmd_list ;;
  start-all) for n in $(names); do run_as "$n" start; done ;;
  stop-all) for n in $(names); do run_as "$n" stop; done ;;
  remove) shift; cmd_remove "${1:-}" ;;
  env) shift; valid_name "${1:-}" || die "which instance?"; h="$(home_of "$1")"
       printf 'SMT5_NATIVE_HOME=%q\nSMT5_LABEL=com.siliconmt5.runtime.%s\nSMT5_UNIT=siliconmt5-runtime-%s\nSMT5_WINE_HOME=%q\nSMT5_ENV_FILE=%q\n' "$h" "$1" "$1" "$DEFAULT_BASE/wine" "$h/.env" ;;
  *) awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"; exit 2 ;;
esac
