#!/usr/bin/env bash
# ==============================================================================
# Quick Fix & Reset Script for Tailscale DNS Lockouts on macOS
# ==============================================================================

set -euo pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}🔧 Tailscale DNS Quick-Fix Utility for macOS${NC}\n"

# 1. Locate Tailscale CLI
TS_PATH=""
if command -v tailscale >/dev/null 2>&1; then
    TS_PATH="tailscale"
elif [ -f "/Applications/Tailscale.app/Contents/MacOS/Tailscale" ]; then
    TS_PATH="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
fi

if [ -n "$TS_PATH" ]; then
    echo -e "${GREEN}✓${NC} Found Tailscale binary at: ${BOLD}${TS_PATH}${NC}"
    echo "Disabling Tailscale DNS override (--accept-dns=false)..."
    "$TS_PATH" set --accept-dns=false 2>/dev/null || "$TS_PATH" down 2>/dev/null || true
    echo -e "${GREEN}✓${NC} Tailscale DNS override disabled."
else
    echo -e "${YELLOW}ℹ Tailscale standalone binary not found. Please toggle disconnect via the menu bar icon.${NC}"
fi

# 2. Reset macOS DNS Cache
echo -e "\nFlushing macOS DNS cache..."
if [ "$EUID" -ne 0 ]; then
    sudo dscacheutil -flushcache
    sudo killall -HUP mDNSResponder
else
    dscacheutil -flushcache
    killall -HUP mDNSResponder
fi
echo -e "${GREEN}✓${NC} macOS DNS Cache flushed."

# 3. Test DNS
echo -e "\nTesting DNS resolution for google.com..."
if nc -z -w 3 google.com 443 2>/dev/null; then
    echo -e "${GREEN}${BOLD}🎉 SUCCESS: DNS is working properly!${NC}"
else
    echo -e "${YELLOW}⚠ Still failing. Check Wi-Fi DNS in System Settings -> Network -> Details -> DNS.${NC}"
fi
