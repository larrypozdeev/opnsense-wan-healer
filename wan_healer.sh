#!/bin/sh
# OPNsense WAN healer: reconfigure → bounce → (uptime-based cooldown) reboot

umask 022
PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"
set -eu

# -------------------- CONFIGURATION --------------------
INTERFACE="igc0"
IP1="1.1.1.1"
IP2="8.8.8.8"
MIN_UPTIME=120
CHECK_INTERVAL_SEC=5
RETRY_WINDOW_SEC=120
REBOOT_COOLDOWN_UPTIME=1800
LOG_FILE="/var/log/wan_healer.log"
ENABLE_LOGGING="true"

TARGET_ACTION="/usr/local/opnsense/service/conf/actions.d/actions_wan_healer.conf"
TARGET_LOCATION="/usr/local/sbin/wan-healer"
LOCK="/var/run/wan_healer.lock"

# -------------------- LOGGING --------------------
ensure_logfile() {
  if [ ! -e "$LOG_FILE" ]; then
    : > "$LOG_FILE" || true
    /bin/chmod 640 "$LOG_FILE" 2>/dev/null || true
  fi
}

log() {
  [ "$ENABLE_LOGGING" = "true" ] || return 0
  ensure_logfile
  MSG="$(/bin/date +%Y-%m-%d.%H:%M:%S) - $*"
  echo "$MSG" >> "$LOG_FILE"
  /usr/bin/logger -t wan_healer "$*"
}

# -------------------- HELPERS --------------------
get_uptime() {
  curtime="$(/bin/date +%s)"
  boottime="$(/sbin/sysctl -n kern.boottime 2>/dev/null | /usr/bin/awk -F'sec = ' '{print $2}' | /usr/bin/awk -F',' '{print $1}')"
  if [ -z "${boottime:-}" ]; then
    boottime="$(/sbin/sysctl -n kern.boottime 2>/dev/null | /usr/bin/awk -F'[, ]+' '{for(i=1;i<=NF;i++) if($i=="sec") {print $(i+2); exit}}')"
  fi
  echo $((curtime - boottime))
}

check_connectivity() {
  GW="$(/sbin/route -n get -inet default 2>/dev/null | /usr/bin/awk '/gateway:/ {print $2; exit}')"
  if [ -n "${GW:-}" ]; then
    /sbin/ping -q -c 2 -W 200 "$GW" >/dev/null 2>&1 && return 0
  fi
  /sbin/ping -q -c 2 -W 200 "$IP1" >/dev/null 2>&1 && return 0
  /sbin/ping -q -c 2 -W 200 "$IP2" >/dev/null 2>&1 && return 0
  return 1
}

reconfig_wan() {
  /usr/local/sbin/configctl interface reconfigure wan
}

bounce_wan() {
  /sbin/ifconfig "$INTERFACE" down || true
  /bin/sleep 2
  /sbin/ifconfig "$INTERFACE" up
}

reboot_box() {
  /usr/local/sbin/configctl system reboot
}

# -------------------- MAIN --------------------
main() {
  exec 9>"$LOCK" || exit 0
  if ! /usr/bin/lockf -s -t 0 9; then
    exit 0
  fi

  uptime="$(get_uptime)"
  if [ "$uptime" -lt "$MIN_UPTIME" ]; then
    exit 0
  fi

  if check_connectivity; then
    log "OK: connectivity up"
  else
    log "FAIL#1: down → reconfigure WAN"
    reconfig_wan
    /bin/sleep "$CHECK_INTERVAL_SEC"
    if ! check_connectivity; then
      log "FAIL#2: still down → bounce WAN"
      bounce_wan
      /bin/sleep "$CHECK_INTERVAL_SEC"

      fails=2
      max_fails=$(( RETRY_WINDOW_SEC / CHECK_INTERVAL_SEC ))
      [ "$max_fails" -lt 1 ] && max_fails=1
      while [ "$fails" -lt "$max_fails" ]; do
        /bin/sleep "$CHECK_INTERVAL_SEC"
        if check_connectivity; then
          log "RECOVERED after $fails consecutive fails"
          break
        fi
        fails=$((fails + 1))
        log "FAIL#$fails: still down"
      done

      if ! check_connectivity; then
        uptime="$(get_uptime)"
        if [ "$uptime" -ge "$REBOOT_COOLDOWN_UPTIME" ]; then
          log "REBOOT: ${fails} consecutive fails (uptime ${uptime}s ≥ ${REBOOT_COOLDOWN_UPTIME}s)"
          reboot_box
        else
          log "SKIP REBOOT: ${fails} consecutive fails but uptime ${uptime}s < ${REBOOT_COOLDOWN_UPTIME}s"
        fi
        exit 0
      fi
    else
      log "RECOVERED after reconfigure"
    fi
  fi
}

# -------------------- INSTALL HOOK --------------------
if [ ! -r "$TARGET_LOCATION" ]; then
  /bin/cp "$0" "$TARGET_LOCATION"
  /bin/chmod 755 "$TARGET_LOCATION"
fi

# Configd action so it shows up as "wan_healer" in the GUI/Cron
if [ ! -r "$TARGET_ACTION" ]; then
  /bin/cat > "$TARGET_ACTION" <<'EOACTION'
[wan_healer]
command:/usr/local/sbin/wan-healer
parameters:
type:script
message:starting wan healer
description:wan_healer
EOACTION
  /usr/sbin/service configd restart
fi

main
