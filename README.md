<p align="center">
  <img src="https://img.shields.io/badge/version-2.0--PCI-brightgreen" alt="Version">
  <img src="https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20WSL%20%7C%20Cygwin-blue" alt="Platform">
  <img src="https://img.shields.io/badge/license-MIT-yellow" alt="License">
  <img src="https://img.shields.io/badge/nmap-required-red" alt="Nmap Required">
</p>

<h1 align="center">nmapauto</h1>
<p align="center"><b>Automated Network Security Scanner & PCI Segmentation Tester</b></p>
<p align="center">A modernized, all-in-one nmap automation tool for penetration testing, vulnerability assessment, PCI DSS segmentation verification, and network reconnaissance.</p>

---

## What is nmapauto?

**nmapauto** is a comprehensive bash-based network security scanner that automates nmap scans with 12 scan types covering everything from quick port discovery to full penetration testing and PCI DSS compliance verification.

Originally inspired by [nmapAutomator](https://github.com/21y4d/nmapAutomator) by @21y4d, this is a complete rewrite with modern security checks, PCI segmentation testing, full pentest automation, and cross-platform support.

### Key Features

- **12 Scan Types** — Network, Port, Script, Full, UDP, Vulns, SSL, Firewall, PCI, Pentest, Recon, All
- **115+ NSE Scripts** — Automatically runs the right scripts based on discovered services
- **PCI DSS Compliance** — Dedicated segmentation verification with PASS/REVIEW/FAIL verdicts
- **Full Pentest Mode** — 7-phase penetration test (stealth, enum, auth, SSL, vulns, firewall, UDP)
- **Service-Aware** — Auto-detects HTTP, SMB, SSH, DNS, RDP, FTP, databases, SNMP, LDAP, VNC, and more
- **Cross-Platform** — Works on Kali, Ubuntu, Debian, CentOS, macOS, WSL, Cygwin, Git Bash
- **Batch Scanning** — Scan hundreds of IPs from a file with one command
- **Auto Reports** — Generates summary reports for PCI and Pentest scans
- **Progress Bar** — Real-time nmap progress tracking
- **Matrix Intro** — Fancy startup animation (auto-skipped in non-interactive mode)

---

## Quick Start

```bash
# Clone the repo
git clone https://github.com/YourUsername/nmapauto.git
cd nmapauto

# Make executable
chmod +x nmapauto.sh

# Run your first scan
./nmapauto.sh -H 192.168.1.1 -t Port

# See full help
./nmapauto.sh -h
```

### Optional: Install globally

```bash
sudo cp nmapauto.sh /usr/local/bin/nmapauto
sudo chmod +x /usr/local/bin/nmapauto

# Now use from anywhere
nmapauto -H 10.0.0.1 -t All
```

---

## Usage

```
nmapauto -H <target> -t <scan-type> [options]
```

### Required Arguments

| Flag | Description |
|------|-------------|
| `-H, --host` | Target IP address or hostname |
| `-t, --type` | Scan type (see Scan Types below) |

### Optional Arguments

| Flag | Description |
|------|-------------|
| `-d, --dns <server>` | Use custom DNS server |
| `-o, --output <dir>` | Custom output directory (default: target name) |
| `-s, --static-nmap <path>` | Path to static nmap binary |
| `-r, --remote` | Remote mode (limited scans, no local nmap) |
| `-y, --yes` | Auto-run all recon tools (skip interactive prompt) |
| `-h, --help` | Show full help with examples |

---

## Scan Types

| Type | Description | Time | Requires Root |
|------|-------------|------|---------------|
| `Network` | Discover live hosts on target's /24 subnet | ~15 sec | No |
| `Port` | Quick top-ports TCP scan | ~15 sec | No |
| `Script` | Version detection + default NSE scripts | ~5 min | No |
| `Full` | All 65535 TCP ports + scripts on new ports | ~5-10 min | No |
| `UDP` | Top 1000 UDP ports + version detection | ~5 min | Yes |
| `Vulns` | CVE scan + vulnerability scripts + auth checks | ~5-15 min | No |
| `SSL` | TLS/SSL ciphers, certs, vulnerabilities, deprecated protocols | ~3-5 min | No |
| `Firewall` | ACK scan, window scan, fragmentation, traceroute | ~5 min | Yes |
| `PCI` | PCI DSS segmentation verification (comprehensive) | ~15-30 min | Yes |
| `Pentest` | Full 7-phase penetration test | ~20-40 min | Yes |
| `Recon` | Auto-suggest & run recon tools per discovered service | ~10-20 min | No |
| `All` | Run every scan type sequentially | ~60-90 min | Yes |

---

## Examples

### Live Host Discovery

```bash
# Find all live hosts on a subnet
./nmapauto.sh -H 192.168.1.0 -t Network

# Discover live hosts across multiple subnets
for subnet in 10.0.1.0 10.0.2.0 10.0.3.0; do
    ./nmapauto.sh -H $subnet -t Network
done

# Extract live IPs from results
grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' 192.168.1.0/nmap/Network_*.nmap \
    | sort -u > live_hosts.txt
```

### Single Target Scans

```bash
# Quick port scan
./nmapauto.sh -H 192.168.1.1 -t Port

# Full 65535 port scan
./nmapauto.sh -H 10.0.0.5 -t Full

# Domain with custom DNS
./nmapauto.sh -H example.com -t Script -d 8.8.8.8

# SSL/TLS assessment
./nmapauto.sh -H 10.10.10.50 -t SSL

# Vulnerability scan
./nmapauto.sh -H 172.16.0.100 -t Vulns -o /tmp/vuln_results

# Full penetration test
./nmapauto.sh -H 10.0.1.25 -t Pentest

# PCI segmentation verification
./nmapauto.sh -H 10.0.2.1 -t PCI

# Firewall detection
./nmapauto.sh -H 10.0.3.1 -t Firewall

# Everything
./nmapauto.sh -H 192.168.1.100 -t All -y
```

### Batch Scanning (Multiple IPs)

```bash
# From IP list file
for ip in $(cat ip_list.txt); do
    ./nmapauto.sh -H $ip -t All -y
done

# PCI segmentation on all CDE-adjacent hosts
for ip in $(cat ip_list.txt); do
    ./nmapauto.sh -H $ip -t PCI -y
done

# Scan domains
while read -r domain; do
    ./nmapauto.sh -H "$domain" -t All -y
done < urls.txt

# Parallel batch scanning
while read -r ip; do
    ./nmapauto.sh -H "$ip" -t Pentest -y &
done < ip_list.txt
wait
```

### Live Host Discovery + Full Scan Workflow

```bash
# Step 1: Find live hosts
./nmapauto.sh -H 10.0.1.0 -t Network

# Step 2: Extract live IPs
grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' 10.0.1.0/nmap/Network_*.nmap \
    | sort -u > live_hosts.txt

# Step 3: Full scan on each live host
for ip in $(cat live_hosts.txt); do
    ./nmapauto.sh -H $ip -t All -y
done
```

---

## What Runs Per Scan Type

### Scans using ONLY nmap (no external tools needed)

| Scan Type | Nmap Techniques & NSE Scripts |
|-----------|-------------------------------|
| **Network** | `-sn` ping sweep |
| **Port** | Top ports TCP `-T4` |
| **Script** | `-sCV` version + default scripts |
| **Full** | `-p-` all 65535 ports |
| **UDP** | `-sU` top 1000 + `-sCVU` version |
| **Firewall** | `-sA` ACK, `-sW` Window, `-f` fragment, `-O` OS, `--traceroute`, `firewall-bypass`, `firewalk` |

### Vulns Scan

| Check | Tool | Required? |
|-------|------|-----------|
| Vuln NSE scripts | `nmap --script vuln` | Built-in |
| Auth checks | `nmap --script auth` | Built-in |
| Banner grab | `nmap --script banner` | Built-in |
| CVE database | `nmap --script vulners` | Optional (skips if missing) |
| Vulscan database | `nmap --script vulscan` | Optional (skips if missing) |

### SSL Scan

| Check | Tool | Required? |
|-------|------|-----------|
| Cipher enumeration | `nmap ssl-enum-ciphers` | Built-in |
| Certificate details | `nmap ssl-cert` | Built-in |
| Heartbleed | `nmap ssl-heartbleed` | Built-in |
| POODLE | `nmap ssl-poodle` | Built-in |
| CCS Injection | `nmap ssl-ccs-injection` | Built-in |
| Ticketbleed | `nmap tls-ticketbleed` | Built-in |
| DH params / LOGJAM | `nmap ssl-dh-params` | Built-in |
| Deprecated protocols | `nmap ssl-enum-ciphers` (SSLv2/3, TLS 1.0/1.1) | Built-in |
| Deep cipher analysis | `sslscan` | Optional (skips if missing) |
| Comprehensive audit | `testssl.sh` | Optional (skips if missing) |

### PCI Segmentation Scan (8 Sections)

| Section | What It Does |
|---------|-------------|
| 1 | Full TCP 65535 port scan with `--reason` |
| 2 | UDP top 1000 port scan |
| 3 | Service version detection on open ports |
| 4a | Database port check (MSSQL, MySQL, PostgreSQL, Oracle, MongoDB, Redis, etc.) |
| 4b | Admin/Management port check (SSH, RDP, VNC, WinRM, NFS, SMB, SNMP, LDAP, Kerberos) |
| 4c | Web/Application port check (HTTP/HTTPS variants) |
| 4d | Payment processing / POS port check |
| 5 | SSL/TLS assessment on open ports |
| 6 | Vulnerability scan + CVE detection |
| 7a | ICMP connectivity check |
| 7b | IP Protocol scan |
| 8 | OS & device fingerprinting |
| **Report** | **Auto-generated PASS/REVIEW/FAIL summary** |

### Pentest Scan (7 Phases)

| Phase | What It Does |
|-------|-------------|
| **1: Stealth** | SYN scan all 65535 ports, version intensity, OS fingerprint |
| **2: Enumeration** | Service-specific deep NSE scripts for HTTP (18 scripts), SMB (17 scripts), SSH, DNS (8 scripts), SNMP (7 scripts), LDAP, RDP, FTP (6 scripts), Telnet, MySQL (6 scripts), MSSQL (5 scripts), PostgreSQL, Oracle, MongoDB, Redis, NFS, VNC, IKE/IPSec |
| **3: Auth** | Anonymous access, default credentials, empty passwords |
| **4: SSL/TLS** | 8 SSL/TLS vulnerability checks |
| **5: Vulns** | `--script vuln` + vulners + vulscan + safe exploit scripts |
| **6: Firewall** | ACK scan, IP Protocol scan, traceroute |
| **7: UDP** | Top 200 UDP ports + version detection |
| **Report** | **Auto-generated penetration test summary** |

### Recon Scan (External Tools — Service-Dependent)

| Service Detected | Tools Used |
|-----------------|------------|
| HTTP/HTTPS | `nikto`, `sslscan`, `ffuf`/`gobuster`/`feroxbuster`, `nuclei`, `whatweb` |
| CMS (WordPress) | `wpscan` |
| CMS (Joomla) | `joomscan` |
| CMS (Drupal) | `droopescan` |
| SMB (445/139) | `smbmap`, `smbclient`, `crackmapexec`, `enum4linux`/`enum4linux-ng` |
| SMTP (25) | `smtp-user-enum`, nmap SMTP scripts |
| DNS (53) | `host`, `dnsrecon`, `dig` (incl. AXFR) |
| SNMP (161) | `snmp-check`, `snmpwalk`, `onesixtyone` |
| LDAP (389) | `ldapsearch`, nmap LDAP scripts |
| SSH (22) | `ssh-audit`, nmap SSH scripts |
| FTP (21) | nmap FTP scripts |
| RDP (3389) | nmap RDP scripts |
| Oracle (1521) | `odat` |
| MySQL (3306) | nmap MySQL scripts |
| MSSQL (1433) | nmap MSSQL scripts |
| Redis (6379) | nmap Redis scripts |
| NFS (2049) | `showmount`, nmap NFS scripts |
| VNC (5900) | nmap VNC scripts |
| Telnet (23) | nmap Telnet scripts |

> Missing tools are auto-detected and listed with install instructions. They are skipped gracefully — never causes errors.

---

## Output Structure

```
<target>/
├── nmapauto_<target>_<type>.txt    # Full scan log
├── nmap/
│   ├── Port_<target>.nmap           # Port scan results
│   ├── Script_<target>.nmap         # Script scan results
│   ├── Full_<target>.nmap           # Full port scan
│   ├── UDP_<target>.nmap            # UDP scan
│   ├── CVEs_<target>.nmap           # CVE/vulners results
│   ├── Vulns_<target>.nmap          # Vulnerability scan
│   ├── Auth_<target>.nmap           # Auth checks
│   ├── Banners_<target>.nmap        # Banner grab
│   ├── Recon_<target>.nmap          # Recon recommendations
│   ├── ssl/
│   │   ├── SSL_Ciphers_<target>.nmap
│   │   ├── SSL_Cert_<target>.nmap
│   │   ├── SSL_Vulns_<target>.nmap
│   │   └── ...
│   ├── firewall/
│   │   ├── ACK_Scan_<target>.nmap
│   │   ├── Window_Scan_<target>.nmap
│   │   ├── Fragment_<target>.nmap
│   │   └── ...
│   ├── pci/
│   │   ├── PCI_FullTCP_<target>.nmap
│   │   ├── PCI_UDP_<target>.nmap
│   │   ├── PCI_DB_Ports_<target>.nmap
│   │   ├── PCI_Admin_Ports_<target>.nmap
│   │   ├── PCI_SSL_<target>.nmap
│   │   ├── PCI_Summary_<target>.txt    # <-- PCI report
│   │   └── ...
│   └── pentest/
│       ├── PT_SYN_<target>.nmap
│       ├── PT_Versions_<target>.nmap
│       ├── PT_HTTP_Enum_<target>.nmap
│       ├── PT_SMB_Enum_<target>.nmap
│       ├── PT_SSL_<target>.nmap
│       ├── PT_Vulns_<target>.nmap
│       ├── PT_Summary_<target>.txt     # <-- Pentest report
│       └── ...
└── recon/
    ├── nikto_<target>_<port>.txt
    ├── ffuf_<target>_<port>.txt
    ├── smbmap_<target>.txt
    └── ...
```

---

## Requirements

### Required

| Tool | Version | Install |
|------|---------|---------|
| **nmap** | 7.80+ | `sudo apt install nmap` |
| **bash** | 4.0+ | Pre-installed on all supported platforms |

### Optional (auto-detected, gracefully skipped if missing)

| Tool | Used For | Install |
|------|----------|---------|
| vulners.nse | CVE scanning | `sudo nmap --script-updatedb` or [manual install](https://github.com/vulnersCom/nmap-vulners) |
| vulscan | CVE database scan | [github.com/scipag/vulscan](https://github.com/scipag/vulscan) |
| sslscan | Deep SSL/TLS analysis | `sudo apt install sslscan` |
| testssl.sh | Comprehensive TLS audit | `sudo apt install testssl.sh` |
| nikto | Web server scanner | `sudo apt install nikto` |
| ffuf | Web directory fuzzing | `sudo apt install ffuf` |
| gobuster | Web directory brute-force | `sudo apt install gobuster` |
| feroxbuster | Web content discovery | `sudo apt install feroxbuster` |
| nuclei | Template-based vuln scanner | [github.com/projectdiscovery/nuclei](https://github.com/projectdiscovery/nuclei) |
| whatweb | Web technology fingerprint | `sudo apt install whatweb` |
| enum4linux | SMB/NetBIOS enumeration | `sudo apt install enum4linux` |
| smbmap | SMB share enumeration | `sudo apt install smbmap` |
| smbclient | SMB client | `sudo apt install smbclient` |
| crackmapexec | SMB/WinRM/LDAP tool | `sudo apt install crackmapexec` |
| ssh-audit | SSH config auditing | `sudo apt install ssh-audit` |
| snmp-check | SNMP enumeration | `sudo apt install snmp-check` |
| snmpwalk | SNMP tree walk | `sudo apt install snmp` |
| onesixtyone | SNMP community brute | `sudo apt install onesixtyone` |
| ldapsearch | LDAP queries | `sudo apt install ldap-utils` |
| dnsrecon | DNS enumeration | `sudo apt install dnsrecon` |
| dig | DNS lookups | `sudo apt install dnsutils` |
| smtp-user-enum | SMTP user enumeration | `sudo apt install smtp-user-enum` |
| odat | Oracle DB attacking tool | [github.com/quentinhardy/odat](https://github.com/quentinhardy/odat) |
| wpscan | WordPress scanner | `sudo apt install wpscan` |
| joomscan | Joomla scanner | `sudo apt install joomscan` |
| droopescan | Drupal scanner | `pip install droopescan` |
| showmount | NFS share listing | `sudo apt install nfs-common` |

### Quick Install All Optional Tools (Kali/Ubuntu/Debian)

```bash
sudo apt update && sudo apt install -y \
    sslscan testssl.sh nikto ffuf gobuster feroxbuster whatweb \
    enum4linux smbmap smbclient crackmapexec ssh-audit \
    snmp-check snmp onesixtyone ldap-utils dnsrecon dnsutils \
    smtp-user-enum wpscan joomscan nfs-common
```

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| Kali Linux | Fully supported | Most optional tools pre-installed |
| Ubuntu / Debian | Fully supported | Install nmap + optional tools |
| CentOS / RHEL / Fedora | Fully supported | Use `yum`/`dnf` instead of `apt` |
| macOS | Fully supported | Install nmap via `brew install nmap` |
| WSL (Windows) | Fully supported | Runs natively in WSL terminal |
| Cygwin | Supported | sudo auto-disabled, some scans limited |
| Git Bash (Windows) | Supported | sudo auto-disabled, some scans limited |

---

## Input File Formats

**ip_list.txt** — one IP per line:
```
192.168.1.1
10.0.0.5
172.16.5.100
10.0.2.50
```

**urls.txt** — one domain per line:
```
example.com
app.internal.corp
staging.example.org
```

---

## PCI DSS Compliance Notes

This tool supports **PCI DSS Requirement 11.3.4 / 11.4.5** (segmentation penetration testing):

- Scans all 65535 TCP ports and top 1000 UDP ports
- Checks for database, admin, web, and payment processing ports across segments
- Validates SSL/TLS configurations
- Tests ICMP and IP protocol connectivity
- Generates a summary report with **PASS / REVIEW / FAIL** verdict

> **Note:** This automated scan supplements but does not replace manual penetration testing required by PCI DSS.

---

## Credits

- Original [nmapAutomator](https://github.com/21y4d/nmapAutomator) by [@21y4d](https://github.com/21y4d)
- Modernized and expanded by [Neev]

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---

## Disclaimer

This tool is intended for **authorized security testing only**. Always obtain proper authorization before scanning any network or system. Unauthorized scanning is illegal and unethical. The authors are not responsible for any misuse of this tool.
