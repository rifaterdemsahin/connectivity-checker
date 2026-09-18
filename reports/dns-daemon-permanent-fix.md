# Permanent DNS Auto-Fix Report — macOS LaunchDaemon

**Date:** 2026-09-18
**Machine:** macOS 27.0 (build 26A428), active interface `en0` (Wi-Fi)
**Repo:** [rifaterdemsahin/connectivity-checker](https://github.com/rifaterdemsahin/connectivity-checker)
**Related incident docs:** [README](../README.md) · [Live dashboard](https://rifaterdemsahin.github.io/connectivity-checker/)

---

## 1. Executive Summary

The recurring "my DNS broke again" failure is **not** the DNS settings reverting. The configured DNS servers persist correctly — the problem is the **macOS resolver cache / `mDNSResponder` going stale on boot or after a Wi-Fi reconnect**, so the system keeps answering from a dead cache until it is flushed by hand.

The permanent fix is a **root LaunchDaemon** (`com.rifaterdemsahin.dnsfix`) that:

1. Re-asserts fast public DNS (Cloudflare + Google) on the active network service.
2. Flushes the resolver cache (`dscacheutil` + `mDNSResponder`).
3. Runs **automatically at every boot/login**, and **every 30 minutes** as a safety net.

It requires `sudo` **once** at install time. After that it runs as root forever — no manual commands, no password prompts.

> **Status at time of writing:** the daemon files are committed, but the install step (copy to `/Library/LaunchDaemons` + `launchctl bootstrap`) has **not been run yet**. Until it is, DNS continues to be held manually at `1.1.1.1 / 8.8.8.8 / 1.0.0.1 / 8.8.4.4` on Wi-Fi. See §7 for the current verified state.

---

## 2. Problem Statement

- DNS resolution (`google.com`, `grok`, `dig api.anthropic.com`) times out on startup or shortly after a Wi-Fi reconnect.
- Raw IP connectivity is fine (`nc -zv 1.1.1.1 443` succeeds), so Layer 3 routing is healthy — only Layer 7 name resolution fails.
- Running `networksetup -setdnsservers ...` + `dscacheutil -flushcache` + `killall -HUP mDNSResponder` fixes it instantly, which is why the failure kept being misread as "the DNS settings reverted."

## 3. Root Cause

`scutil --dns` shows resolver #1 pointing at the manually-set public servers, and `networksetup -getdnsservers Wi-Fi` already returns the correct list. In other words, **the persistent DNS configuration is intact after the failure**. What goes stale is the in-memory resolver state:

- At boot, `mDNSResponder` starts before the Wi-Fi service has fully applied its DNS configuration; early queries get cached as failures.
- On Wi-Fi reconnect (sleep/wake, network switch), the resolver cache can retain entries keyed to the previous network state.
- The stale cache is only cleared by the flush step, which is exactly why the manual fix works every time.

The LaunchDaemon design targets the actual fault: **re-assert DNS + flush the cache on a schedule and at load**, instead of relying on the user to notice and run the fix.

## 4. Files Delivered

| File | Purpose |
| :--- | :--- |
| `dns-daemon-fix.sh` | Worker script: detects the active interface/service, applies `1.1.1.1 8.8.8.8 1.0.0.1 8.8.4.4`, flushes cache, logs to `/var/log/dns-daemon-fix.log`. |
| `com.rifaterdemsahin.dnsfix.plist` | LaunchDaemon definition: `RunAtLoad` + `StartInterval 1800` (30 min), stdout/stderr to the same log. |

Daemon behaviour:

- Resolves the default-route interface via `route -n get default`, maps it to the network service name via `networksetup -listnetworkserviceorder` (falls back to `Wi-Fi` / `en0`), so it survives Ethernet/Thunderbolt changes.
- `RunAtLoad` covers boot/login; `StartInterval 1800` covers long sessions and delayed Wi-Fi reconnects.
- Logs one line per run, e.g. `Applied DNS (...) to Wi-Fi (en0) and flushed cache.`

## 5. Installation (One-Time, Needs `sudo`)

Run in a normal terminal (prompts once for the password):

```bash
sudo cp /Users/rifaterdemsahin/projects/connectivity-checker/com.rifaterdemsahin.dnsfix.plist /Library/LaunchDaemons/com.rifaterdemsahin.dnsfix.plist
sudo chown root:wheel /Library/LaunchDaemons/com.rifaterdemsahin.dnsfix.plist
sudo chmod 644 /Library/LaunchDaemons/com.rifaterdemsahin.dnsfix.plist
sudo chmod +x /Users/rifaterdemsahin/projects/connectivity-checker/dns-daemon-fix.sh
sudo launchctl bootstrap system /Library/LaunchDaemons/com.rifaterdemsahin.dnsfix.plist
sudo launchctl kickstart -k system/com.rifaterdemsahin.dnsfix
```

## 6. Verification

```bash
# Is the daemon loaded?
launchctl print system/com.rifaterdemsahin.dnsfix | head -20

# Did it run and what did it do?
tail -20 /var/log/dns-daemon-fix.log

# What DNS is actually configured now?
networksetup -getdnsservers Wi-Fi
scutil --dns | head -8
```

## 7. Current Verified State (2026-09-18)

| Check | Result |
| :--- | :--- |
| `/Library/LaunchDaemons/com.rifaterdemsahin.dnsfix.plist` | **Not installed yet** |
| `launchctl print system/com.rifaterdemsahin.dnsfix` | `Could not find service` |
| `/var/log/dns-daemon-fix.log` | Does not exist yet |
| `networksetup -getdnsservers Wi-Fi` | `1.1.1.1 8.8.8.8 1.0.0.1 8.8.4.4` (manual, correct) |
| Default route / interface | `en0` |
| `ping -c1 google.com` | Resolves and replies (~9.7 ms) |

Until §5 is run, every reboot/Wi-Fi reconnect can still require the manual flush.

## 8. Rollback

```bash
sudo launchctl bootout system/com.rifaterdemsahin.dnsfix
sudo rm /Library/LaunchDaemons/com.rifaterdemsahin.dnsfix.plist
sudo rm -f /var/log/dns-daemon-fix.log
```

## 9. Operational Notes & Follow-Ups

- **Log rotation:** `/var/log/dns-daemon-fix.log` grows one line per 30 minutes (≈ 48 lines/day). `newsyslog` can rotate it if it ever matters.
- **Tailscale:** if MagicDNS hijacking returns, it overrides resolver order at the `utun*` layer — the daemon re-asserts public DNS on Wi-Fi but does not disable Tailscale DNS (`tailscale set --accept-dns=false` remains the targeted fix; see `fix-dns.sh`).
- **Hardcoded path:** the plist points at `/Users/rifaterdemsahin/projects/connectivity-checker/dns-daemon-fix.sh`. If the repo moves, update the plist and re-bootstrap.
- **Single point of failure:** if the script is deleted while the plist remains, launchd logs a spawn failure instead of fixing DNS. Keep the two files together in this repo.
