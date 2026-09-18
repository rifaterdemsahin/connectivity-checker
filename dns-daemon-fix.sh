#!/usr/bin/env bash
# ==============================================================================
# Runs as root via LaunchDaemon (com.rifaterdemsahin.dnsfix) at boot/login and
# every 30 minutes thereafter. Re-asserts fast public DNS and flushes the
# resolver cache so DNS never needs to be fixed by hand again.
# ==============================================================================
set -uo pipefail

LOG="/var/log/dns-daemon-fix.log"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

ACTIVE_IFACE=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
[ -z "$ACTIVE_IFACE" ] && ACTIVE_IFACE="en0"

SERVICE_NAME=$(networksetup -listnetworkserviceorder 2>/dev/null | awk -v iface="$ACTIVE_IFACE" '
    /\(Hardware Port:/ {
        port=$0
        sub(/.*\(Hardware Port: /, "", port)
        sub(/, Device:.*/, "", port)
        getline
        if ($0 ~ "Device: " iface "\\)") {
            print port
            exit
        }
    }
')
[ -z "$SERVICE_NAME" ] && SERVICE_NAME="Wi-Fi"

networksetup -setdnsservers "$SERVICE_NAME" 1.1.1.1 8.8.8.8 1.0.0.1 8.8.4.4
dscacheutil -flushcache
killall -HUP mDNSResponder 2>/dev/null || true

log "Applied DNS (1.1.1.1, 8.8.8.8, 1.0.0.1, 8.8.4.4) to ${SERVICE_NAME} (${ACTIVE_IFACE}) and flushed cache."
