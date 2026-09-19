#!/usr/bin/env bash
# ==============================================================================
# 🌐 Advanced Network Connectivity & DNS Triage Tool (macOS / Linux)
# Detects Layer 3 IP Reachability vs Layer 7 DNS Failures & MagicDNS Hijacks
# Produces formatted output + Gemini Mobile triage card for offline AI troubleshooting
# ==============================================================================

set -euo pipefail

# Color formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${MAGENTA}${BOLD}=================================================================${NC}"
echo -e "${CYAN}${BOLD}       🌐 Advanced Network Connectivity & DNS Triage Tool        ${NC}"
echo -e "${MAGENTA}${BOLD}=================================================================${NC}"
echo -e "${YELLOW}        ⚡ Lay-3 Reachability  •  🧠 DNS Triage  •  🚀 Speed${NC}"
echo ""

FAILURES=0
WARNINGS=0
OS_TYPE="$(uname -s)"

# Step 1: Default Gateway & Active Interface
echo -e "${BOLD}[1/6] Checking Active Network Interfaces & Default Route...${NC}"
DEFAULT_IFACE=""
if command -v route >/dev/null 2>&1; then
    DEFAULT_IFACE=$(route -n get default 2>/dev/null | grep 'interface:' | awk '{print $2}' || true)
fi

if [ -z "$DEFAULT_IFACE" ]; then
    DEFAULT_IFACE="en0"
fi

SERVICE_NAME="Wi-Fi"
if [ "$OS_TYPE" = "Darwin" ]; then
    SERVICE_NAME=$(networksetup -listnetworkserviceorder 2>/dev/null | awk -v iface="$DEFAULT_IFACE" '
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
    ' || true)
    [ -z "$SERVICE_NAME" ] && SERVICE_NAME="Wi-Fi"
fi

echo -e "  ${GREEN}✓${NC} Default Route Interface: ${BOLD}${DEFAULT_IFACE}${NC} (${SERVICE_NAME})"

# Get Local IPv4 & IPv6
LOCAL_IPV4=$(ifconfig "$DEFAULT_IFACE" 2>/dev/null | grep 'inet ' | awk '{print $2}' || true)
LOCAL_IPV6=$(ifconfig "$DEFAULT_IFACE" 2>/dev/null | grep 'inet6 ' | head -n 1 | awk '{print $2}' || true)
echo -e "  ${BLUE}ℹ${NC} Local IPv4: ${BOLD}${LOCAL_IPV4:-None}${NC} | IPv6: ${BOLD}${LOCAL_IPV6:-None}${NC}"

# Step 2: Layer 3 - Direct IP Reachability
echo -e "\n${BOLD}[2/6] Testing Layer 3 Reachability (Direct TCP to Public IP)...${NC}"
IP_TEST_SUCCESS=false

if nc -z -w 3 1.1.1.1 443 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Direct TCP connect to 1.1.1.1:443 (Cloudflare Anycast) -> ${GREEN}SUCCESS${NC}"
    IP_TEST_SUCCESS=true
elif nc -z -w 3 8.8.8.8 53 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Direct TCP connect to 8.8.8.8:53 (Google Anycast) -> ${GREEN}SUCCESS${NC}"
    IP_TEST_SUCCESS=true
else
    echo -e "  ${RED}✗${NC} Cannot reach public IP addresses directly (1.1.1.1 / 8.8.8.8)"
    echo -e "    ${YELLOW}➔ Physical Wi-Fi link or default gateway routing issue.${NC}"
    FAILURES=$((FAILURES + 1))
fi

# Step 3: Layer 7 - System DNS vs Direct Public DNS Query
echo -e "\n${BOLD}[3/6] Testing DNS Resolution (System Resolver vs Direct Anycast)...${NC}"
DOMAINS=("google.com" "api.anthropic.com" "github.com" "cloudflare.com")
SYSTEM_DNS_PASS=0
DIRECT_DNS_PASS=0

for domain in "${DOMAINS[@]}"; do
    # System resolution test via TCP connect
    if nc -z -w 2 "$domain" 443 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} System Resolved & Connected: ${BOLD}${domain}:443${NC}"
        SYSTEM_DNS_PASS=$((SYSTEM_DNS_PASS + 1))
    else
        # Try dig via system resolver
        if dig +time=2 +tries=1 "$domain" +short 2>/dev/null | grep -q '^[0-9.]'; then
            echo -e "  ${GREEN}✓${NC} System Dig resolved: ${BOLD}${domain}${NC}"
            SYSTEM_DNS_PASS=$((SYSTEM_DNS_PASS + 1))
        else
            echo -e "  ${RED}✗${NC} System DNS Resolution FAILED for: ${BOLD}${domain}${NC}"
        fi
    fi
    
    # Direct Public DNS query test (bypass local resolver)
    if dig +time=2 +tries=1 @"1.1.1.1" "$domain" +short 2>/dev/null | grep -q '^[0-9.]'; then
        DIRECT_DNS_PASS=$((DIRECT_DNS_PASS + 1))
    fi
done

echo -e "  ${BLUE}ℹ${NC} System Resolver Score: ${BOLD}${SYSTEM_DNS_PASS}/${#DOMAINS[@]}${NC} | Direct 1.1.1.1 Query Score: ${BOLD}${DIRECT_DNS_PASS}/${#DOMAINS[@]}${NC}"

if [ "$SYSTEM_DNS_PASS" -lt "${#DOMAINS[@]}" ]; then
    FAILURES=$((FAILURES + 1))
fi

# Step 4: Inspect System DNS Resolver Configuration
echo -e "\n${BOLD}[4/6] Inspecting DNS Resolvers & Network Setup...${NC}"
TAILSCALE_RESOLVER_ACTIVE=false
TAILSCALE_UTUN_ACTIVE=false
CURRENT_MAC_DNS=""

if [ "$OS_TYPE" = "Darwin" ]; then
    RAW_MAC_DNS=$(networksetup -getdnsservers "$SERVICE_NAME" 2>/dev/null || true)
    if echo "$RAW_MAC_DNS" | grep -q "There aren't any DNS Servers"; then
        CURRENT_MAC_DNS="DHCP (Router Default)"
    else
        CURRENT_MAC_DNS=$(echo "$RAW_MAC_DNS" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    fi
    echo -e "  ${BLUE}ℹ${NC} Configured DNS on [${SERVICE_NAME}]: ${BOLD}${CURRENT_MAC_DNS}${NC}"
    
    SCUTIL_DNS=$(scutil --dns 2>/dev/null || true)
    
    # Check if 100.95.0.x (Tailscale MagicDNS) is in resolver #1
    if echo "$SCUTIL_DNS" | grep -E -A 10 "resolver #1" | grep -q "100.95.0"; then
        TAILSCALE_RESOLVER_ACTIVE=true
        echo -e "  ${RED}⚠ DETECTED:${NC} Resolver #1 is hijacked by Tailscale MagicDNS (${BOLD}100.95.0.251-254${NC})!"
    else
        PRIMARY_NS=$(echo "$SCUTIL_DNS" | grep 'nameserver\[0\]' | head -n 1 | awk '{print $3}' || true)
        echo -e "  ${GREEN}✓${NC} Primary Resolver in scutil: ${BOLD}${PRIMARY_NS:-Unknown}${NC}"
    fi

    # Check for Tailscale utun adapter
    if ifconfig 2>/dev/null | grep -E "100\.(6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7])\." >/dev/null; then
        TAILSCALE_UTUN_ACTIVE=true
        TS_IP=$(ifconfig 2>/dev/null | grep -oE "100\.(6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7])\.[0-9]+\.[0-9]+" | head -n 1 || true)
        echo -e "  ${YELLOW}ℹ${NC} Active Tailscale CGNAT IP on utun adapter: ${BOLD}${TS_IP}${NC}"
    fi
fi

# Step 5: Tailscale Client Status
echo -e "\n${BOLD}[5/6] Checking Tailscale Client Status...${NC}"
TS_BIN=""
if command -v tailscale >/dev/null 2>&1; then
    TS_BIN="tailscale"
elif [ -f "/Applications/Tailscale.app/Contents/MacOS/Tailscale" ]; then
    TS_BIN="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
    echo -e "  ${BLUE}ℹ${NC} Found Tailscale App binary at: ${BOLD}${TS_BIN}${NC}"
fi

if [ -n "$TS_BIN" ]; then
    TS_STATUS=$("$TS_BIN" status 2>&1 || true)
    if echo "$TS_STATUS" | grep -iq "Tailscale is stopped"; then
        echo -e "  ${GREEN}✓${NC} Tailscale Status: ${BOLD}Stopped${NC}"
    else
        echo -e "  ${YELLOW}⚠${NC} Tailscale Status: ${BOLD}Running / Connected${NC}"
    fi
else
    echo -e "  ${YELLOW}ℹ${NC} Tailscale CLI not present in PATH."
fi

# Step 6: Speed & Latency Benchmark
echo -e "\n${BOLD}[6/6] Running Speed & Latency Benchmark (Downlink / Uplink / Ping)...${NC}"

speed_bar() {
    local value="$1"
    local max="$2"
    local color="$3"
    local width=30
    awk -v v="$value" -v m="$max" -v w="$width" -v c="$color" '
        BEGIN {
            if (m <= 0) m = 1
            filled = int((v / m) * w)
            if (filled > w) filled = w
            if (filled < 0) filled = 0
            bar = ""
            for (i = 0; i < w; i++) {
                if (i < filled) bar = bar "█"
                else bar = bar "░"
            }
            printf "  %s%s %6.1f Mbps\033[0m\n", c, bar, v
        }'
}

DL_MBPS=""
UL_MBPS=""
PING_MS=""
RESP_RPM=""

if command -v networkQuality >/dev/null 2>&1; then
    echo -e "  ${MAGENTA}▶${NC} Querying Apple ${BOLD}networkQuality${NC} engine (takes ~15-30s)..."
    NQ_OUT=$(networkQuality -s 2>&1 || networkQuality 2>&1 || true)
    DL_MBPS=$(echo "$NQ_OUT" | grep -i "Downlink capacity" | grep -oE "[0-9]+(\.[0-9]+)?" | head -n 1 || true)
    UL_MBPS=$(echo "$NQ_OUT" | grep -i "Uplink capacity" | grep -oE "[0-9]+(\.[0-9]+)?" | head -n 1 || true)
    PING_MS=$(echo "$NQ_OUT" | grep -i "Idle Latency" | grep -oE "[0-9]+(\.[0-9]+)?" | head -n 1 || true)
    RESP_RPM=$(echo "$NQ_OUT" | grep -i "Responsiveness" | grep -oE "\(([0-9]+) RPM\)" | grep -oE "[0-9]+" | head -n 1 || true)
fi

if [ -z "$DL_MBPS" ]; then
    echo -e "  ${BLUE}ℹ${NC} Falling back to Cloudflare multi-stream test..."
    DL_BPS=$(curl -s -w "%{speed_download}" -o /dev/null --max-time 20 \
        "https://speed.cloudflare.com/__down?bytes=25000000" 2>/dev/null || echo "0")
    if [ -n "$DL_BPS" ] && [ "$DL_BPS" != "0" ]; then
        DL_MBPS=$(awk "BEGIN {printf \"%.1f\", $DL_BPS * 8 / 1000000}")
    fi
    UL_BPS=$(head -c 5000000 /dev/zero | curl -s -w "%{speed_upload}" -o /dev/null --max-time 20 \
        -X POST --data-binary @- "https://speed.cloudflare.com/__up" 2>/dev/null || echo "0")
    if [ -n "$UL_BPS" ] && [ "$UL_BPS" != "0" ]; then
        UL_MBPS=$(awk "BEGIN {printf \"%.1f\", $UL_BPS * 8 / 1000000}")
    fi
fi

echo ""
if [ -n "$DL_MBPS" ]; then
    DL_MBPS=$(awk "BEGIN {printf \"%.1f\", $DL_MBPS}")
    echo -e "  ${GREEN}${BOLD}▼ DOWNLINK${NC}"
    speed_bar "$DL_MBPS" 1000 "$GREEN"
else
    echo -e "  ${YELLOW}⚠${NC} Downlink measurement unavailable."
fi

if [ -n "$UL_MBPS" ]; then
    UL_MBPS=$(awk "BEGIN {printf \"%.1f\", $UL_MBPS}")
    echo -e "  ${BLUE}${BOLD}▲ UPLINK${NC}"
    speed_bar "$UL_MBPS" 200 "$BLUE"
else
    echo -e "  ${YELLOW}⚠${NC} Uplink measurement unavailable."
fi

if [ -n "$PING_MS" ]; then
    PING_MS=$(awk "BEGIN {printf \"%d\", $PING_MS}")
    echo -e "  ${CYAN}⏱  Idle Latency: ${BOLD}${PING_MS} ms${NC}"
fi
if [ -n "$RESP_RPM" ]; then
    echo -e "  ${MAGENTA}📊 Responsiveness: ${BOLD}${RESP_RPM} RPM${NC}"
fi

# Step 7: Diagnosis & Auto-Fix Trigger
echo -e "\n${CYAN}================================================================="
echo "                       DIAGNOSIS SUMMARY                         "
echo -e "=================================================================${NC}"

if [ "$IP_TEST_SUCCESS" = true ] && [ "$SYSTEM_DNS_PASS" -lt "${#DOMAINS[@]}" ]; then
    echo -e "${RED}${BOLD}🚨 CONFIRMED: Layer 7 DNS Resolution Outage!${NC}"
    echo -e "  - Layer 3 Physical/Routing: ${GREEN}ONLINE (1.1.1.1 reachable)${NC}"
    echo -e "  - Layer 7 System DNS:      ${RED}OFFLINE (${SYSTEM_DNS_PASS}/${#DOMAINS[@]} working)${NC}"
    
    if [ "$DIRECT_DNS_PASS" -gt 0 ]; then
        echo -e "  - Direct Public DNS Query: ${GREEN}SUCCESS (1.1.1.1 answers queries)${NC}"
        echo -e "\n${YELLOW}${BOLD}🔍 ROOT CAUSE:${NC}"
        echo -e "  Your Wi-Fi DHCP DNS or local resolver is broken/stuck, but public Anycast DNS is reachable."
    fi

    echo -e "\n${GREEN}${BOLD}⚡ INSTANT 1-CLICK FIX COMMAND:${NC}"
    echo -e "  ${BOLD}sudo ./fix-dns.sh${NC}"
    echo -e "  Or copy-paste one-liner:"
    echo -e "  ${BOLD}sudo networksetup -setdnsservers \"${SERVICE_NAME}\" 1.1.1.1 8.8.8.8 1.0.0.1 8.8.4.4 && sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder${NC}"
elif [ "$FAILURES" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}✅ ALL SYSTEMS FULLY OPERATIONAL!${NC}"
    echo -e "  - Physical Link & Layer 3: ${GREEN}Healthy${NC}"
    echo -e "  - System DNS Resolution:   ${GREEN}Healthy (${SYSTEM_DNS_PASS}/${#DOMAINS[@]} domains resolved)${NC}"
    echo -e "  - Active DNS Servers:      ${BOLD}${CURRENT_MAC_DNS:-Default Router / Anycast}${NC}"
    if [ -n "$DL_MBPS" ]; then
        echo -e "  - Throughput:              ${GREEN}${DL_MBPS} Mbps ↓${NC} / ${BLUE}${UL_MBPS:-?} Mbps ↑${NC} (${CYAN}${PING_MS:-?} ms${NC})"
    fi
else
    echo -e "${RED}${BOLD}❌ PHYSICAL / ROUTING FAILURE:${NC} Check your Wi-Fi connection or ethernet cable."
fi

# Step 7: Mobile Phone & Gemini Mobile Copy-Paste Card
echo -e "\n${MAGENTA}${BOLD}================================================================="
echo "      📱 GEMINI MOBILE / PHONE TROUBLESHOOTING PROMPT            "
echo -e "=================================================================${NC}"
echo -e "${YELLOW}Copy the text below into the Gemini app on your phone for instant step-by-step help:${NC}\n"
cat << GEMINI_PROMPT
I am troubleshooting network connectivity on my Mac. Here are my diagnostic results:
- OS / Active Interface: ${OS_TYPE} / ${DEFAULT_IFACE} (${SERVICE_NAME})
- Layer 3 Direct IP: $( [ "$IP_TEST_SUCCESS" = true ] && echo "WORKING (1.1.1.1:443 connected)" || echo "FAILED" )
- System DNS Resolution: ${SYSTEM_DNS_PASS}/${#DOMAINS[@]} domains resolved
- Direct 1.1.1.1 DNS Query: ${DIRECT_DNS_PASS}/${#DOMAINS[@]} succeeded
- Current DNS Config: ${CURRENT_MAC_DNS:-DHCP Default}
- Tailscale utun / MagicDNS: $( [ "$TAILSCALE_UTUN_ACTIVE" = true ] && echo "Active (utun)" || echo "Inactive" )
- Speed Test: Downlink ${DL_MBPS:-N/A} Mbps | Uplink ${UL_MBPS:-N/A} Mbps | Ping ${PING_MS:-N/A} ms
Question: What exact macOS Terminal commands or System Settings steps should I take to fix this right now?
GEMINI_PROMPT
echo -e "\n${MAGENTA}${BOLD}=================================================================${NC}\n"
