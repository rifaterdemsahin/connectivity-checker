#!/usr/bin/env bash
# ==============================================================================
# Connectivity & Tailscale DNS Diagnostic Script
# Detects Layer 3 IP Reachability vs Layer 7 DNS Failures & Tailscale MagicDNS Hijacks
# ==============================================================================

set -euo pipefail

# Color formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${CYAN}${BOLD}"
echo "================================================================="
echo "       🌐 Network Connectivity & DNS Triage Tool (macOS/Linux)   "
echo "================================================================="
echo -e "${NC}"

FAILURES=0
WARNINGS=0

# Step 1: Default Gateway & Active Interface
echo -e "${BOLD}[1/6] Checking Active Network Interfaces & Default Route...${NC}"
DEFAULT_IFACE=""
if command -v route >/dev/null 2>&1; then
    DEFAULT_IFACE=$(route -n get default 2>/dev/null | grep 'interface:' | awk '{print $2}' || true)
fi

if [ -n "$DEFAULT_IFACE" ]; then
    echo -e "  ${GREEN}✓${NC} Default Route Interface: ${BOLD}${DEFAULT_IFACE}${NC}"
else
    echo -e "  ${YELLOW}⚠${NC} Could not determine primary default interface"
    ((WARNINGS++))
fi

# Step 2: Layer 3 - Direct IP Reachability
echo -e "\n${BOLD}[2/6] Testing Layer 3 Reachability (Direct IP to Public DNS)...${NC}"
IP_TEST_SUCCESS=false

# Test 1.1.1.1 (Cloudflare) on port 443
if nc -z -w 3 1.1.1.1 443 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Direct TCP connect to 1.1.1.1:443 (Cloudflare) -> ${GREEN}SUCCESS${NC}"
    IP_TEST_SUCCESS=true
elif nc -z -w 3 8.8.8.8 53 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Direct TCP connect to 8.8.8.8:53 (Google DNS) -> ${GREEN}SUCCESS${NC}"
    IP_TEST_SUCCESS=true
else
    echo -e "  ${RED}✗${NC} Cannot reach public IP addresses directly (1.1.1.1 / 8.8.8.8)"
    echo -e "    ${YELLOW}➔ Physical link or default gateway routing issue.${NC}"
    ((FAILURES++))
fi

# Step 3: Layer 7 - DNS Hostname Resolution
echo -e "\n${BOLD}[3/6] Testing DNS Hostname Resolution...${NC}"
DOMAINS=("google.com" "api.anthropic.com" "github.com" "cloudflare.com")
DNS_FAIL_COUNT=0

for domain in "${DOMAINS[@]}"; do
    if nc -z -w 3 "$domain" 443 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Resolved & Connected: ${BOLD}${domain}:443${NC}"
    else
        # Try dig or nslookup
        if dig +time=2 +tries=1 "$domain" +short 2>/dev/null | grep -q '^[0-9.]'; then
            echo -e "  ${GREEN}✓${NC} Dig resolved: ${BOLD}${domain}${NC}"
        else
            echo -e "  ${RED}✗${NC} DNS Resolution FAILED for: ${BOLD}${domain}${NC}"
            ((DNS_FAIL_COUNT++))
        fi
    fi
done

if [ "$DNS_FAIL_COUNT" -gt 0 ]; then
    ((FAILURES++))
fi

# Step 4: Inspect System DNS Resolvers
echo -e "\n${BOLD}[4/6] Inspecting System DNS Resolver Hierarchy...${NC}"
TAILSCALE_RESOLVER_ACTIVE=false
TAILSCALE_UTUN_ACTIVE=false

if [[ "$OSTYPE" == "darwin"* ]]; then
    SCUTIL_DNS=$(scutil --dns 2>/dev/null || true)
    
    # Check if 100.95.0.x (Tailscale MagicDNS) is listed in resolver #1
    if echo "$SCUTIL_DNS" | grep -E -A 10 "resolver #1" | grep -q "100.95.0"; then
        TAILSCALE_RESOLVER_ACTIVE=true
        echo -e "  ${RED}⚠ DETECTED:${NC} Resolver #1 is set to Tailscale MagicDNS (${BOLD}100.95.0.251-254${NC}) with high priority!"
    else
        PRIMARY_NS=$(echo "$SCUTIL_DNS" | grep 'nameserver\[0\]' | head -n 1 | awk '{print $3}')
        echo -e "  ${GREEN}✓${NC} Primary Resolver nameserver[0]: ${BOLD}${PRIMARY_NS:-Unknown}${NC}"
    fi

    # Check for Tailscale utun adapter
    if ifconfig 2>/dev/null | grep -E "100\.(6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7])\." >/dev/null; then
        TAILSCALE_UTUN_ACTIVE=true
        TS_IP=$(ifconfig 2>/dev/null | grep -oE "100\.(6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7])\.[0-9]+\.[0-9]+" | head -n 1)
        echo -e "  ${YELLOW}ℹ${NC} Active Tailscale CGNAT IP detected on utun adapter: ${BOLD}${TS_IP}${NC}"
    fi
else
    # Linux / etc/resolv.conf check
    if grep -E "nameserver 100\.95\." /etc/resolv.conf 2>/dev/null; then
        TAILSCALE_RESOLVER_ACTIVE=true
        echo -e "  ${RED}⚠ DETECTED:${NC} /etc/resolv.conf pointing to Tailscale MagicDNS (100.95.0.x)"
    fi
fi

# Step 5: Tailscale CLI & Daemon Detection
echo -e "\n${BOLD}[5/6] Checking Tailscale Client Status...${NC}"
TS_BIN=""
if command -v tailscale >/dev/null 2>&1; then
    TS_BIN="tailscale"
elif [ -f "/Applications/Tailscale.app/Contents/MacOS/Tailscale" ]; then
    TS_BIN="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
    echo -e "  ${BLUE}ℹ${NC} Found macOS App Store Tailscale binary at: ${BOLD}${TS_BIN}${NC}"
fi

if [ -n "$TS_BIN" ]; then
    TS_STATUS=$("$TS_BIN" status 2>&1 || true)
    if echo "$TS_STATUS" | grep -iq "Tailscale is stopped"; then
        echo -e "  ${GREEN}✓${NC} Tailscale Status: ${BOLD}Stopped${NC}"
    else
        echo -e "  ${YELLOW}⚠${NC} Tailscale Status: ${BOLD}Running / Connected${NC}"
    fi
else
    echo -e "  ${YELLOW}ℹ${NC} 'tailscale' CLI is not in your current PATH."
    echo -e "    Tip for macOS: alias tailscale='/Applications/Tailscale.app/Contents/MacOS/Tailscale'"
fi

# Step 6: Final Diagnosis & Recommendations
echo -e "\n${CYAN}================================================================="
echo "                       DIAGNOSIS SUMMARY                         "
echo -e "=================================================================${NC}"

if [ "$IP_TEST_SUCCESS" = true ] && [ "$DNS_FAIL_COUNT" -gt 0 ]; then
    echo -e "${RED}${BOLD}🚨 ISSUE CONFIRMED: DNS Resolution Outage (Layer 3 OK, Layer 7 Down)${NC}"
    echo -e "Your IP routing is healthy (can reach 1.1.1.1 / 8.8.8.8), but domain names fail to resolve."
    
    if [ "$TAILSCALE_RESOLVER_ACTIVE" = true ] || [ "$TAILSCALE_UTUN_ACTIVE" = true ]; then
        echo -e "\n${YELLOW}${BOLD}🔍 ROOT CAUSE:${NC}"
        echo -e "  Tailscale MagicDNS hijacked the primary system DNS resolver (order 104200 in macOS scutil)."
        echo -e "  When Tailscale's upstream resolver becomes unreachable, all standard DNS requests time out."
        
        echo -e "\n${GREEN}${BOLD}🛠 HOW TO FIX:${NC}"
        echo -e "  1. ${BOLD}Quick GUI Fix:${NC} Click Tailscale menubar icon -> Turn OFF / Disconnect Tailscale."
        echo -e "  2. ${BOLD}Quick CLI Fix:${NC}"
        if [ -n "$TS_BIN" ]; then
            echo -e "     $TS_BIN down"
            echo -e "     $TS_BIN up --accept-dns=false"
        else
            echo -e "     /Applications/Tailscale.app/Contents/MacOS/Tailscale down"
            echo -e "     /Applications/Tailscale.app/Contents/MacOS/Tailscale up --accept-dns=false"
        fi
        echo -e "  3. ${BOLD}Tailscale Admin Console:${NC} Disable 'MagicDNS' under DNS settings if you want to use local Wi-Fi DNS."
        echo -e "  4. ${BOLD}Flush macOS DNS Cache:${NC}"
        echo -e "     sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder"
    fi
elif [ "$FAILURES" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}✅ ALL SYSTEMS HEALTHY!${NC}"
    echo -e "  - Layer 3 IP connectivity is active."
    echo -e "  - DNS resolution is resolving domains correctly."
else
    echo -e "${RED}${BOLD}❌ NETWORK DISCONNECTED:${NC} Please check your Wi-Fi/Ethernet cable and router."
fi

echo -e "${CYAN}=================================================================${NC}\n"
