# 🌐 Connectivity Checker & Universal DNS Fixer

An incident post-mortem, diagnostic suite, and interactive triage toolkit for diagnosing macOS & Linux connectivity failures where **Layer 3 IP routing works** (`1.1.1.1:443`), but **Layer 7 DNS resolution fails** (`google.com:443`) due to router DNS timeouts or Tailscale MagicDNS resolver hijacks.

🔗 **Live Web Dashboard:** [https://rifaterdemsahin.github.io/connectivity-checker/](https://rifaterdemsahin.github.io/connectivity-checker/)

---

## ⚡ Instant Emergency Commands

### 1. One-Liner Fix (Copy & Paste into macOS Terminal)
Sets ultra-fast public DNS (Cloudflare + Google), flushes system cache, and restarts the DNS daemon:
```bash
sudo networksetup -setdnsservers Wi-Fi 1.1.1.1 8.8.8.8 1.0.0.1 8.8.4.4 && sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder
```
*(Note: Ensure `-setdnsservers` has the trailing `s`)*

### 2. Automated Diagnostic & Fixer Script
```bash
# Run comprehensive diagnostic
./check-connectivity.sh

# Run universal DNS fixer
./fix-dns.sh
```

---

## 📱 Mobile Phone & Gemini Mobile Emergency Runbook

When your laptop is completely offline or DNS-locked, you can use **Gemini on your mobile phone** (connected to cellular 4G/5G) to diagnose and generate exact recovery commands.

### 📋 Gemini Mobile Triage Prompt
Copy and paste this prompt into the Gemini app on your phone:

```text
I am troubleshooting network connectivity on my Mac. Here is my status:
- Layer 3 Direct IP: 1.1.1.1:443 connects successfully via nc / ping
- Layer 7 DNS Resolution: FAILED (google.com times out, Grok / Anthropic CLI fails)
- Active Interface: en0 (Wi-Fi)
- Tailscale / VPN status: Active or Recently Disconnected

Please give me:
1. The exact terminal command to set Cloudflare (1.1.1.1) and Google (8.8.8.8) DNS on macOS.
2. The command to flush the macOS DNS cache.
3. The step-by-step macOS System Settings GUI navigation path to configure DNS manually.
```

### 📱 Quick Mobile Steps (If you can't run scripts)
1. **macOS System Settings GUI Fix:**
   - Go to **System Settings** → **Wi-Fi**.
   - Click **Details...** next to your connected network.
   - Select **DNS** in the left sidebar.
   - Click `+` and add `1.1.1.1`, `8.8.8.8`, `1.0.0.1`, `8.8.4.4`.
   - Click **OK** → apply changes.
2. **Flush Cache:**
   - In Terminal: `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`
3. **Turn off Tailscale:**
   - If installed, click the Tailscale menu bar icon and select **Disconnect** (or `tailscale set --accept-dns=false`).

---

## 📖 The Incident Story

### 1. The Symptoms
- Commands like `nslookup google.com`, `grok`, and `dig api.anthropic.com` timed out.
- Browsers could not open any web pages.

### 2. The Breakthrough Finding
- Direct TCP connection to Cloudflare DNS IP succeeded:
  ```bash
  nc -zv 1.1.1.1 443
  # Connection to 1.1.1.1 port 443 [tcp/https] succeeded!
  ```
- Connecting to hostname failed on resolution:
  ```bash
  nc -zv google.com 443
  # nc: getaddrinfo: nodename nor servname provided, or not known
  ```
- **Conclusion:** Physical Wi-Fi and TCP/IP routing were fully operational. Only the DNS subsystem was failing.

### 3. The Root Cause
Running `scutil --dns` revealed that Tailscale's virtual network interface (`utun*` at `100.96.0.2`) had registered Tailscale MagicDNS (`100.95.0.251-254`) as **Resolver #1 with Order 104200**, taking higher priority over the local Wi-Fi DNS resolver (`order 200000`).

Because Tailscale's upstream DNS node was unreachable, all DNS queries timed out before falling back.

### 4. The Resolution
- Setting reliable public DNS servers (`1.1.1.1`, `8.8.8.8`) on the active network service (`Wi-Fi`) and flushing `mDNSResponder` restored connectivity immediately.

---

## 🛠 Included Diagnostic & Recovery Scripts

### 1. `check-connectivity.sh`
Performs a 6-step automated health check:
1. Detects default route, active interface (`en0`, `utun*`), and local IP addresses.
2. Tests Layer 3 direct IP connectivity to `1.1.1.1` and `8.8.8.8`.
3. Tests Layer 7 DNS resolution comparing System Resolver vs Direct Anycast (`@1.1.1.1`).
4. Inspects `scutil --dns` hierarchy and active macOS DNS server settings.
5. Checks Tailscale CLI and daemon status.
6. Generates a **Gemini Mobile Triage Card** ready for copy-pasting into phone AI.

```bash
chmod +x check-connectivity.sh
./check-connectivity.sh
```

### 2. `fix-dns.sh`
Automated repair utility:
- Auto-detects the active network service (e.g. `Wi-Fi`, `Ethernet`, `Thunderbolt Bridge`).
- Disables Tailscale MagicDNS hijacking (`--accept-dns=false`).
- Applies high-speed public DNS (`1.1.1.1`, `8.8.8.8`, `1.0.0.1`, `8.8.4.4`).
- Flushes macOS cache (`dscacheutil`, `mDNSResponder`).
- Verifies resolution against multiple live endpoints.

```bash
chmod +x fix-dns.sh
./fix-dns.sh
```

### 3. `speedtest.sh`
Benchmarking utility to test downlink/uplink capacity, latency, and RPM responsiveness using macOS native `networkQuality` (with `curl` fallback) and identify your infrastructure (EE Full Fibre over BT Openreach Core).

```bash
chmod +x speedtest.sh
./speedtest.sh
```

### 4. `fix-tailscale-dns.sh`
Tailscale-focused reset script for disabling VPN DNS overrides and flushing cache.

```bash
chmod +x fix-tailscale-dns.sh
./fix-tailscale-dns.sh
```

---

## ⚡ Infrastructure Benchmark: EE over BT vs Virgin Media

| Feature / Metric | EE Full Fibre (FTTP over BT Openreach) | Old Virgin Media (DOCSIS 3.0 / 3.1) |
| :--- | :--- | :--- |
| **Physical Medium** | Pure optical glass fiber direct to ONT | Hybrid Fibre-Coaxial (HFC copper street tree) |
| **Edge Ping Latency** | **8.3 ms – 9.5 ms** (UK Edge / BBC / Google) | 22.0 ms – 35.0+ ms |
| **Tested Upload Speed**| **78.3 Mbps** (~4x Virgin cable tiers) | ~20 – 25 Mbps |
| **Tested Download** | **237.7 Mbps** | 125 – 250 Mbps |
| **Street Contention** | Dedicated optical time-division | Shared neighborhood coaxial RF spectrum |
| **Packet Loss & Jitter**| **0.0%** packet loss, optical noise immunity | Prone to RF ingress & cabinet noise |

---

## 💡 Quick Tips for macOS & Tailscale

### Add Tailscale CLI Alias
If Tailscale was installed via the Mac App Store, the CLI binary is at `/Applications/Tailscale.app/Contents/MacOS/Tailscale`. Add to your `~/.zshrc`:
```bash
alias tailscale="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
```

### Disable Tailscale DNS Override
To use Tailscale for subnet routing without overriding your public DNS:
```bash
tailscale up --accept-dns=false
```

---

## 🚀 GitHub Pages Setup

1. Open repository settings: [GitHub Pages Settings](https://github.com/rifaterdemsahin/connectivity-checker/settings/pages)
2. Under **Build and deployment > Source**, select **GitHub Actions** (or **Deploy from a branch > main / (root)**).
3. The page will be published automatically at `https://rifaterdemsahin.github.io/connectivity-checker/`.
