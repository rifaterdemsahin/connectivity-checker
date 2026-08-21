# 🌐 Connectivity Checker & Tailscale DNS Triage

An incident post-mortem, diagnostic suite, and interactive guide for diagnosing macOS & Linux connectivity failures where **Layer 3 IP routing works** (`1.1.1.1:443`), but **Layer 7 DNS resolution fails** (`google.com:443`) due to VPN/Tailscale MagicDNS resolver overrides.

🔗 **Live Web Dashboard:** [https://rifaterdemsahin.github.io/connectivity-checker/](https://rifaterdemsahin.github.io/connectivity-checker/)

---

## 📖 The Incident Story

### 1. The Symptoms
- Commands like `nslookup google.com` and `dig api.anthropic.com` timed out.
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
Running `scutil --dns` revealed that Tailscale's virtual network interface (`utun5` at `100.96.0.2`) had registered Tailscale MagicDNS (`100.95.0.251-254`) as **Resolver #1 with Order 104200**, taking higher priority over the local Wi-Fi DNS resolver (`order 200000`).

Because Tailscale's upstream DNS node was unreachable, all DNS queries timed out before falling back.

### 4. The Resolution
- Turning off Tailscale in the macOS menu bar destroyed the `utun5` interface and removed Resolver #1 from `scutil`.
- The system immediately reverted to Wi-Fi DNS, and connectivity was restored instantly.

---

## 🛠 Included Diagnostic Scripts

### 1. `check-connectivity.sh`
Performs a 6-step automated health check:
1. Detects default route and active network interface (`en0`, `utun*`).
2. Tests Layer 3 direct IP connectivity to `1.1.1.1` and `8.8.8.8`.
3. Tests Layer 7 DNS resolution for `google.com`, `api.anthropic.com`, `github.com`.
4. Inspects `scutil --dns` hierarchy for MagicDNS / VPN priority hijacking (`order 104200`).
5. Checks Tailscale CLI and daemon status.
6. Outputs actionable diagnosis and repair commands.

```bash
chmod +x check-connectivity.sh
./check-connectivity.sh
```

### 2. `fix-tailscale-dns.sh`
Automates recovery by resetting Tailscale DNS overrides, flushing macOS DNS cache (`dscacheutil -flushcache`, `killall -HUP mDNSResponder`), and verifying connectivity.

```bash
chmod +x fix-tailscale-dns.sh
./fix-tailscale-dns.sh
```

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
