# Chokepoint

**Turn any Linux laptop or server into a full-featured, temporary router — in one command.**

![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)
![Shell: Bash](https://img.shields.io/badge/shell-bash-4EAA25.svg)
![Platform: Linux](https://img.shields.io/badge/platform-linux-lightgrey.svg)

A *chokepoint* is the single place all traffic must pass through — the best spot to observe and control it.

Plug a device into your Ethernet port (or use a spare Wi-Fi card as an access point) and `chokepoint` shares your
upstream connection with it — with DHCP, a caching DNS resolver, domain blocking, port forwarding, traffic capture,
sandboxing for untrusted devices, transparent proxying for Burp/mitmproxy, bandwidth shaping, PXE boot and more.

Nothing is persistent: `stop` (or a reboot) undoes every change.

```
$ sudo chokepoint start --lan eth1
→ Configuring eth1 as 192.168.50.1/24
→ Loading firewall/NAT table 'chokepoint_default'
→ Starting dnsmasq (DHCP DNS)

✔ Router 'default' is up
  ● default up 0s
    LAN     eth1 192.168.50.1/24 → WAN wlan0 (192.168.1.23/24)
    DHCP    192.168.50.10 – 192.168.50.254, lease 12h, 0 active, 0 reserved
    DNS     192.168.50.1 → 1.1.1.1 9.9.9.9 · .lan · 0 blocked domains · 0 blocklist entries · log off
    Filter  0 port-forwards · 0 blocked MACs
    Procs   dnsmasq pid 44061
```

---

## Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Commands](#commands)
- [Options](#options)
- [Profiles (YAML)](#profiles-yaml)
- [Scenarios](#scenarios)
- [How it works](#how-it-works)
- [Troubleshooting](#troubleshooting)
- [Security notes](#security-notes)
- [Contributing](#contributing)
- [License](#license)

---

## Features

| Area | What you get |
|---|---|
| **Routing / NAT** | Share any upstream (Wi-Fi, Ethernet, VPN `tun0`) with a LAN port or Wi-Fi AP. Several routers at once, one per LAN interface. |
| **DHCP** | Address pool, lease time, static leases (MAC → IP/hostname), raw DHCP options, PXE/TFTP boot. Leases survive `restart`. |
| **DNS** | Caching resolver, local domain (`host.lan`), custom records, domain blocking incl. subdomains, downloadable ad/malware blocklists, query logging, forced DNS (hijack hard-coded resolvers). |
| **Security** | `--sandbox` mode, host isolation, Internet-only clients, DNS-over-TLS blocking, MAC blocking, transparent proxy redirect for Burp/mitmproxy. |
| **Observability** | `clients`, `leases`, `logs -f`, `top` (most queried / blocked domains, busiest clients), `capture` (pcap), `scan` (nmap). |
| **Live management** | Block domains, add DNS records, static leases, port forwards, ban devices — instantly, without restarting. |
| **Shaping** | Cap LAN download/upload rate to simulate slow links or tame a device. |
| **Wi-Fi AP** | Run a WPA2 (or open/hidden) access point via hostapd. |
| **Config** | CLI flags, `CP_*` env vars, and layered YAML profiles. `--dry-run` previews every command and firewall rule. |
| **Automation** | `post_up` / `pre_down` hooks to start tools together with the router. |

## Requirements

**Required:** `bash` ≥ 4.4, `iproute2` (`ip`), `nftables` (`nft`), `dnsmasq`, `python3`, root (the script re-runs itself via `sudo`).

**Optional:**

| Tool | Used for |
|---|---|
| `python3-yaml` (PyYAML) | Full YAML support (a built-in minimal parser is used otherwise) |
| `iptables` | Compatibility with Docker / UFW `DROP` policies |
| `nmcli` | Stops NetworkManager from reconfiguring the LAN interface |
| `hostapd` | Wi-Fi access-point mode |
| `tc` (iproute2) | Bandwidth shaping |
| `tcpdump` | `capture` |
| `nmap` | `scan` (falls back to a ping sweep for host discovery) |
| `curl` or `wget` | Downloading blocklists |

Debian / Ubuntu / Parrot / Kali:

```bash
sudo apt install iproute2 nftables dnsmasq-base python3 python3-yaml \
                 hostapd tcpdump nmap curl
```

> If the full `dnsmasq` package is installed, make sure its system service is not listening on all interfaces
> (`sudo systemctl disable --now dnsmasq`) — the router runs its own dnsmasq instance bound to the LAN interface only.

Check everything at once:

```bash
chokepoint check
```

## Installation

```bash
git clone https://github.com/Arttacker/chokepoint.git
cd chokepoint
./chokepoint check                 # run in place...
sudo make install                  # ...or install to /usr/local (bin + bundled profiles)
```

`make install` copies the script to `/usr/local/bin/chokepoint` and the bundled profiles to
`/usr/local/share/chokepoint/profiles`. Use `sudo make uninstall` to remove them, or `PREFIX=~/.local make install`
for a user-local install.

## Quick start

```bash
# 1. Find your interfaces (the default-route interface is the WAN candidate)
chokepoint check

# 2. Share the default upstream with whatever is plugged into eth1
sudo chokepoint start --lan eth1

# 3. See what connected
chokepoint leases
chokepoint clients

# 4. Done
sudo chokepoint stop
```

Not sure what it will do? Add `--dry-run` to any `start` — it prints every command and the full nftables ruleset
without touching the system (no root needed).

## Commands

```
chokepoint <command> [options] [args]
```

### Lifecycle

| Command | Description |
|---|---|
| `start` | Bring the router up. Needs `--lan` or a profile; with neither, the `default` profile is used if it exists. |
| `stop` | Tear everything down. The DNS log (if enabled) is saved to the capture dir. |
| `restart` | Stop + start. Re-uses the running configuration unless you pass new options/profiles. |
| `status` | Show running routers, their services and enabled features. |

### Observe

| Command | Description |
|---|---|
| `leases` | DHCP leases (IP, MAC, hostname, expiry). |
| `clients` | Devices seen on the LAN, with hostname, neighbour state and flags (reserved / BLOCKED). |
| `logs [N] [-f]` | Last N lines of DNS queries, DHCP and AP events; `-f` to follow. Falls back to the journal when query logging is off. |
| `top [N]` | Top N queried domains, busiest clients and blocked lookups. Needs `--log-queries`. |
| `capture [BPF filter]` | tcpdump on the LAN into `/var/tmp/chokepoint/<name>-<timestamp>.pcap`. `--live` prints packets instead. |
| `scan` | Host discovery on the LAN subnet. |
| `scan ports [IP...]` | nmap service scan of the given hosts (or the whole subnet). |

### Manage live (no restart)

Changes are applied immediately and last until `stop`. Put permanent ones in a profile.

| Command | Description |
|---|---|
| `block [list]` / `block add\|del DOMAIN...` | Block domains and all their subdomains (NXDOMAIN). |
| `dns [list]` / `dns add NAME IP` / `dns del NAME` / `dns flush` | Local DNS records; `flush` clears the cache. |
| `reserve [list]` / `reserve add MAC IP [HOST]` / `reserve del MAC` | Static DHCP leases (applied on the device's next DHCP request). |
| `forward [list]` / `forward add\|del SPEC` | Port forwards, `SPEC = tcp\|udp:WAN_PORT:LAN_IP[:LAN_PORT]`. |
| `client [list]` / `client block\|unblock MAC\|IP` | Cut a device off: no DHCP, no traffic, deauthenticated on Wi-Fi. |

### Profiles & tools

| Command | Description |
|---|---|
| `profiles` | List available profiles (with description, running marker). |
| `init [NAME\|FILE]` | Write a fully commented profile from defaults + the options you pass. No argument → stdout. |
| `config` | Print the effective configuration (profiles + env + flags) as YAML. |
| `config running` | Print the configuration of the running router. |
| `check` | Dependencies, interfaces, running routers. |
| `help [examples\|config]` | Help, scenario cookbook, or YAML key reference. |

## Options

Options may appear before or after the command. List options are repeatable.

### General

| Option | Description |
|---|---|
| `-p, --profile NAME\|FILE` | Load a YAML profile. Repeat to layer profiles (later wins). |
| `-c, --config FILE` | Same as `--profile`. |
| `-n, --name NAME` | Instance name. Lets several routers run side by side; selects which one runtime commands act on. |
| `--set KEY=VALUE` | Set any config key by YAML path or key name, e.g. `--set dns.cache_size=5000`. |
| `--dry-run` | Print commands and rulesets instead of executing them. |
| `--force` | Override safety checks; overwrite files with `init`. |
| `-f, --follow` | Follow output (`logs`). |
| `--live` | `capture`: print packets instead of writing a pcap. |
| `--no-color`, `-h/--help`, `-V/--version` | |

### Network

| Option | Default | Description |
|---|---|---|
| `--lan IFACE` | — | Interface the clients are on (**required** unless set in a profile). |
| `--wan IFACE` | `auto` | Upstream to share; `auto` = interface of the default route. Can be a VPN (`tun0`). |
| `-a, --address IP/PREFIX` | `192.168.50.1/24` | Router address on the LAN. |

### DHCP

| Option | Default | Description |
|---|---|---|
| `--dhcp-range A-B` | `.10` – last host | Address pool. |
| `--lease TIME` | `12h` | Lease time (`30m`, `12h`, `infinite`). |
| `--reserve MAC,IP[,HOST]` | | Static lease. |
| `--dhcp-option OPT` | | Raw dnsmasq `dhcp-option`, e.g. `option:ntp-server,192.168.50.1`. |
| `--tftp-root DIR` | | Enable the built-in TFTP server. |
| `--boot-file FILE` | | PXE boot file (`pxelinux.0`, `ipxe.efi`, …). |
| `--no-dhcp` | | Don't serve DHCP. |

### DNS

| Option | Default | Description |
|---|---|---|
| `--dns IP[#PORT]` | `1.1.1.1 9.9.9.9` | Upstream resolver. |
| `--domain NAME` | `lan` | Local domain; clients resolve as `HOST.NAME`. |
| `--record NAME=IP` | | Local DNS record. |
| `--block DOMAIN` | | Block a domain and its subdomains. |
| `--blocklist-url URL` | | Hosts-format, plain domain list or adblock `\|\|domain^` list, downloaded at start. |
| `--blocklist-file FILE` | | Same, from a local file. |
| `--log-queries` | off | Log every query and DHCP event (for `logs`/`top`). |
| `--force-dns` | off | Redirect all LAN DNS traffic (port 53) to the router. |
| `--cache-size N` | `1000` | DNS cache entries. |
| `--no-dns` | | Don't run DNS; clients get the upstream servers via DHCP. |

### Firewall / security

| Option | Description |
|---|---|
| `--sandbox` | Shortcut for `--isolate-host --block-private --block-dot --force-dns --log-queries`. |
| `--isolate-host` | Clients can reach this machine only for DHCP/DNS (and TFTP/proxy when enabled). |
| `--block-private` | Clients get Internet only: no RFC1918, CGNAT, link-local, or other local interfaces (Docker, VPN…). |
| `--block-dot` | Block DNS-over-TLS / DNS-over-QUIC (port 853) so clients fall back to the router's DNS. |
| `--block-mac MAC` | Deny a device DHCP and all traffic. |
| `--forward SPEC` | Port forward `tcp\|udp:WAN_PORT:LAN_IP[:LAN_PORT]` from the WAN side. |
| `--proxy PORT` | Transparently redirect client web traffic to a local proxy port. |
| `--proxy-ports LIST` | Ports redirected to the proxy (default `80,443`). |

### Shaping, Wi-Fi, hooks

| Option | Description |
|---|---|
| `--rate-down RATE`, `--rate-up RATE` | Cap total LAN download / upload (`512kbit`, `20mbit`, …). |
| `--ssid NAME` | Run an access point on the LAN interface (must be a Wi-Fi card). |
| `--passphrase PSK` | WPA2 passphrase, 8–63 characters. Empty = open network. |
| `--band g\|a`, `--channel N`, `--country CC`, `--hidden` | AP radio settings (defaults: `g`, 6 or 36, `US`, visible). |
| `--post-up CMD`, `--pre-down CMD` | Shell commands run as root after start / before stop. |
| `--capture-dir DIR` | Where pcaps and saved DNS logs go (default `/var/tmp/chokepoint`). |

## Profiles (YAML)

Profiles let you keep several setups and switch between them without editing the script.

### Where profiles live

`-p NAME` looks for `NAME.yml` / `NAME.yaml` in, in order:

1. `$CHOKEPOINT_PROFILES` (if set)
2. `~/.config/chokepoint/profiles/` — your own profiles
3. `/etc/chokepoint/profiles/` — system-wide profiles
4. `/usr/local/share/chokepoint/profiles/` (after `make install`) or `profiles/` next to the script — bundled examples

Earlier directories win, so copy a bundled profile to `~/.config/chokepoint/profiles/` to customize it.

`-p` also accepts a path to any file. Running `start` with no profile and no `--lan` uses the profile named `default`.

### Precedence

```
CLI flags  >  CP_<KEY> environment variables  >  profiles (-p, later wins)  >  built-in defaults
```

- List flags (`--reserve`, `--record`, `--block`, `--forward`, `--dns`, …) **append** to the profile's list.
- Any key can be set from the CLI with `--set`, or from the environment with `CP_<KEY>`
  (e.g. `CP_WIFI_PASSPHRASE`). Env vars are passed through `sudo` automatically.

### Example profile

```yaml
description: "Sandbox for untrusted IoT devices: Internet only, full DNS logging"
lan: eth1
wan: auto
address: 10.66.0.1/24

dhcp:
  lease: 1h
  reservations:
    - "aa:bb:cc:dd:ee:ff,10.66.0.50,camera"

dns:
  upstream: [9.9.9.9, 149.112.112.112]
  log_queries: true
  force: true
  block_domains: [telemetry.example.com]

firewall:
  isolate_host: true
  block_private: true
  block_dot: true

shaping:
  download: 5mbit
  upload: 2mbit
```

> Quote MAC addresses and anything containing `:` in YAML.

### Creating profiles

```bash
# Commented profile with your options baked in → ~/.config/chokepoint/profiles/lab.yml
chokepoint init lab --lan eth1 -a 10.20.0.1/24 --log-queries

# Export the effective config (profile + flags) or the running config
chokepoint config -p lab --rate-down 5mbit > lab-slow.yml
sudo chokepoint config running > snapshot.yml
```

### Bundled profiles

| Profile | Purpose |
|---|---|
| `default` | Share the default upstream with `eth1`. Used when `start` gets no profile or `--lan` — copy and adapt it. |
| `iot-lab` | Sandbox for untrusted devices: isolated, Internet-only, DNS logged and forced, throttled. |
| `mitm` | Transparent redirect of HTTP/HTTPS to a proxy on `:8080`. |
| `hotspot` | Wi-Fi access point with an ad-blocking blocklist. |
| `pxe` | PXE/TFTP boot server. |
| `lab` | Infra lab: static leases, local DNS names, NTP option, port forwards. |

### All keys

Run `chokepoint help config` for the full table. Summary:

| YAML path | Type | Default |
|---|---|---|
| `name`, `description` | str | profile file name / — |
| `lan`, `wan`, `address` | str | — / `auto` / `192.168.50.1/24` |
| `dhcp.enabled`, `dhcp.range`, `dhcp.lease` | bool / str / str | `true` / auto / `12h` |
| `dhcp.reservations`, `dhcp.options` | list | |
| `dhcp.pxe.tftp_root`, `dhcp.pxe.boot_file` | str | |
| `dns.enabled`, `dns.upstream`, `dns.domain`, `dns.cache_size` | bool / list / str / int | `true` / `1.1.1.1,9.9.9.9` / `lan` / `1000` |
| `dns.log_queries`, `dns.force` | bool | `false` |
| `dns.records`, `dns.block_domains`, `dns.blocklist_urls`, `dns.blocklist_files` | list | |
| `firewall.isolate_host`, `firewall.block_private`, `firewall.block_dot` | bool | `false` |
| `firewall.block_macs`, `firewall.port_forwards` | list | |
| `firewall.transparent_proxy`, `firewall.proxy_ports` | int / str | — / `80,443` |
| `shaping.download`, `shaping.upload` | str | |
| `wifi.ssid`, `wifi.passphrase`, `wifi.band`, `wifi.channel`, `wifi.country`, `wifi.hidden` | | — / — / `g` / 6 or 36 / `US` / `false` |
| `capture.dir` | str | `/var/tmp/chokepoint` |
| `hooks.post_up`, `hooks.pre_down` | str | |

## Scenarios

`chokepoint help examples` prints the full cookbook. Highlights:

**Give a wired device Internet through your laptop's Wi-Fi**
```bash
sudo chokepoint start --lan eth1
```

**IoT / malware sandbox — watch everything a device does**
```bash
sudo chokepoint start --lan eth1 --name iot --sandbox --rate-down 2mbit
sudo chokepoint logs -f        # every DNS lookup
sudo chokepoint capture        # full pcap
sudo chokepoint top            # most contacted / blocked domains
```

**Intercept a device's HTTP(S) with mitmproxy or Burp**
```bash
mitmproxy --mode transparent --showhost -p 8080 &
sudo chokepoint start --lan eth1 --proxy 8080 --block-dot --force-dns
# install the proxy's CA certificate on the device
```

**Instant Wi-Fi access point**
```bash
sudo chokepoint start --lan wlx00c0ca --ssid TestNet --passphrase 'changeme123'
sudo chokepoint client block 192.168.50.23     # kick + ban a device
```

**PXE boot server**
```bash
sudo chokepoint start --lan eth1 --tftp-root /srv/tftp --boot-file pxelinux.0
```

**Lab network with fixed IPs and names**
```bash
sudo chokepoint start --lan eth1 -a 10.20.0.1/24 --domain lab \
     --reserve aa:bb:cc:dd:ee:01,10.20.0.10,switch --record nas=10.20.0.5
sudo chokepoint dns add grafana 10.20.0.11      # grafana.lab resolves immediately
```

**Ad / tracker blocking and parental control**
```bash
sudo chokepoint start --lan eth1 --force-dns --block-dot \
     --blocklist-url https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts \
     --block tiktok.com
```

**Route a device through your VPN**
```bash
sudo chokepoint start --lan eth1 --wan tun0 --dns 10.8.0.1 --block-private
```

**Simulate a slow link (plus latency/loss via a hook)**
```bash
sudo chokepoint start --lan eth1 --rate-down 1mbit --rate-up 256kbit \
     --post-up 'tc qdisc add dev $CP_LAN parent 1:10 netem delay 200ms loss 2%'
```

**Expose a device's service to the outside network**
```bash
sudo chokepoint start --lan eth1 --forward tcp:8443:192.168.50.20:443 \
     --reserve 11:22:33:44:55:66,192.168.50.20
```

**Devices with static IP configuration**

DHCP is optional. Configure the device with an IP in the LAN subnet **outside the DHCP pool**, gateway and DNS =
the router address (e.g. `192.168.50.1`). Add a name for it with `dns add NAME IP`. With `--force-dns`, the device's
DNS queries are answered by the router whatever DNS server it is configured with.

### Hooks

Hooks run as root through `bash -c` with these environment variables:

| Variable | Value |
|---|---|
| `CP_NAME` | Instance name |
| `CP_LAN`, `CP_WAN` | Interfaces |
| `CP_GW`, `CP_NET` | Router address, LAN subnet |
| `CP_STATE` | State directory (`/run/chokepoint/<name>`) |

## How it works

On `start` the script:

1. Validates the config: interfaces exist, LAN ≠ WAN, LAN doesn't carry your default route, and the LAN subnet
   doesn't overlap an address **or route** on another interface.
2. Tells NetworkManager to leave the LAN interface alone (runtime only), assigns the router address, enables
   `net.ipv4.ip_forward`.
3. Loads one nftables table, `ip chokepoint_<name>`, with filter/NAT chains, a `blocked_macs` set and a
   `port_forwards` chain.
4. Inserts a few `iptables` ACCEPT rules into `DOCKER-USER` (if Docker is present) or `FORWARD`, and `INPUT`, so
   Docker's or UFW's DROP policies don't block routed traffic.
5. Optionally applies `tc` shaping and starts `hostapd`.
6. Starts a dedicated `dnsmasq` bound only to the LAN interface.

All state lives in `/run/chokepoint/<name>/` (tmpfs: gone after reboot). Live-management commands edit files there
and send `SIGHUP` to dnsmasq, or update the nftables set/chain directly.

`stop` reverses every step: kills its processes, deletes its table and iptables rules, removes shaping, flushes the
LAN address, hands the interface back to NetworkManager, and restores `ip_forward` if it was off and nothing else
(another instance, Docker) needs it. If `start` fails half-way, it rolls back automatically.

Inspect the live firewall with:

```bash
sudo nft list table ip chokepoint_default
```

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| **Client gets an IP but can't reach the Internet; laptop can't ping the client** | A **VPN** (or another interface) routes the same subnet, so replies go into the tunnel. `ip route get <client-ip>` shows `dev tun0`. Pick another `--address`. `start` refuses this case, but a VPN that connects or reconnects *after* the router is up can re-introduce it. |
| `LAN subnet … overlaps …` | As above, or the LAN subnet equals your Wi-Fi network. Choose another subnet (`10.66.0.1/24`, `192.168.169.1/24`, …). |
| `… currently carries your default route` | You picked your Internet interface as LAN. Use the other one (see `check`). |
| `dnsmasq: failed to create listening socket … Address already in use` | Another DNS/DHCP server listens on all interfaces (system `dnsmasq`, `bind9`…). Stop it, or configure it to bind specific interfaces. `systemd-resolved` (127.0.0.53) does not conflict. |
| Client gets no DHCP lease | Check `logs` with `--log-queries`, cable/link (`ip -br link`), and that the MAC isn't blocked (`client list`). |
| Internet works but some sites/apps don't | Check `top` for blocked domains; a blocklist may be too aggressive (`block del` only covers `--block` entries — restart without the blocklist). |
| Transparent proxy shows TLS errors | Expected until the proxy's CA is trusted on the device; apps with certificate pinning will still refuse. |
| Wi-Fi AP doesn't start | Card must support AP mode (`iw list` → "Supported interface modes: AP") and must not be your active Wi-Fi connection. See `/run/chokepoint/<name>/hostapd.log`. |
| Something looks wrong | Run the same `start` with `--dry-run` to see exactly what is configured, and `status` to see what is running. |

Only IPv4 is routed. Clients won't get IPv6 connectivity through the router.

## Security notes

- The script must run as root; it re-executes itself through `sudo` for commands that need it.
- **Hooks run as root.** Only use profiles you trust.
- Avoid `--passphrase` on the command line (visible in `ps` and shell history). Put it in a profile with
  `chmod 600`, or use `CP_WIFI_PASSPHRASE=… chokepoint start -p hotspot`. Generated `hostapd.conf` and
  `init` profiles are created with mode `600`; `config` masks the passphrase when printing to a terminal.
- Don't pick a subnet outside the private ranges (e.g. `192.169.x.x`) — you'd shadow real Internet addresses. The
  script warns about this.
- `--sandbox` limits what a device can reach, but it is not a substitute for a dedicated, air-gapped malware lab.
- Transparent proxying, traffic capture, access points and scanning are for networks and devices you own or are
  explicitly authorized to test.

## Contributing

Issues and pull requests are welcome. Before submitting a change:

```bash
bash -n chokepoint                       # syntax check
shellcheck chokepoint                    # lint (if installed)
chokepoint start --lan <iface> --dry-run # review the generated commands and nftables ruleset
```

## License

[MIT](LICENSE) © 2026 Arttacker
