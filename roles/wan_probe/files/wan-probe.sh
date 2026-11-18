#!/usr/bin/env bash
# WAN outage probe: every INTERVAL seconds ping a ladder of targets (modem LAN ->
# ISP DNS -> public anchors). Writes a line only when the up/down pattern changes
# (+ heartbeat every HEARTBEAT s). On the first failing cycle it captures a
# one-shot diagnosis (link state, route, ARP of gateway, mtr, DNS, public IP) so
# the failing layer can be identified afterwards. Log: /var/log/wan-probe/events.log
set -u
. /etc/default/wan-probe
LOG=${LOG:-/var/log/wan-probe/events.log}
INTERVAL=${INTERVAL:-10}; HEARTBEAT=${HEARTBEAT:-600}
mkdir -p "$(dirname "$LOG")"
ts() { date '+%F %T%z'; }
log() { echo "$(ts) $*" >> "$LOG"; }
chk() { ping -n -c 1 -W 2 "$1" >/dev/null 2>&1 && echo 1 || echo 0; }
diag() {
  {
    echo "  [diag] link: $(ip -br link show "${IFACE:-}" 2>/dev/null | tr -s ' ')"
    [ -n "${IFACE:-}" ] && command -v ethtool >/dev/null && echo "  [diag] ethtool: $(ethtool "$IFACE" 2>/dev/null | grep -E 'Speed|Link detected' | tr -s ' ' | tr '\n' ';')"
    echo "  [diag] route: $(ip route get 1.1.1.1 2>/dev/null | head -1)"
    echo "  [diag] gw-neigh: $(ip neigh show ${GW:+$GW} 2>/dev/null | head -2 | tr '\n' ';')"
    echo "  [diag] dns(google): $(timeout 4 getent hosts www.google.com 2>&1 | head -1)"
    echo "  [diag] pubip(https): $(curl -s -m 5 https://api.ipify.org 2>&1 | head -c 60)"
    if command -v mtr >/dev/null; then mtr -n -r -c 3 -w -G 1 1.1.1.1 2>&1 | sed 's/^/  [mtr] /' | head -12
    elif command -v traceroute >/dev/null; then traceroute -n -w 1 -q 1 -m 6 1.1.1.1 2>&1 | sed 's/^/  [tr] /' | head -8; fi
    command -v tailscale >/dev/null && echo "  [diag] ts: $(timeout 5 tailscale netcheck 2>&1 | grep -E 'UDP|IPv4|Nearest' | tr -s ' ' | tr '\n' ';')"
  } >> "$LOG" 2>&1
}
prev=""; last_hb=0; down_since=0
log "start targets: $TARGETS iface=${IFACE:-} gw=${GW:-}"
while true; do
  pat=""; line=""
  for t in $TARGETS; do n=${t%%=*}; ip=${t#*=}; r=$(chk "$ip"); pat="$pat$r"; line="$line $n=$r"; done
  now=$(date +%s)
  if [ "$pat" != "$prev" ]; then
    log "CHANGE$line"
    if [[ "$pat" == *0* && ( -z "$prev" || "$prev" != *0* || "$pat" != "$prev" ) ]]; then
      [ "$down_since" = 0 ] && down_since=$now
      diag
    fi
    if [[ "$pat" != *0* && "$down_since" != 0 ]]; then log "RECOVERED after $((now-down_since))s"; down_since=0; fi
    prev=$pat; last_hb=$now
  elif [ $((now-last_hb)) -ge "$HEARTBEAT" ]; then
    log "hb$line"; last_hb=$now
  fi
  # still down: re-run diag every 5 min
  if [[ "$pat" == *0* ]] && [ $(( (now-down_since) % 300 )) -lt "$INTERVAL" ] && [ "$down_since" != 0 ] && [ "$now" != "$down_since" ]; then diag; fi
  sleep "$INTERVAL"
done
