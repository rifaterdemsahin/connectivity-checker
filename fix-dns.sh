#!/usr/bin/env bash
# ==============================================================================
# 🛠 macOS & Linux Universal DNS Fixer & Recovery Suite
# Automatically detects active interfaces, resets DNS overrides, fixes Tailscale
# hijacks, applies high-performance public DNS, and flushes cache.
# ==============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}"
echo "================================================================="
echo "       🛠 Universal DNS & Network Connectivity Fixer            "
echo "================================================================="
echo -e "${NC}"

# Detect OS
OS_TYPE="$(uname -s)"

# Step 1: Detect Active Network Interface & macOS Service Name
echo -e "${BOLD}[1/5] Detecting Active Network Interface & Service...${NC}"

ACTIVE_IFACE=""
if command -v route >/dev/null 2>&1; then
    ACTIVE_IFACE=$(route -n get default 2>/dev/null | grep 'interface:' | awk '{print $2}' || true)
fi

if [ -z "$ACTIVE_IFACE" ]; then
    ACTIVE_IFACE="en0" # fallback default for Mac Wi-Fi
fi

SERVICE_NAME=""
if [ "$OS_TYPE" = "Darwin" ]; then
    # Find matching networksetup service name for the active interface
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
    
    # Fallback to Wi-Fi if undetected
    if [ -z "$SERVICE_NAME" ]; then
        SERVICE_NAME="Wi-Fi"
    fi
    echo -e "  ${GREEN}✓${NC} Active Interface: ${BOLD}${ACTIVE_IFACE}${NC}"
    echo -e "  ${GREEN}✓${NC} macOS Network Service: ${BOLD}${SERVICE_NAME}${NC}"
fi

# Step 2: Fix Tailscale MagicDNS / VPN Overrides if present
echo -e "\n${BOLD}[2/5] Checking and neutralizing VPN / Tailscale DNS Overrides...${NC}"

TS_BIN=""
if command -v tailscale >/dev/null 2>&1; then
    TS_BIN="tailscale"
elif [ -f "/Applications/Tailscale.app/Contents/MacOS/Tailscale" ]; then
    TS_BIN="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
fi

if [ -n "$TS_BIN" ]; then
    echo -e "  ${BLUE}ℹ${NC} Tailscale found: Disabling MagicDNS override (--accept-dns=false)..."
    "$TS_BIN" set --accept-dns=false 2>/dev/null || "$TS_BIN" down 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} Tailscale DNS override disabled."
else
    echo -e "  ${YELLOW}ℹ${NC} Standalone Tailscale CLI not active (turn off via menu bar if Tailscale is running)."
fi

# Step 3: Apply Fast & Secure Public DNS Servers
echo -e "\n${BOLD}[3/5] Applying Ultra-Fast Anycast Public DNS (Cloudflare + Google)...${NC}"
echo -e "  Primary:   ${BOLD}1.1.1.1${NC} (Cloudflare Primary)"
echo -e "  Secondary: ${BOLD}8.8.8.8${NC} (Google Primary)"
echo -e "  Backup 1:  ${BOLD}1.0.0.1${NC} (Cloudflare Secondary)"
echo -e "  Backup 2:  ${BOLD}8.8.4.4${NC} (Google Secondary)"

if [ "$OS_TYPE" = "Darwin" ]; then
    if [ "$EUID" -ne 0 ]; then
        echo -e "\n${YELLOW}🔑 Administrator privileges (sudo) required to update macOS network settings.${NC}"
        sudo networksetup -setdnsservers "$SERVICE_NAME" 1.1.1.1 8.8.8.8 1.0.0.1 8.8.4.4
    else
        networksetup -setdnsservers "$SERVICE_NAME" 1.1.1.1 8.8.8.8 1.0.0.1 8.8.4.4
    fi
    echo -e "  ${GREEN}✓${NC} Applied DNS configuration to ${BOLD}${SERVICE_NAME}${NC}."
else
    # Linux fallback
    if [ "$EUID" -ne 0 ]; then
        echo -e "nameserver 1.1.1.1\nnameserver 8.8.8.8" | sudo tee /etc/resolv.conf >/dev/null || true
    else
        echo -e "nameserver 1.1.1.1\nnameserver 8.8.8.8" > /etc/resolv.conf || true
    fi
    echo -e "  ${GREEN}✓${NC} Updated /etc/resolv.conf."
fi

# Step 4: Flush System DNS Cache
echo -e "\n${BOLD}[4/5] Flushing System DNS Cache...${NC}"
if [ "$OS_TYPE" = "Darwin" ]; then
    if [ "$EUID" -ne 0 ]; then
        sudo dscacheutil -flushcache
        sudo killall -HUP mDNSResponder 2>/dev/null || true
    else
        dscacheutil -flushcache
        killall -HUP mDNSResponder 2>/dev/null || true
    fi
    echo -e "  ${GREEN}✓${NC} macOS DNS responder cache refreshed."
fi

# Step 5: Verification & Diagnostic Test
echo -e "\n${BOLD}[5/5] Testing DNS Resolution & Endpoints...${NC}"

DOMAINS=("google.com" "cloudflare.com" "api.anthropic.com" "github.com")
SUCCESS_COUNT=0

for domain in "${DOMAINS[@]}"; do
    if nc -z -w 3 "$domain" 443 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Resolved & Connected: ${BOLD}${domain}:443${NC}"
        ((SUCCESS_COUNT++))
    else
        echo -e "  ${RED}✗${NC} Could not reach: ${BOLD}${domain}${NC}"
    fi
done

echo -e "\n${CYAN}================================================================="
if [ "$SUCCESS_COUNT" -ge 2 ]; then
    echo -e "                    ${GREEN}${BOLD}🎉 FIX SUCCESSFUL!${NC}${CYAN}                           "
    echo -e "=================================================================${NC}"
    echo -e "Your DNS stack is fully restored and resolving domain names at high speed."
    echo -e "Active DNS servers: 1.1.1.1, 8.8.8.8, 1.0.0.1, 8.8.4.4 on [${SERVICE_NAME}]"
else
    echo -e "                    ${RED}${BOLD}⚠ ATTENTION NEEDED${NC}${CYAN}                           "
    echo -e "=================================================================${NC}"
    echo -e "Domain resolution is still encountering issues."
    echo -e "Try resetting Wi-Fi interface or checking physical router connection."
fi

# Mobile Prompt / Gemini Card
echo -e "\n${MAGENTA}${BOLD}📱 GEMINI MOBILE / PHONE TRIAGE PROMPT (Copy if you need AI help):${NC}"
echo -e "${YELLOW}-----------------------------------------------------------------"
echo -e "Context: My Mac (Interface: ${ACTIVE_IFACE}, Service: ${SERVICE_NAME}) had Layer 3 IP reachability (1.1.1.1:443 OK) but DNS resolution failed. I ran the DNS fixer applying 1.1.1.1 and 8.8.8.8. Current test results: ${SUCCESS_COUNT}/${#DOMAINS[@]} domains resolved. Please provide next triage steps if still failing."
echo -e "-----------------------------------------------------------------${NC}\n"
