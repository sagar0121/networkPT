#!/bin/bash
# nmapauto v2.0 — Network Security & PCI Segmentation Scanner
# Original nmapAutomator by @21y4d | Modernized 2026 for PT & PCI DSS
#
# Usage: nmapauto -H <target> -t <type>    |    nmapauto -h  (full help)
# Types: Network, Port, Script, Full, UDP, Vulns, SSL, Firewall, PCI, Pentest, Recon, All

# ═══════════════════════════════════════════════════════════════════
# ANSI Colors & Globals
# ═══════════════════════════════════════════════════════════════════
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'
origIFS="${IFS}"
NEWLINE='
'

elapsedStart="$(date '+%s')"
REMOTE=false
SKIP_RECON_PROMPT=false
VERSION="2.0-PCI"

# ═══════════════════════════════════════════════════════════════════
# Platform Detection (Linux, macOS, WSL, Cygwin, MinGW/Git Bash)
# ═══════════════════════════════════════════════════════════════════
PLATFORM="$(uname -s)"
case "${PLATFORM}" in
    Linux*)
        if grep -qi microsoft /proc/version 2>/dev/null; then
            OSENV="WSL"
        else
            OSENV="Linux"
        fi
        ;;
    Darwin*)  OSENV="macOS" ;;
    CYGWIN*)  OSENV="Cygwin" ;;
    MINGW*|MSYS*) OSENV="GitBash" ;;
    *)        OSENV="Unknown" ;;
esac

# On Cygwin/MinGW, sudo is not available — skip sudo prefix
if [ "${OSENV}" = "Cygwin" ] || [ "${OSENV}" = "GitBash" ]; then
    SUDO_CMD=""
    printf "${YELLOW}Detected ${OSENV} — sudo not available, running scans without elevation.${NC}\n"
    printf "${YELLOW}Some scans (UDP, ACK, OS detect) may require Administrator privileges.${NC}\n\n"
elif [ "$(id -u 2>/dev/null)" = "0" ]; then
    SUDO_CMD=""
else
    SUDO_CMD="sudo"
fi

# ═══════════════════════════════════════════════════════════════════
# Matrix Rain Intro (fancy startup animation)
# ═══════════════════════════════════════════════════════════════════
matrixIntro() {
    # Get terminal dimensions
    cols="$(tput cols 2>/dev/null || echo 80)"
    rows="$(tput lines 2>/dev/null || echo 24)"
    [ "${cols}" -lt 20 ] 2>/dev/null && cols=80
    [ "${rows}" -lt 5 ] 2>/dev/null && rows=24

    # Matrix characters
    matrixChars="0123456789ABCDEFabcdef@#%&*!<>{}[]|/\\~"
    green='\033[0;32m'
    bright='\033[1;32m'
    dim='\033[2;32m'
    nc='\033[0m'

    # Clear screen and hide cursor
    printf '\033[?25l'
    clear 2>/dev/null || printf '\033[2J\033[H'

    # Run matrix rain for ~2 seconds
    frame=0
    maxFrames=15
    while [ ${frame} -lt ${maxFrames} ]; do
        col=1
        while [ ${col} -le ${cols} ]; do
            # Random chance to print a character at this column
            randVal=$(($(od -An -N1 -tu1 /dev/urandom 2>/dev/null || echo 128) % 100))
            if [ ${randVal} -lt 35 ]; then
                randChar=$(($(od -An -N1 -tu1 /dev/urandom 2>/dev/null || echo 65) % ${#matrixChars}))
                char="$(echo "${matrixChars}" | cut -c$((randChar + 1)))"
                randRow=$(($(od -An -N1 -tu1 /dev/urandom 2>/dev/null || echo 10) % rows + 1))
                if [ $((randVal % 3)) -eq 0 ]; then
                    printf "\033[${randRow};${col}H${bright}${char}"
                elif [ $((randVal % 3)) -eq 1 ]; then
                    printf "\033[${randRow};${col}H${green}${char}"
                else
                    printf "\033[${randRow};${col}H${dim}${char}"
                fi
            fi
            col=$((col + 3))
        done
        sleep 0.1 2>/dev/null || sleep 1
        frame=$((frame + 1))
    done

    # Clear and show the banner
    clear 2>/dev/null || printf '\033[2J\033[H'
    printf "${nc}"

    # ASCII art banner
    printf "${bright}"
    cat << 'BANNER'

    ███╗   ██╗███████╗███████╗██╗   ██╗
    ████╗  ██║██╔════╝██╔════╝██║   ██║
    ██╔██╗ ██║█████╗  █████╗  ██║   ██║
    ██║╚██╗██║██╔══╝  ██╔══╝  ╚██╗ ██╔╝
    ██║ ╚████║███████╗███████╗ ╚████╔╝
    ╚═╝  ╚═══╝╚══════╝╚══════╝  ╚═══╝

BANNER
    printf "${green}"
    printf "    nmapauto ${VERSION} | Network Security & PCI Scanner\n"
    printf "    ────────────────────────────────────────────────────────\n"
    printf "    Platform: ${OSENV} | $(date '+%Y-%m-%d %H:%M:%S')\n"
    printf "${nc}\n"

    # Show cursor again
    printf '\033[?25h'
}

# Run matrix intro (skip if piped or non-interactive)
if [ -t 1 ]; then
    matrixIntro
fi

# ═══════════════════════════════════════════════════════════════════
# Argument Parsing
# ═══════════════════════════════════════════════════════════════════
while [ $# -gt 0 ]; do
    key="$1"
    case "${key}" in
        -H|--host)      HOST="$2"; shift; shift ;;
        -t|--type)      TYPE="$2"; shift; shift ;;
        -d|--dns)       DNS="$2"; shift; shift ;;
        -o|--output)    OUTPUTDIR="$2"; shift; shift ;;
        -s|--static-nmap) NMAPPATH="$2"; shift; shift ;;
        -r|--remote)    REMOTE=true; shift ;;
        -y|--yes)       SKIP_RECON_PROMPT=true; shift ;;
        -h|--help)      SHOW_HELP=true; shift ;;
        *)              POSITIONAL="${POSITIONAL} $1"; shift ;;
    esac
done
set -- ${POSITIONAL}

# Legacy positional args
[ -z "${HOST}" ] && HOST="$1"
[ -z "${TYPE}" ] && TYPE="$2"

# Legacy type aliases
case "${TYPE}" in
    [Qq]uick) TYPE="Port" ;;
    [Bb]asic) TYPE="Script" ;;
esac

# DNS config
if [ -n "${DNS}" ]; then
    DNSSERVER="${DNS}"
    DNSSTRING="--dns-server=${DNSSERVER}"
else
    DNSSERVER="$(grep 'nameserver' /etc/resolv.conf 2>/dev/null | grep -v '#' | head -n 1 | awk '{print $NF}')"
    DNSSTRING="--system-dns"
fi

# Output dir
[ -z "${OUTPUTDIR}" ] && OUTPUTDIR="${HOST}"

# Nmap binary detection
if [ -z "${NMAPPATH}" ] && type nmap >/dev/null 2>&1; then
    NMAPPATH="$(command -v nmap)"
elif [ -n "${NMAPPATH}" ]; then
    NMAPPATH="$(cd "$(dirname "${NMAPPATH}")" && pwd -P)/$(basename "${NMAPPATH}")"
    if [ ! -x "$NMAPPATH" ]; then
        printf "${RED}File is not executable! Attempting chmod +x...${NC}\n"
        chmod +x "$NMAPPATH" 2>/dev/null || { printf "${RED}Could not chmod. Running in Remote mode...${NC}\n\n"; REMOTE=true; }
    elif [ "$($NMAPPATH -h 2>/dev/null | head -c4)" != "Nmap" ]; then
        printf "${RED}Static binary does not appear to be Nmap! Running in Remote mode...${NC}\n\n"
        REMOTE=true
    fi
    printf "${GREEN}Using static nmap binary at ${NMAPPATH}${NC}\n"
else
    printf "${RED}Nmap is not installed and -s is not used. Running in Remote mode...${NC}\n\n"
    REMOTE=true
fi

# ═══════════════════════════════════════════════════════════════════
# Usage / Help
# ═══════════════════════════════════════════════════════════════════
usage() {
    echo
    printf "${BOLD}${GREEN}nmapauto ${VERSION}${NC} — Network Security & PCI Segmentation Scanner\n"
    printf "${GREEN}═══════════════════════════════════════════════════════════════${NC}\n\n"

    printf "${BOLD}USAGE:${NC}\n"
    printf "  nmapauto -H <target> -t <scan-type> [options]\n\n"

    printf "${BOLD}REQUIRED:${NC}\n"
    printf "  ${YELLOW}-H, --host ${NC}<IP|DOMAIN>     Target IP address or hostname\n"
    printf "  ${YELLOW}-t, --type ${NC}<TYPE>           Scan type (see below)\n\n"

    printf "${BOLD}OPTIONS:${NC}\n"
    printf "  ${YELLOW}-d, --dns ${NC}<DNS-SERVER>      Use custom DNS server\n"
    printf "  ${YELLOW}-o, --output ${NC}<DIRECTORY>    Custom output directory (default: target name)\n"
    printf "  ${YELLOW}-s, --static-nmap ${NC}<PATH>    Path to static nmap binary\n"
    printf "  ${YELLOW}-r, --remote${NC}                Remote mode (limited scans, no local nmap)\n"
    printf "  ${YELLOW}-y, --yes${NC}                   Auto-run all recon tools (skip prompt)\n"
    printf "  ${YELLOW}-h, --help${NC}                  Show this help message\n\n"

    printf "${BOLD}SCAN TYPES:${NC}\n"
    printf "  ${YELLOW}Network ${NC}  Discover live hosts on the target's /24 subnet          ${CYAN}~15 sec${NC}\n"
    printf "  ${YELLOW}Port    ${NC}  Quick top-ports TCP scan                                 ${CYAN}~15 sec${NC}\n"
    printf "  ${YELLOW}Script  ${NC}  Version detection + default NSE scripts on found ports   ${CYAN}~5 min${NC}\n"
    printf "  ${YELLOW}Full    ${NC}  All 65535 TCP ports, then scripts on new ports            ${CYAN}~5-10 min${NC}\n"
    printf "  ${YELLOW}UDP     ${NC}  Top 1000 UDP ports + version detection (requires root)   ${CYAN}~5 min${NC}\n"
    printf "  ${YELLOW}Vulns   ${NC}  CVE (vulners/vulscan) + vuln NSE scripts + auth checks   ${CYAN}~5-15 min${NC}\n"
    printf "  ${YELLOW}SSL     ${NC}  TLS/SSL ciphers, certs, Heartbleed, POODLE, deprecated   ${CYAN}~3-5 min${NC}\n"
    printf "  ${YELLOW}Firewall${NC}  ACK scan, window scan, fragmentation, traceroute         ${CYAN}~5 min${NC}\n"
    printf "  ${YELLOW}PCI     ${NC}  PCI DSS segmentation verification (all ports + report)   ${CYAN}~15-30 min${NC}\n"
    printf "  ${YELLOW}Pentest ${NC}  Full 7-phase pentest (stealth, enum, vulns, auth, FW)    ${CYAN}~20-40 min${NC}\n"
    printf "  ${YELLOW}Recon   ${NC}  Auto-suggest & run recon tools per discovered service    ${CYAN}~10-20 min${NC}\n"
    printf "  ${YELLOW}All     ${NC}  Run every scan type above sequentially                   ${CYAN}~60-90 min${NC}\n\n"

    printf "${BOLD}EXAMPLES:${NC}\n\n"

    printf "  ${BOLD}${GREEN}--- Live Host Discovery ---${NC}\n\n"

    printf "  ${CYAN}# Find all live hosts on a /24 subnet${NC}\n"
    printf "  nmapauto -H 192.168.1.0 -t Network\n\n"

    printf "  ${CYAN}# Find live hosts on a different subnet${NC}\n"
    printf "  nmapauto -H 10.0.2.0 -t Network\n\n"

    printf "  ${CYAN}# Batch — discover live hosts across multiple subnets${NC}\n"
    printf "  for subnet in 10.0.1.0 10.0.2.0 10.0.3.0 172.16.0.0; do\n"
    printf "      nmapauto -H \$subnet -t Network\n"
    printf "  done\n\n"

    printf "  ${CYAN}# Extract just the live IPs from results${NC}\n"
    printf "  grep 'Host is up' 10.0.1.0/nmap/Network_10.0.1.0.nmap\n"
    printf "  ${CYAN}# Or:${NC}\n"
    printf "  grep -oP '\\d+\\.\\d+\\.\\d+\\.\\d+' 10.0.1.0/nmap/Network_10.0.1.0.nmap > live_hosts.txt\n\n"

    printf "  ${BOLD}${GREEN}--- Single Target Scans ---${NC}\n\n"

    printf "  ${CYAN}# Quick port scan${NC}\n"
    printf "  nmapauto -H 192.168.1.1 -t Port\n\n"

    printf "  ${CYAN}# Full scan with version detection${NC}\n"
    printf "  nmapauto -H 10.0.0.5 -t Full\n\n"

    printf "  ${CYAN}# Domain — script scan with custom DNS${NC}\n"
    printf "  nmapauto -H example.com -t Script -d 8.8.8.8\n\n"

    printf "  ${CYAN}# SSL/TLS check on a web server${NC}\n"
    printf "  nmapauto -H 10.10.10.50 -t SSL\n\n"

    printf "  ${CYAN}# Vulnerability scan with custom output dir${NC}\n"
    printf "  nmapauto -H 172.16.0.100 -t Vulns -o /tmp/vuln_results\n\n"

    printf "  ${CYAN}# Full penetration test scan${NC}\n"
    printf "  nmapauto -H 10.0.1.25 -t Pentest\n\n"

    printf "  ${CYAN}# PCI segmentation verification${NC}\n"
    printf "  nmapauto -H 10.0.2.1 -t PCI\n\n"

    printf "  ${CYAN}# Firewall / ACL detection${NC}\n"
    printf "  nmapauto -H 10.0.3.1 -t Firewall\n\n"

    printf "  ${CYAN}# Run ALL scans on a target${NC}\n"
    printf "  nmapauto -H 192.168.1.100 -t All\n\n"

    printf "  ${CYAN}# Run ALL scans, skip recon prompt (auto-yes)${NC}\n"
    printf "  nmapauto -H 192.168.1.100 -t All -y\n\n"

    printf "  ${BOLD}${GREEN}--- Batch Scanning (Multiple IPs) ---${NC}\n\n"

    printf "  ${CYAN}# Scan all IPs from a list${NC}\n"
    printf "  for ip in \$(cat ip_list.txt); do\n"
    printf "      nmapauto -H \$ip -t All -y\n"
    printf "  done\n\n"

    printf "  ${CYAN}# PCI segmentation on all CDE-adjacent hosts${NC}\n"
    printf "  for ip in \$(cat ip_list.txt); do\n"
    printf "      nmapauto -H \$ip -t PCI -y\n"
    printf "  done\n\n"

    printf "  ${CYAN}# Scan domains from a list${NC}\n"
    printf "  while read -r domain; do\n"
    printf "      nmapauto -H \"\$domain\" -t All -y\n"
    printf "  done < urls.txt\n\n"

    printf "  ${CYAN}# Parallel batch scanning (background jobs)${NC}\n"
    printf "  while read -r ip; do\n"
    printf "      nmapauto -H \"\$ip\" -t Pentest -y &\n"
    printf "  done < ip_list.txt\n"
    printf "  wait\n\n"

    printf "  ${BOLD}${GREEN}--- Live Host Discovery + Full Scan Workflow ---${NC}\n\n"

    printf "  ${CYAN}# Step 1: Find live hosts${NC}\n"
    printf "  nmapauto -H 10.0.1.0 -t Network\n\n"
    printf "  ${CYAN}# Step 2: Extract live IPs${NC}\n"
    printf "  grep -oE '[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+' 10.0.1.0/nmap/Network_*.nmap \\\\\n"
    printf "      | sort -u > live_hosts.txt\n\n"
    printf "  ${CYAN}# Step 3: Full scan on each live host${NC}\n"
    printf "  for ip in \$(cat live_hosts.txt); do\n"
    printf "      nmapauto -H \$ip -t All -y\n"
    printf "  done\n\n"

    printf "${BOLD}INPUT FILES FORMAT:${NC}\n\n"

    printf "  ${YELLOW}ip_list.txt${NC} — one IP or CIDR per line:\n"
    printf "      192.168.1.1\n"
    printf "      10.0.0.0/24\n"
    printf "      172.16.5.100\n\n"

    printf "  ${YELLOW}urls.txt${NC} — one domain per line:\n"
    printf "      example.com\n"
    printf "      app.internal.corp\n"
    printf "      staging.example.org\n\n"

    printf "${BOLD}OUTPUT:${NC}\n"
    printf "  Results are saved in ${YELLOW}./<target>/nmap/${NC} directory\n"
    printf "  PCI reports:    ${YELLOW}nmap/pci/PCI_Summary_<target>.txt${NC}\n"
    printf "  Pentest reports: ${YELLOW}nmap/pentest/PT_Summary_<target>.txt${NC}\n"
    printf "  Full log:       ${YELLOW}nmapauto_<target>_<type>.txt${NC}\n\n"

    printf "${BOLD}SUPPORTED PLATFORMS:${NC}\n"
    printf "  Kali Linux, Ubuntu/Debian, CentOS/RHEL, macOS, WSL, Cygwin, Git Bash\n\n"

    printf "${BOLD}REQUIREMENTS:${NC}\n"
    printf "  - nmap (required)\n"
    printf "  - sudo/root for UDP, ACK, OS detection, and fragmentation scans\n"
    printf "  - Optional: vulners.nse, vulscan, sslscan, testssl.sh, nuclei,\n"
    printf "    ffuf/gobuster/feroxbuster, nikto, enum4linux, ssh-audit, whatweb\n\n"

    printf "${GREEN}═══════════════════════════════════════════════════════════════${NC}\n"
    exit 1
}

# ═══════════════════════════════════════════════════════════════════
# Utility Functions
# ═══════════════════════════════════════════════════════════════════

# Cross-platform sed in-place edit (macOS needs -i '', Linux needs -i)
sedi() {
    if [ "${OSENV}" = "macOS" ]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# Assign discovered ports from scan files
assignPorts() {
    if [ -f "nmap/Port_$1.nmap" ]; then
        commonPorts="$(awk -vORS=, -F/ '/^[0-9]/{print $1}' "nmap/Port_$1.nmap" | sed 's/.$//')"
    fi
    if [ -f "nmap/Full_$1.nmap" ]; then
        if [ -f "nmap/Port_$1.nmap" ]; then
            allPorts="$(awk -vORS=, -F/ '/^[0-9]/{print $1}' "nmap/Port_$1.nmap" "nmap/Full_$1.nmap" | sed 's/.$//')"
        else
            allPorts="$(awk -vORS=, -F/ '/^[0-9]/{print $1}' "nmap/Full_$1.nmap" | sed 's/.$//')"
        fi
    fi
    if [ -f "nmap/UDP_$1.nmap" ]; then
        udpPorts="$(awk -vORS=, -F/ '/^[0-9]/{print $1}' "nmap/UDP_$1.nmap" | sed 's/.$//')"
        [ "${udpPorts}" = "Al" ] && udpPorts=""
    fi
}

# Check if host responds to ping, return nmap type and TTL
checkPing() {
    if [ "$(uname -s)" = "Linux" ]; then TW="W"; else TW="t"; fi
    pingTest="$(ping -c 1 -${TW} 1 "$1" 2>/dev/null | grep -i ttl)"
    if [ -z "${pingTest}" ]; then
        echo "${NMAPPATH} -Pn"
    else
        echo "${NMAPPATH}"
        # Extract TTL value — handles both "ttl=64" and "ttl 64" formats across Linux/macOS/BSDs
        ttl="$(echo "${pingTest}" | sed -n 's/.*[Tt][Tt][Ll][= ]*\([0-9]*\).*/\1/p' | head -1)"
        echo "${ttl}"
    fi
}

# OS detection from TTL
checkOS() {
    case "$1" in
        25[456])  echo "OpenBSD/Cisco/Oracle" ;;
        12[78])   echo "Windows" ;;
        6[34])    echo "Linux" ;;
        *)        echo "Unknown OS" ;;
    esac
}

# Compare port lists to find extras
cmpPorts() {
    extraPorts="$(echo ",${allPorts}," | sed 's/,\('"$(echo "${commonPorts}" | sed 's/,/,\\|/g')"',\)\+/,/g; s/^,\|,$//g')"
}

# Progress bar for nmap scans
progressBar() {
    [ -z "${2##*[!0-9]*}" ] && return 1
    termWidth="$(stty size 2>/dev/null | cut -d ' ' -f 2)"
    termWidth="${termWidth:-80}"
    [ "${termWidth}" -le 120 ] 2>/dev/null && width=50 || width=100
    fill="$(printf "%-$((width == 100 ? $2 : ($2 / 2)))s" "#" | tr ' ' '#')"
    empty="$(printf "%-$((width - (width == 100 ? $2 : ($2 / 2))))s" " ")"
    printf "In progress: $1 Scan ($3 elapsed - $4 remaining)   \n"
    printf "[${fill}>${empty}] $2%% done   \n"
    printf "\e[2A"
}

# Execute nmap with progress bar
nmapProgressBar() {
    refreshRate="${2:-1}"
    outputFile="$(echo $1 | sed -e 's/.*-oN \(.*\).nmap.*/\1/').nmap"
    tmpOutputFile="${outputFile}.tmp"

    if [ ! -e "${outputFile}" ]; then
        $1 --stats-every "${refreshRate}s" >"${tmpOutputFile}" 2>&1 &
    fi

    while { [ ! -e "${outputFile}" ] || ! grep -q "Nmap done at" "${outputFile}"; } && { [ ! -e "${tmpOutputFile}" ] || ! grep -i -q "quitting" "${tmpOutputFile}"; }; do
        scanType="$(tail -n 2 "${tmpOutputFile}" 2>/dev/null | sed -ne '/elapsed/{s/.*undergoing \(.*\) Scan.*/\1/p}')"
        percent="$(tail -n 2 "${tmpOutputFile}" 2>/dev/null | sed -ne '/% done/{s/.*About \(.*\)\..*% done.*/\1/p}')"
        elapsed="$(tail -n 2 "${tmpOutputFile}" 2>/dev/null | sed -ne '/elapsed/{s/Stats: \(.*\) elapsed.*/\1/p}')"
        remaining="$(tail -n 2 "${tmpOutputFile}" 2>/dev/null | sed -ne '/remaining/{s/.* (\(.*\) remaining.*/\1/p}')"
        progressBar "${scanType:-No}" "${percent:-0}" "${elapsed:-0:00:00}" "${remaining:-0:00:00}"
        sleep "${refreshRate}"
    done
    printf "\033[0K\r\n\033[0K\r\n"

    if [ -e "${outputFile}" ]; then
        sed -n '/PORT.*STATE.*SERVICE/,/^# Nmap/H;${x;s/^\n\|\n[^\n]*\n# Nmap.*//gp}' "${outputFile}" | awk '!/^SF(:|-).*$/' | grep -v 'service unrecognized despite'
    else
        cat "${tmpOutputFile}"
    fi
    rm -f "${tmpOutputFile}"
}

# Run nmap silently (no progress bar, for secondary scans)
nmapQuiet() {
    printf "${CYAN}  → Running: $(echo "$1" | sed 's|.*/nmap|nmap|')${NC}\n"
    eval "$1" 2>&1
}

# ═══════════════════════════════════════════════════════════════════
# Header
# ═══════════════════════════════════════════════════════════════════
header() {
    echo
    printf "${BOLD}${GREEN}══════════════════════════════════════════════════════════════${NC}\n"
    printf "${BOLD}${GREEN}  nmapauto ${VERSION} — PCI Network Security Scanner${NC}\n"
    printf "${BOLD}${GREEN}══════════════════════════════════════════════════════════════${NC}\n"
    echo

    if expr "${TYPE}" : '^\([Aa]ll\)$' >/dev/null; then
        printf "${YELLOW}Running all scans on ${NC}${HOST}"
    else
        printf "${YELLOW}Running a ${TYPE} scan on ${NC}${HOST}"
    fi

    if expr "${HOST}" : '^\(\([[:alnum:]-]\{1,63\}\.\)*[[:alpha:]]\{2,6\}\)$' >/dev/null; then
        urlIP="$(host -4 -W 1 "${HOST}" ${DNSSERVER} 2>/dev/null | grep "${HOST}" | head -n 1 | awk '{print $NF}')"
        if [ -n "${urlIP}" ]; then
            printf "${YELLOW} with IP ${NC}${urlIP}\n\n"
        else
            printf ".. ${RED}Could not resolve IP of ${NC}${HOST}\n\n"
        fi
    else
        printf "\n"
    fi

    $REMOTE && printf "${YELLOW}Running in Remote mode! Some scans will be limited.\n"

    # Subnet detection
    if expr "${HOST}" : '^\([0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\)$' >/dev/null; then
        subnet="$(echo "${HOST}" | cut -d "." -f 1,2,3).0"
    fi

    # Ping & OS detection
    kernel="$(uname -s)"
    checkPing="$(checkPing "${urlIP:-$HOST}")"
    nmapType="$(echo "${checkPing}" | head -n 1)"

    if expr "${nmapType}" : ".*-Pn$" >/dev/null; then
        pingable=false
        printf "${NC}\n${YELLOW}No ping detected.. Will not use ping scans!\n${NC}\n"
    else
        pingable=true
    fi

    ttl="$(echo "${checkPing}" | tail -n 1)"
    if [ "${ttl}" != "nmap -Pn" ] && [ -n "${ttl}" ]; then
        osType="$(checkOS "${ttl}")"
        printf "${NC}\n${GREEN}Host is likely running ${osType}\n"
    fi

    printf "${CYAN}Scan started: $(date '+%Y-%m-%d %H:%M:%S')${NC}\n"
    echo
    echo
}

# ═══════════════════════════════════════════════════════════════════
# SCAN: Network Discovery
# ═══════════════════════════════════════════════════════════════════
networkScan() {
    printf "${GREEN}---------------------Starting Network Scan---------------------${NC}\n\n"

    origHOST="${HOST}"
    HOST="${urlIP:-$HOST}"
    if [ "$(uname -s)" = "Linux" ]; then TW="W"; else TW="t"; fi

    if ! $REMOTE; then
        nmapProgressBar "${nmapType} -T4 --max-retries 1 --max-scan-delay 20 -n -sn -oN nmap/Network_${HOST}.nmap ${subnet}/24"
        printf "${YELLOW}Found the following live hosts:${NC}\n\n"
        grep -v '#' "nmap/Network_${HOST}.nmap" | grep "$(echo "$subnet" | sed 's/..$//')" | awk '{print $5}'
    elif $pingable; then
        echo >"nmap/Network_${HOST}.nmap"
        for ip in $(seq 0 254); do
            (ping -c 1 -${TW} 1 "$(echo "$subnet" | sed 's/..$//').$ip" 2>/dev/null | grep 'stat' -A1 | xargs | grep -v ', 0.*received' | awk '{print $2}' >>"nmap/Network_${HOST}.nmap") &
        done
        wait
        sedi '/^$/d' "nmap/Network_${HOST}.nmap"
        sort -t . -k 3,3n -k 4,4n "nmap/Network_${HOST}.nmap"
    else
        printf "${YELLOW}No ping detected.. TCP Network Scan is not implemented yet in Remote mode.\n${NC}"
    fi

    HOST="${origHOST}"
    echo; echo; echo
}

# ═══════════════════════════════════════════════════════════════════
# SCAN: Port Discovery (Quick)
# ═══════════════════════════════════════════════════════════════════
portScan() {
    printf "${GREEN}---------------------Starting Port Scan-----------------------${NC}\n\n"

    if ! $REMOTE; then
        nmapProgressBar "${nmapType} -T4 --max-retries 1 --max-scan-delay 20 --open -oN nmap/Port_${HOST}.nmap ${HOST} ${DNSSTRING}"
        assignPorts "${HOST}"
    else
        printf "${YELLOW}Port Scan is not implemented yet in Remote mode.\n${NC}"
    fi

    echo; echo; echo
}

# ═══════════════════════════════════════════════════════════════════
# SCAN: Script/Version Detection
# ═══════════════════════════════════════════════════════════════════
scriptScan() {
    printf "${GREEN}---------------------Starting Script Scan-----------------------${NC}\n\n"

    if ! $REMOTE; then
        if [ -z "${commonPorts}" ]; then
            printf "${YELLOW}No ports in port scan.. Skipping!\n"
        else
            nmapProgressBar "${nmapType} -sCV -p${commonPorts} --open -oN nmap/Script_${HOST}.nmap ${HOST} ${DNSSTRING}" 2
        fi

        if [ -f "nmap/Script_${HOST}.nmap" ] && grep -q "Service Info: OS:" "nmap/Script_${HOST}.nmap"; then
            serviceOS="$(sed -n '/Service Info/{s/.* \([^;]*\);.*/\1/p;q}' "nmap/Script_${HOST}.nmap")"
            if [ "${osType}" != "${serviceOS}" ]; then
                osType="${serviceOS}"
                printf "${NC}\n\n${GREEN}OS Detection modified to: ${osType}\n${NC}\n"
            fi
        fi
    else
        printf "${YELLOW}Script Scan is not supported in Remote mode.\n${NC}"
    fi

    echo; echo; echo
}

# ═══════════════════════════════════════════════════════════════════
# SCAN: Full Port Range (1-65535)
# ═══════════════════════════════════════════════════════════════════
fullScan() {
    printf "${GREEN}---------------------Starting Full Scan------------------------${NC}\n\n"

    if ! $REMOTE; then
        nmapProgressBar "${nmapType} -p- --max-retries 1 --max-rate 500 --max-scan-delay 20 -T4 -v --open -oN nmap/Full_${HOST}.nmap ${HOST} ${DNSSTRING}" 3
        assignPorts "${HOST}"

        if [ -z "${commonPorts}" ]; then
            echo; echo
            printf "${YELLOW}Making a script scan on all ports\n${NC}\n"
            nmapProgressBar "${nmapType} -sCV -p${allPorts} --open -oN nmap/Full_Extra_${HOST}.nmap ${HOST} ${DNSSTRING}" 2
            assignPorts "${HOST}"
        else
            cmpPorts
            if [ -z "${extraPorts}" ]; then
                echo; echo
                allPorts=""
                printf "${YELLOW}No new ports\n${NC}\n"
            else
                echo; echo
                printf "${YELLOW}Making a script scan on extra ports: $(echo "${extraPorts}" | sed 's/,/, /g')\n${NC}\n"
                nmapProgressBar "${nmapType} -sCV -p${extraPorts} --open -oN nmap/Full_Extra_${HOST}.nmap ${HOST} ${DNSSTRING}" 2
                assignPorts "${HOST}"
            fi
        fi
    else
        printf "${YELLOW}Full Scan is not implemented yet in Remote mode.\n${NC}"
    fi

    echo; echo; echo
}

# ═══════════════════════════════════════════════════════════════════
# SCAN: UDP
# ═══════════════════════════════════════════════════════════════════
UDPScan() {
    printf "${GREEN}----------------------Starting UDP Scan------------------------${NC}\n\n"

    if ! $REMOTE; then
        if [ "${USER}" != 'root' ]; then
            echo "UDP needs to be run as root, running with sudo..."
            ${SUDO_CMD:+${SUDO_CMD} -v}
            echo
        fi

        nmapProgressBar "${SUDO_CMD} ${nmapType} -sU --top-ports 1000 --max-retries 1 --open -oN nmap/UDP_${HOST}.nmap ${HOST} ${DNSSTRING}" 3
        assignPorts "${HOST}"

        if [ -n "${udpPorts}" ]; then
            echo; echo
            printf "${YELLOW}Making a script scan on UDP ports: $(echo "${udpPorts}" | sed 's/,/, /g')\n${NC}\n"
            ${SUDO_CMD:+${SUDO_CMD} -v}
            nmapProgressBar "${SUDO_CMD} ${nmapType} -sCVU -p${udpPorts} --open -oN nmap/UDP_Extra_${HOST}.nmap ${HOST} ${DNSSTRING}" 2
        else
            echo; echo
            printf "${YELLOW}No UDP ports are open\n${NC}\n"
        fi
    else
        printf "${YELLOW}UDP Scan is not implemented yet in Remote mode.\n${NC}"
    fi

    echo; echo; echo
}

# ═══════════════════════════════════════════════════════════════════
# SCAN: Vulnerability Detection (Enhanced)
# ═══════════════════════════════════════════════════════════════════
vulnsScan() {
    printf "${GREEN}---------------------Starting Vulns Scan-----------------------${NC}\n\n"

    if ! $REMOTE; then
        if [ -z "${allPorts}" ]; then
            portType="common"
            ports="${commonPorts}"
        else
            portType="all"
            ports="${allPorts}"
        fi

        if [ -z "${ports}" ]; then
            printf "${YELLOW}No ports found.. Skipping vulnerability scan!\n${NC}"
            echo; echo; echo
            return
        fi

        # --- CVE Scan with vulners ---
        if [ -f /usr/share/nmap/scripts/vulners.nse ] || ${NMAPPATH} --script-help vulners >/dev/null 2>&1; then
            printf "${YELLOW}Running CVE scan (vulners) on ${portType} ports${NC}\n\n"
            nmapProgressBar "${nmapType} -sV --script vulners --script-args mincvss=5.0 -p${ports} --open -oN nmap/CVEs_${HOST}.nmap ${HOST} ${DNSSTRING}" 3
            echo
        else
            printf "${YELLOW}vulners.nse not found — skipping CVE scan${NC}\n"
            printf "${CYAN}Install: https://github.com/vulnersCom/nmap-vulners${NC}\n\n"
        fi

        # --- Nmap vuln category scripts ---
        echo
        printf "${YELLOW}Running Vuln scan on ${portType} ports (this may take a while)...${NC}\n\n"
        nmapProgressBar "${nmapType} -sV --script vuln -p${ports} --open -oN nmap/Vulns_${HOST}.nmap ${HOST} ${DNSSTRING}" 3

        # --- vulscan if available ---
        if [ -f /usr/share/nmap/scripts/vulscan/vulscan.nse ] || ${NMAPPATH} --script-help vulscan >/dev/null 2>&1; then
            echo
            printf "${YELLOW}Running vulscan CVE database scan...${NC}\n\n"
            nmapProgressBar "${nmapType} -sV --script vulscan/vulscan.nse --script-args vulscandb=cve.csv -p${ports} --open -oN nmap/Vulscan_${HOST}.nmap ${HOST} ${DNSSTRING}" 3
        fi

        # --- Auth check (default creds / anon access) ---
        echo
        printf "${YELLOW}Running authentication checks on ${portType} ports...${NC}\n\n"
        nmapProgressBar "${nmapType} --script auth -p${ports} --open -oN nmap/Auth_${HOST}.nmap ${HOST} ${DNSSTRING}" 3

        # --- Brute-force safe checks (banner, default creds only) ---
        echo
        printf "${YELLOW}Running default credential checks...${NC}\n\n"
        ${nmapType} --script=banner -p${ports} --open -oN "nmap/Banners_${HOST}.nmap" ${HOST} ${DNSSTRING} >/dev/null 2>&1
        if [ -f "nmap/Banners_${HOST}.nmap" ]; then
            printf "${CYAN}Banner grab results saved to nmap/Banners_${HOST}.nmap${NC}\n"
        fi
    else
        printf "${YELLOW}Vulns Scan is not supported in Remote mode.\n${NC}"
    fi

    echo; echo; echo
}

# ═══════════════════════════════════════════════════════════════════
# SCAN: SSL/TLS Analysis (NEW)
# ═══════════════════════════════════════════════════════════════════
sslScan() {
    printf "${GREEN}---------------------Starting SSL/TLS Scan---------------------${NC}\n\n"

    if $REMOTE; then
        printf "${YELLOW}SSL Scan is not supported in Remote mode.\n${NC}"
        echo; echo; echo
        return
    fi

    # Determine which ports to scan for SSL
    if [ -z "${allPorts}" ]; then
        ports="${commonPorts}"
    else
        ports="${allPorts}"
    fi

    if [ -z "${ports}" ]; then
        # Default common SSL ports
        ports="443,8443,993,995,465,636,989,990,992,994,5061,6697"
        printf "${YELLOW}No ports from prior scans — testing common SSL ports: ${ports}${NC}\n\n"
    fi

    mkdir -p nmap/ssl

    # --- SSL enum ciphers ---
    printf "${YELLOW}[1/5] Enumerating SSL/TLS ciphers and protocols...${NC}\n\n"
    ${nmapType} --script ssl-enum-ciphers -p${ports} --open \
        -oN "nmap/ssl/SSL_Ciphers_${HOST}.nmap" ${HOST} ${DNSSTRING} 2>&1 | \
        grep -E "TLSv|SSLv|cipher|compressor|WARNING|NULL|WEAK|Grade" || true
    echo

    # --- SSL certificate details ---
    printf "${YELLOW}[2/5] Extracting SSL certificate details...${NC}\n\n"
    ${nmapType} --script ssl-cert -p${ports} --open \
        -oN "nmap/ssl/SSL_Cert_${HOST}.nmap" ${HOST} ${DNSSTRING} 2>&1 | \
        grep -E "Subject:|Issuer:|Not valid|sha256|Public Key|Alternative" || true
    echo

    # --- Check for known TLS vulnerabilities ---
    printf "${YELLOW}[3/5] Testing for TLS vulnerabilities (Heartbleed, POODLE, CCS, ROBOT, LOGJAM)...${NC}\n\n"
    ${nmapType} --script ssl-heartbleed,ssl-poodle,ssl-ccs-injection,tls-ticketbleed \
        -p${ports} --open \
        -oN "nmap/ssl/SSL_Vulns_${HOST}.nmap" ${HOST} ${DNSSTRING} 2>&1 | \
        grep -E "VULNERABLE|NOT VULNERABLE|State:|heartbleed|poodle|ccs-injection|ticketbleed" || true
    echo

    # --- Check for weak DH parameters ---
    printf "${YELLOW}[4/5] Checking for weak Diffie-Hellman parameters...${NC}\n\n"
    ${nmapType} --script ssl-dh-params -p${ports} --open \
        -oN "nmap/ssl/SSL_DH_${HOST}.nmap" ${HOST} ${DNSSTRING} 2>&1 | \
        grep -E "VULNERABLE|DH|LOGJAM|WEAK" || true
    echo

    # --- SSLv2/SSLv3 deprecated protocol check ---
    printf "${YELLOW}[5/5] Checking for deprecated protocols (SSLv2, SSLv3, TLS 1.0, TLS 1.1)...${NC}\n\n"
    ${nmapType} --script ssl-enum-ciphers -p${ports} --open \
        -oN "nmap/ssl/SSL_Deprecated_${HOST}.nmap" ${HOST} ${DNSSTRING} 2>&1 | \
        grep -E "SSLv2|SSLv3|TLSv1\.0|TLSv1\.1|WARNING" || true
    echo

    # --- External sslscan if available ---
    if type sslscan >/dev/null 2>&1; then
        printf "${YELLOW}Running sslscan for additional analysis...${NC}\n\n"
        sslscan --no-colour "${HOST}" 2>/dev/null | tee "nmap/ssl/sslscan_${HOST}.txt" | \
            grep -E "Accepted|Preferred|SSLv|TLSv|Certificate|Heartbleed|expired|self-signed" || true
        echo
    fi

    # --- testssl.sh if available ---
    if type testssl >/dev/null 2>&1 || type testssl.sh >/dev/null 2>&1; then
        TESTSSL="$(command -v testssl || command -v testssl.sh)"
        printf "${YELLOW}Running testssl.sh for comprehensive TLS testing...${NC}\n\n"
        "${TESTSSL}" --quiet --color 0 "${HOST}" 2>/dev/null | tee "nmap/ssl/testssl_${HOST}.txt" | \
            grep -E "VULNERABLE|NOT ok|WARN|Grade|offered" || true
        echo
    fi

    printf "${GREEN}SSL/TLS scan results saved in nmap/ssl/${NC}\n"
    echo; echo; echo
}

# ═══════════════════════════════════════════════════════════════════
# SCAN: Firewall & ACL Detection (NEW)
# ═══════════════════════════════════════════════════════════════════
firewallScan() {
    printf "${GREEN}---------------------Starting Firewall Scan--------------------${NC}\n\n"

    if $REMOTE; then
        printf "${YELLOW}Firewall Scan is not supported in Remote mode.\n${NC}"
        echo; echo; echo
        return
    fi

    if [ -z "${allPorts}" ]; then
        ports="${commonPorts}"
    else
        ports="${allPorts}"
    fi

    mkdir -p nmap/firewall

    # --- ACK scan to detect filtered/unfiltered ports (stateful firewall detection) ---
    printf "${YELLOW}[1/6] ACK scan — detecting stateful firewall rules...${NC}\n\n"
    if [ "${USER}" != 'root' ]; then ${SUDO_CMD:+${SUDO_CMD} -v}; fi
    ${SUDO_CMD} ${nmapType} -sA -T4 --top-ports 100 \
        -oN "nmap/firewall/ACK_Scan_${HOST}.nmap" ${HOST} ${DNSSTRING} 2>&1 | \
        grep -E "filtered|unfiltered|PORT" || true
    echo

    # --- Window scan for more granular firewall detection ---
    printf "${YELLOW}[2/6] TCP Window scan — granular firewall analysis...${NC}\n\n"
    ${SUDO_CMD} ${nmapType} -sW -T4 --top-ports 50 \
        -oN "nmap/firewall/Window_Scan_${HOST}.nmap" ${HOST} ${DNSSTRING} 2>&1 | \
        grep -E "open|closed|filtered|PORT" || true
    echo

    # --- Firewall/IDS evasion scripts ---
    printf "${YELLOW}[3/6] Firewall detection NSE scripts...${NC}\n\n"
    ${nmapType} --script firewall-bypass,firewalk -T4 --top-ports 25 \
        -oN "nmap/firewall/FW_Scripts_${HOST}.nmap" ${HOST} ${DNSSTRING} 2>&1 | \
        grep -v "^$" || true
    echo

    # --- IP ID sequence analysis ---
    printf "${YELLOW}[4/6] IP ID sequence analysis (idle scan feasibility)...${NC}\n\n"
    ${nmapType} -O --top-ports 25 \
        -oN "nmap/firewall/IPID_${HOST}.nmap" ${HOST} ${DNSSTRING} 2>&1 | \
        grep -E "IP ID|OS details|fingerprint|aggressive" || true
    echo

    # --- Traceroute to detect filtering hops ---
    printf "${YELLOW}[5/6] Traceroute — identifying filtering hops...${NC}\n\n"
    ${nmapType} --traceroute --top-ports 10 \
        -oN "nmap/firewall/Traceroute_${HOST}.nmap" ${HOST} ${DNSSTRING} 2>&1 | \
        grep -E "HOP|TRACEROUTE|[0-9]\.\.\." || true
    echo

    # --- Fragment scan to test firewall reassembly ---
    printf "${YELLOW}[6/6] Fragment scan — testing firewall packet reassembly...${NC}\n\n"
    ${SUDO_CMD} ${nmapType} -f --top-ports 25 \
        -oN "nmap/firewall/Fragment_${HOST}.nmap" ${HOST} ${DNSSTRING} 2>&1 | \
        grep -E "open|filtered|PORT" || true
    echo

    printf "${GREEN}Firewall scan results saved in nmap/firewall/${NC}\n"
    echo; echo; echo
}

# ═══════════════════════════════════════════════════════════════════
# SCAN: PCI DSS Segmentation Verification (NEW)
# ═══════════════════════════════════════════════════════════════════
pciScan() {
    printf "${GREEN}═══════════════════════════════════════════════════════════════${NC}\n"
    printf "${GREEN}       PCI DSS SEGMENTATION VERIFICATION SCAN${NC}\n"
    printf "${GREEN}═══════════════════════════════════════════════════════════════${NC}\n\n"

    if $REMOTE; then
        printf "${YELLOW}PCI Scan is not supported in Remote mode.\n${NC}"
        echo; echo; echo
        return
    fi

    if [ -z "${allPorts}" ]; then
        ports="${commonPorts}"
    else
        ports="${allPorts}"
    fi

    mkdir -p nmap/pci

    printf "${CYAN}PCI DSS Requirement 11.3.4 / 11.4.5: Segmentation penetration testing${NC}\n"
    printf "${CYAN}Verifying that network segments are properly isolated from the CDE${NC}\n\n"

    # ═══════════════════════════════════════════════
    # Section 1: Full TCP Port Scan (Segmentation)
    # ═══════════════════════════════════════════════
    printf "${MAGENTA}━━━ Section 1: Full TCP Port Connectivity Test ━━━${NC}\n\n"
    printf "${YELLOW}Scanning all 65535 TCP ports to verify segmentation blocks unauthorized access...${NC}\n\n"
    nmapProgressBar "${nmapType} -p- -T4 --max-retries 2 --max-rate 1000 -v --open --reason \
        -oN nmap/pci/PCI_FullTCP_${HOST}.nmap ${HOST} ${DNSSTRING}" 5

    # Count open ports for PCI reporting
    if [ -f "nmap/pci/PCI_FullTCP_${HOST}.nmap" ]; then
        openCount="$(grep -c "^[0-9].*open " "nmap/pci/PCI_FullTCP_${HOST}.nmap" 2>/dev/null || echo 0)"
        printf "\n${BOLD}${CYAN}[PCI] TCP open ports found: ${openCount}${NC}\n"
        if [ "${openCount}" -gt 0 ]; then
            printf "${RED}[!] WARNING: Open ports detected — verify each is authorized for cross-segment access${NC}\n"
        else
            printf "${GREEN}[✓] No open TCP ports — segmentation appears effective${NC}\n"
        fi
    fi
    echo

    # ═══════════════════════════════════════════════
    # Section 2: Full UDP Scan (Top Ports)
    # ═══════════════════════════════════════════════
    printf "${MAGENTA}━━━ Section 2: UDP Port Connectivity Test ━━━${NC}\n\n"
    if [ "${USER}" != 'root' ]; then ${SUDO_CMD:+${SUDO_CMD} -v}; fi
    printf "${YELLOW}Scanning top 1000 UDP ports for segmentation leaks...${NC}\n\n"
    nmapProgressBar "${SUDO_CMD} ${nmapType} -sU --top-ports 1000 --max-retries 1 --open --reason \
        -oN nmap/pci/PCI_UDP_${HOST}.nmap ${HOST} ${DNSSTRING}" 5

    if [ -f "nmap/pci/PCI_UDP_${HOST}.nmap" ]; then
        udpOpenCount="$(grep -c "^[0-9].*open " "nmap/pci/PCI_UDP_${HOST}.nmap" 2>/dev/null || echo 0)"
        printf "\n${BOLD}${CYAN}[PCI] UDP open ports found: ${udpOpenCount}${NC}\n"
        if [ "${udpOpenCount}" -gt 0 ]; then
            printf "${RED}[!] WARNING: Open UDP ports detected — verify authorization${NC}\n"
        else
            printf "${GREEN}[✓] No open UDP ports — segmentation appears effective${NC}\n"
        fi
    fi
    echo

    # ═══════════════════════════════════════════════
    # Section 3: Service Version & Banner Detection
    # ═══════════════════════════════════════════════
    printf "${MAGENTA}━━━ Section 3: Service Identification on Open Ports ━━━${NC}\n\n"
    # Gather all open ports from PCI scans
    pciTcpPorts=""
    if [ -f "nmap/pci/PCI_FullTCP_${HOST}.nmap" ]; then
        pciTcpPorts="$(awk -vORS=, -F/ '/^[0-9]/{print $1}' "nmap/pci/PCI_FullTCP_${HOST}.nmap" | sed 's/.$//')"
    fi
    pciUdpPorts=""
    if [ -f "nmap/pci/PCI_UDP_${HOST}.nmap" ]; then
        pciUdpPorts="$(awk -vORS=, -F/ '/^[0-9].*open /{print $1}' "nmap/pci/PCI_UDP_${HOST}.nmap" | sed 's/.$//')"
    fi

    if [ -n "${pciTcpPorts}" ]; then
        printf "${YELLOW}Running version detection on open TCP ports: ${pciTcpPorts}${NC}\n\n"
        nmapProgressBar "${nmapType} -sCV -p${pciTcpPorts} --open --reason \
            -oN nmap/pci/PCI_Services_${HOST}.nmap ${HOST} ${DNSSTRING}" 2
    else
        printf "${GREEN}No open TCP ports to fingerprint.${NC}\n"
    fi
    echo

    # ═══════════════════════════════════════════════
    # Section 4: PCI-Sensitive Service Detection
    # ═══════════════════════════════════════════════
    printf "${MAGENTA}━━━ Section 4: PCI-Sensitive Service Detection ━━━${NC}\n\n"
    printf "${YELLOW}Checking for CDE-relevant services that should NOT be accessible across segments...${NC}\n\n"

    # Check for database ports
    dbPorts="1433,1434,3306,5432,1521,27017,6379,9042,5984,8529,28015,7474,9200,9300"
    printf "${CYAN}  [4a] Database services (MSSQL, MySQL, PostgreSQL, Oracle, MongoDB, Redis, etc.)...${NC}\n"
    ${nmapType} -sV -p${dbPorts} --open --reason \
        -oN "nmap/pci/PCI_DB_Ports_${HOST}.nmap" ${HOST} ${DNSSTRING} 2>&1 | \
        grep -E "^[0-9].*open" || printf "  ${GREEN}No database ports accessible${NC}\n"
    echo

    # Check for admin/management ports
    adminPorts="22,23,3389,5900,5901,5985,5986,2049,111,135,139,445,161,162,389,636,88,464"
    printf "${CYAN}  [4b] Admin/Management services (SSH, RDP, VNC, WinRM, NFS, SMB, SNMP, LDAP, Kerberos)...${NC}\n"
    ${nmapType} -sV -p${adminPorts} --open --reason \
        -oN "nmap/pci/PCI_Admin_Ports_${HOST}.nmap" ${HOST} ${DNSSTRING} 2>&1 | \
        grep -E "^[0-9].*open" || printf "  ${GREEN}No admin/management ports accessible${NC}\n"
    echo

    # Check for cardholder data environment ports
    cdePorts="80,443,8080,8443,8000,8888,9443,4443"
    printf "${CYAN}  [4c] Web/Application services (potential CDE front-ends)...${NC}\n"
    ${nmapType} -sV -p${cdePorts} --open --reason \
        -oN "nmap/pci/PCI_Web_Ports_${HOST}.nmap" ${HOST} ${DNSSTRING} 2>&1 | \
        grep -E "^[0-9].*open" || printf "  ${GREEN}No web application ports accessible${NC}\n"
    echo

    # Check for payment processing ports
    paymentPorts="443,9100,9101,9102,4100,8583,8090,20000,20001"
    printf "${CYAN}  [4d] Payment processing / POS ports...${NC}\n"
    ${nmapType} -sV -p${paymentPorts} --open --reason \
        -oN "nmap/pci/PCI_Payment_Ports_${HOST}.nmap" ${HOST} ${DNSSTRING} 2>&1 | \
        grep -E "^[0-9].*open" || printf "  ${GREEN}No payment processing ports accessible${NC}\n"
    echo

    # ═══════════════════════════════════════════════
    # Section 5: SSL/TLS on Open Ports
    # ═══════════════════════════════════════════════
    if [ -n "${pciTcpPorts}" ]; then
        printf "${MAGENTA}━━━ Section 5: SSL/TLS Assessment on Open Ports ━━━${NC}\n\n"
        printf "${YELLOW}Checking for weak ciphers, expired certs, deprecated protocols...${NC}\n\n"

        ${nmapType} --script ssl-enum-ciphers,ssl-cert,ssl-heartbleed,ssl-poodle,ssl-ccs-injection,ssl-dh-params \
            -p${pciTcpPorts} --open \
            -oN "nmap/pci/PCI_SSL_${HOST}.nmap" ${HOST} ${DNSSTRING} 2>&1 | \
            grep -E "TLSv|SSLv|VULNERABLE|Grade|WARNING|expired|self-signed|Subject:|NULL|WEAK|SHA1" || \
            printf "  ${GREEN}No SSL/TLS issues detected on open ports${NC}\n"
        echo
    fi

    # ═══════════════════════════════════════════════
    # Section 6: Vulnerability Assessment
    # ═══════════════════════════════════════════════
    if [ -n "${pciTcpPorts}" ]; then
        printf "${MAGENTA}━━━ Section 6: Vulnerability Assessment on Open Ports ━━━${NC}\n\n"

        printf "${YELLOW}Running vuln category scripts...${NC}\n\n"
        nmapProgressBar "${nmapType} -sV --script vuln -p${pciTcpPorts} --open \
            -oN nmap/pci/PCI_Vulns_${HOST}.nmap ${HOST} ${DNSSTRING}" 3

        if [ -f /usr/share/nmap/scripts/vulners.nse ] || ${NMAPPATH} --script-help vulners >/dev/null 2>&1; then
            echo
            printf "${YELLOW}Running CVE scan (vulners)...${NC}\n\n"
            nmapProgressBar "${nmapType} -sV --script vulners --script-args mincvss=4.0 -p${pciTcpPorts} --open \
                -oN nmap/pci/PCI_CVEs_${HOST}.nmap ${HOST} ${DNSSTRING}" 3
        fi
    fi
    echo

    # ═══════════════════════════════════════════════
    # Section 7: ICMP & Protocol Checks
    # ═══════════════════════════════════════════════
    printf "${MAGENTA}━━━ Section 7: ICMP & IP Protocol Scan ━━━${NC}\n\n"

    printf "${CYAN}  [7a] ICMP connectivity check...${NC}\n"
    if [ "$(uname -s)" = "Linux" ]; then TW="W"; else TW="t"; fi
    pingResult="$(ping -c 3 -${TW} 2 "${urlIP:-$HOST}" 2>&1)"
    if echo "${pingResult}" | grep -qi "ttl"; then
        printf "  ${RED}[!] ICMP (ping) is ALLOWED to this host — verify if intended${NC}\n"
        echo "${pingResult}" | grep -iE "ttl|packets" | head -3
    else
        printf "  ${GREEN}[✓] ICMP (ping) is BLOCKED — good segmentation practice${NC}\n"
    fi
    echo

    printf "${CYAN}  [7b] IP Protocol scan (TCP, UDP, ICMP, IGMP, etc.)...${NC}\n"
    ${SUDO_CMD} ${nmapType} -sO --top-ports 10 \
        -oN "nmap/pci/PCI_Protocols_${HOST}.nmap" ${HOST} ${DNSSTRING} 2>&1 | \
        grep -E "^[0-9].*open" || printf "  ${GREEN}Only expected protocols detected${NC}\n"
    echo

    # ═══════════════════════════════════════════════
    # Section 8: OS & Device Fingerprinting
    # ═══════════════════════════════════════════════
    printf "${MAGENTA}━━━ Section 8: OS & Device Fingerprinting ━━━${NC}\n\n"
    ${SUDO_CMD} ${nmapType} -O --osscan-guess --max-retries 2 \
        -oN "nmap/pci/PCI_OS_${HOST}.nmap" ${HOST} ${DNSSTRING} 2>&1 | \
        grep -E "OS details|Running|Device type|fingerprint|Aggressive" || \
        printf "  ${YELLOW}Could not determine OS — host may be well-hardened${NC}\n"
    echo

    # ═══════════════════════════════════════════════
    # PCI Summary Report
    # ═══════════════════════════════════════════════
    printf "${GREEN}═══════════════════════════════════════════════════════════════${NC}\n"
    printf "${GREEN}       PCI SEGMENTATION SCAN SUMMARY — ${HOST}${NC}\n"
    printf "${GREEN}═══════════════════════════════════════════════════════════════${NC}\n\n"

    printf "${BOLD}Scan Date:${NC} $(date '+%Y-%m-%d %H:%M:%S')\n"
    printf "${BOLD}Target:${NC} ${HOST}\n"
    printf "${BOLD}OS Guess:${NC} ${osType:-Unknown}\n\n"

    # Generate summary report file
    summaryFile="nmap/pci/PCI_Summary_${HOST}.txt"
    {
        echo "============================================================"
        echo "PCI DSS SEGMENTATION VERIFICATION REPORT"
        echo "============================================================"
        echo "Date:   $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Target: ${HOST}"
        echo "OS:     ${osType:-Unknown}"
        echo "============================================================"
        echo ""
        echo "FINDINGS:"
        echo ""

        echo "--- TCP Open Ports ---"
        if [ -f "nmap/pci/PCI_FullTCP_${HOST}.nmap" ]; then
            grep "^[0-9].*open" "nmap/pci/PCI_FullTCP_${HOST}.nmap" || echo "  None found"
        else
            echo "  Scan not completed"
        fi
        echo ""

        echo "--- UDP Open Ports ---"
        if [ -f "nmap/pci/PCI_UDP_${HOST}.nmap" ]; then
            grep "^[0-9].*open " "nmap/pci/PCI_UDP_${HOST}.nmap" || echo "  None found"
        else
            echo "  Scan not completed"
        fi
        echo ""

        echo "--- Database Ports ---"
        if [ -f "nmap/pci/PCI_DB_Ports_${HOST}.nmap" ]; then
            grep "^[0-9].*open" "nmap/pci/PCI_DB_Ports_${HOST}.nmap" || echo "  None accessible"
        fi
        echo ""

        echo "--- Admin/Management Ports ---"
        if [ -f "nmap/pci/PCI_Admin_Ports_${HOST}.nmap" ]; then
            grep "^[0-9].*open" "nmap/pci/PCI_Admin_Ports_${HOST}.nmap" || echo "  None accessible"
        fi
        echo ""

        echo "--- Web/Application Ports ---"
        if [ -f "nmap/pci/PCI_Web_Ports_${HOST}.nmap" ]; then
            grep "^[0-9].*open" "nmap/pci/PCI_Web_Ports_${HOST}.nmap" || echo "  None accessible"
        fi
        echo ""

        echo "--- SSL/TLS Issues ---"
        if [ -f "nmap/pci/PCI_SSL_${HOST}.nmap" ]; then
            grep -E "VULNERABLE|WEAK|SSLv2|SSLv3|TLSv1\.0|TLSv1\.1|expired|self-signed" "nmap/pci/PCI_SSL_${HOST}.nmap" || echo "  No issues found"
        fi
        echo ""

        echo "--- Vulnerabilities ---"
        if [ -f "nmap/pci/PCI_Vulns_${HOST}.nmap" ]; then
            grep -E "VULNERABLE|CVE-" "nmap/pci/PCI_Vulns_${HOST}.nmap" | head -20 || echo "  No vulnerabilities found"
        fi
        echo ""

        echo "--- ICMP Status ---"
        if echo "${pingResult}" | grep -qi "ttl"; then
            echo "  ICMP ALLOWED — verify if intended"
        else
            echo "  ICMP BLOCKED — good"
        fi
        echo ""

        echo "============================================================"
        echo "SEGMENTATION VERDICT:"
        echo ""
        tcpCount="${openCount:-0}"
        udpCount="${udpOpenCount:-0}"
        totalOpen=$((tcpCount + udpCount))
        if [ "${totalOpen}" -eq 0 ]; then
            echo "  [PASS] No open ports detected. Segmentation appears EFFECTIVE."
        elif [ "${totalOpen}" -le 5 ]; then
            echo "  [REVIEW] ${totalOpen} open port(s) detected. Verify each is authorized."
        else
            echo "  [FAIL] ${totalOpen} open port(s) detected. Segmentation may be INEFFECTIVE."
        fi
        echo ""
        echo "NOTE: This automated scan supplements but does not replace"
        echo "manual penetration testing required by PCI DSS 11.3.4/11.4.5"
        echo "============================================================"
    } | tee "${summaryFile}"

    printf "\n${GREEN}Full PCI report saved to: ${summaryFile}${NC}\n"
    echo; echo; echo
}

# ═══════════════════════════════════════════════════════════════════
# SCAN: Full Penetration Test (NEW)
# ═══════════════════════════════════════════════════════════════════
pentestScan() {
    printf "${GREEN}═══════════════════════════════════════════════════════════════${NC}\n"
    printf "${GREEN}       COMPREHENSIVE PENETRATION TEST SCAN${NC}\n"
    printf "${GREEN}═══════════════════════════════════════════════════════════════${NC}\n\n"

    if $REMOTE; then
        printf "${YELLOW}Pentest Scan is not supported in Remote mode.\n${NC}"
        echo; echo; echo
        return
    fi

    mkdir -p nmap/pentest

    # Gather known ports
    if [ -z "${allPorts}" ]; then
        ports="${commonPorts}"
    else
        ports="${allPorts}"
    fi

    # ═══════════════════════════════════════════════
    # Phase 1: Stealth & Evasion Scans
    # ═══════════════════════════════════════════════
    printf "${MAGENTA}━━━ Phase 1: Stealth Reconnaissance ━━━${NC}\n\n"

    printf "${YELLOW}[1a] SYN Stealth scan (all ports)...${NC}\n\n"
    if [ "${USER}" != 'root' ]; then ${SUDO_CMD:+${SUDO_CMD} -v}; fi
    nmapProgressBar "${SUDO_CMD} ${nmapType} -sS -p- -T4 --max-retries 2 --open --reason \
        -oN nmap/pentest/PT_SYN_${HOST}.nmap ${HOST} ${DNSSTRING}" 5
    echo

    printf "${YELLOW}[1b] Version intensity scan on open ports...${NC}\n\n"
    ptPorts="$(awk -vORS=, -F/ '/^[0-9]/{print $1}' "nmap/pentest/PT_SYN_${HOST}.nmap" 2>/dev/null | sed 's/.$//')"
    if [ -n "${ptPorts}" ]; then
        nmapProgressBar "${nmapType} -sV --version-intensity 5 -p${ptPorts} --open \
            -oN nmap/pentest/PT_Versions_${HOST}.nmap ${HOST} ${DNSSTRING}" 2
    fi
    echo

    printf "${YELLOW}[1c] Aggressive OS detection...${NC}\n\n"
    ${SUDO_CMD} ${nmapType} -O --osscan-guess --max-retries 2 -p${ptPorts:-1-1000} \
        -oN "nmap/pentest/PT_OS_${HOST}.nmap" ${HOST} ${DNSSTRING} 2>&1 | \
        grep -E "OS details|Running|Device type|Aggressive|fingerprint" || true
    echo

    # ═══════════════════════════════════════════════
    # Phase 2: Service Enumeration & NSE Deep Scan
    # ═══════════════════════════════════════════════
    printf "${MAGENTA}━━━ Phase 2: Service Enumeration ━━━${NC}\n\n"

    if [ -n "${ptPorts}" ]; then
        printf "${YELLOW}[2a] Default scripts + version detection...${NC}\n\n"
        nmapProgressBar "${nmapType} -sCV -p${ptPorts} --open \
            -oN nmap/pentest/PT_ScriptScan_${HOST}.nmap ${HOST} ${DNSSTRING}" 2
        echo

        printf "${YELLOW}[2b] Banner grabbing...${NC}\n\n"
        ${nmapType} --script banner -p${ptPorts} --open \
            -oN "nmap/pentest/PT_Banners_${HOST}.nmap" ${HOST} ${DNSSTRING} >/dev/null 2>&1
        printf "${CYAN}  Banner results saved${NC}\n"
        echo

        # Service-specific deep enumeration
        printf "${YELLOW}[2c] Service-specific enumeration scripts...${NC}\n\n"

        # HTTP enumeration
        httpPorts="$(grep -E "open.*http" "nmap/pentest/PT_ScriptScan_${HOST}.nmap" 2>/dev/null | awk -F/ '{print $1}' | tr '\n' ',' | sed 's/.$//')"
        if [ -n "${httpPorts}" ]; then
            printf "${CYAN}  HTTP services on ports: ${httpPorts}${NC}\n"
            ${nmapType} --script http-methods,http-headers,http-title,http-server-header,http-robots.txt,http-sitemap-generator,http-security-headers,http-cookie-flags,http-cors,http-crossdomainxml,http-internal-ip-disclosure,http-config-backup,http-default-accounts,http-passwd,http-shellshock,http-put,http-phpmyadmin-dir-traversal,http-backup-finder \
                -p${httpPorts} --open \
                -oN "nmap/pentest/PT_HTTP_Enum_${HOST}.nmap" ${HOST} ${DNSSTRING} >/dev/null 2>&1
            printf "${CYAN}  HTTP enumeration complete${NC}\n"

            # HTTP vulnerability checks
            ${nmapType} --script http-vuln-cve2017-5638,http-vuln-cve2017-1001000,http-vuln-cve2014-3704,http-vuln-cve2013-0156,http-vuln-cve2012-1823,http-vuln-cve2006-3392 \
                -p${httpPorts} --open \
                -oN "nmap/pentest/PT_HTTP_Vulns_${HOST}.nmap" ${HOST} ${DNSSTRING} >/dev/null 2>&1
            printf "${CYAN}  HTTP vuln checks complete${NC}\n"
        fi

        # SMB deep enum
        if echo "${ptPorts}" | grep -qE "(^|,)(445|139)(,|$)"; then
            printf "${CYAN}  SMB enumeration...${NC}\n"
            ${nmapType} --script smb-enum-shares,smb-enum-users,smb-enum-domains,smb-enum-groups,smb-enum-processes,smb-enum-sessions,smb-enum-services,smb-os-discovery,smb-protocols,smb-security-mode,smb-vuln-ms17-010,smb-vuln-ms08-067,smb-vuln-cve-2017-7494,smb-vuln-conficker,smb-double-pulsar-backdoor,smb2-security-mode,smb2-capabilities \
                -p139,445 --open \
                -oN "nmap/pentest/PT_SMB_Enum_${HOST}.nmap" ${HOST} ${DNSSTRING} >/dev/null 2>&1
            printf "${CYAN}  SMB enumeration complete${NC}\n"
        fi

        # SSH audit
        if echo "${ptPorts}" | grep -qE "(^|,)22(,|$)"; then
            printf "${CYAN}  SSH enumeration...${NC}\n"
            ${nmapType} --script ssh2-enum-algos,ssh-auth-methods,ssh-hostkey,ssh-publickey-acceptance \
                -p22 --open \
                -oN "nmap/pentest/PT_SSH_Enum_${HOST}.nmap" ${HOST} ${DNSSTRING} >/dev/null 2>&1
            printf "${CYAN}  SSH enumeration complete${NC}\n"
        fi

        # DNS deep enum
        if echo "${ptPorts}" | grep -qE "(^|,)53(,|$)"; then
            printf "${CYAN}  DNS enumeration...${NC}\n"
            ${nmapType} --script dns-zone-transfer,dns-cache-snoop,dns-recursion,dns-service-discovery,dns-nsid,dns-update,dns-random-txid,dns-random-srcport \
                -p53 --open \
                -oN "nmap/pentest/PT_DNS_Enum_${HOST}.nmap" ${HOST} ${DNSSTRING} >/dev/null 2>&1
            printf "${CYAN}  DNS enumeration complete${NC}\n"
        fi

        # SNMP
        if echo "${udpPorts}" | grep -qE "(^|,)161(,|$)"; then
            printf "${CYAN}  SNMP enumeration...${NC}\n"
            ${SUDO_CMD} ${nmapType} -sU --script snmp-info,snmp-interfaces,snmp-netstat,snmp-processes,snmp-sysdescr,snmp-win32-software,snmp-brute \
                -p161 --open \
                -oN "nmap/pentest/PT_SNMP_Enum_${HOST}.nmap" ${HOST} ${DNSSTRING} >/dev/null 2>&1
            printf "${CYAN}  SNMP enumeration complete${NC}\n"
        fi

        # LDAP
        if echo "${ptPorts}" | grep -qE "(^|,)(389|636)(,|$)"; then
            printf "${CYAN}  LDAP enumeration...${NC}\n"
            ${nmapType} --script ldap-rootdse,ldap-search,ldap-novell-getpass \
                -p389,636 --open \
                -oN "nmap/pentest/PT_LDAP_Enum_${HOST}.nmap" ${HOST} ${DNSSTRING} >/dev/null 2>&1
            printf "${CYAN}  LDAP enumeration complete${NC}\n"
        fi

        # RDP
        if echo "${ptPorts}" | grep -qE "(^|,)3389(,|$)"; then
            printf "${CYAN}  RDP enumeration...${NC}\n"
            ${nmapType} --script rdp-enum-encryption,rdp-vuln-ms12-020,rdp-ntlm-info \
                -p3389 --open \
                -oN "nmap/pentest/PT_RDP_Enum_${HOST}.nmap" ${HOST} ${DNSSTRING} >/dev/null 2>&1
            printf "${CYAN}  RDP enumeration complete${NC}\n"
        fi

        # FTP
        if echo "${ptPorts}" | grep -qE "(^|,)21(,|$)"; then
            printf "${CYAN}  FTP enumeration...${NC}\n"
            ${nmapType} --script ftp-anon,ftp-bounce,ftp-syst,ftp-vsftpd-backdoor,ftp-vuln-cve2010-4221,ftp-proftpd-backdoor \
                -p21 --open \
                -oN "nmap/pentest/PT_FTP_Enum_${HOST}.nmap" ${HOST} ${DNSSTRING} >/dev/null 2>&1
            printf "${CYAN}  FTP enumeration complete${NC}\n"
        fi

        # Telnet
        if echo "${ptPorts}" | grep -qE "(^|,)23(,|$)"; then
            printf "${CYAN}  Telnet enumeration...${NC}\n"
            ${nmapType} --script telnet-ntlm-info,telnet-encryption \
                -p23 --open \
                -oN "nmap/pentest/PT_Telnet_Enum_${HOST}.nmap" ${HOST} ${DNSSTRING} >/dev/null 2>&1
            printf "${CYAN}  Telnet enumeration complete${NC}\n"
        fi

        # Database services
        dbFound=""
        if echo "${ptPorts}" | grep -qE "(^|,)3306(,|$)"; then
            printf "${CYAN}  MySQL enumeration...${NC}\n"
            ${nmapType} --script mysql-info,mysql-enum,mysql-empty-password,mysql-databases,mysql-variables,mysql-vuln-cve2012-2122 \
                -p3306 --open \
                -oN "nmap/pentest/PT_MySQL_Enum_${HOST}.nmap" ${HOST} ${DNSSTRING} >/dev/null 2>&1
            dbFound="yes"
        fi
        if echo "${ptPorts}" | grep -qE "(^|,)1433(,|$)"; then
            printf "${CYAN}  MSSQL enumeration...${NC}\n"
            ${nmapType} --script ms-sql-info,ms-sql-config,ms-sql-empty-password,ms-sql-ntlm-info,ms-sql-dump-hashes \
                -p1433 --open \
                -oN "nmap/pentest/PT_MSSQL_Enum_${HOST}.nmap" ${HOST} ${DNSSTRING} >/dev/null 2>&1
            dbFound="yes"
        fi
        if echo "${ptPorts}" | grep -qE "(^|,)5432(,|$)"; then
            printf "${CYAN}  PostgreSQL enumeration...${NC}\n"
            ${nmapType} --script pgsql-brute \
                -p5432 --open \
                -oN "nmap/pentest/PT_PgSQL_Enum_${HOST}.nmap" ${HOST} ${DNSSTRING} >/dev/null 2>&1
            dbFound="yes"
        fi
        if echo "${ptPorts}" | grep -qE "(^|,)1521(,|$)"; then
            printf "${CYAN}  Oracle enumeration...${NC}\n"
            ${nmapType} --script oracle-sid-brute,oracle-tns-version \
                -p1521 --open \
                -oN "nmap/pentest/PT_Oracle_Enum_${HOST}.nmap" ${HOST} ${DNSSTRING} >/dev/null 2>&1
            dbFound="yes"
        fi
        if echo "${ptPorts}" | grep -qE "(^|,)27017(,|$)"; then
            printf "${CYAN}  MongoDB enumeration...${NC}\n"
            ${nmapType} --script mongodb-info,mongodb-databases \
                -p27017 --open \
                -oN "nmap/pentest/PT_MongoDB_Enum_${HOST}.nmap" ${HOST} ${DNSSTRING} >/dev/null 2>&1
            dbFound="yes"
        fi
        if echo "${ptPorts}" | grep -qE "(^|,)6379(,|$)"; then
            printf "${CYAN}  Redis enumeration...${NC}\n"
            ${nmapType} --script redis-info \
                -p6379 --open \
                -oN "nmap/pentest/PT_Redis_Enum_${HOST}.nmap" ${HOST} ${DNSSTRING} >/dev/null 2>&1
            dbFound="yes"
        fi
        [ -n "${dbFound}" ] && printf "${CYAN}  Database enumeration complete${NC}\n"

        # NFS
        if echo "${ptPorts}" | grep -qE "(^|,)2049(,|$)"; then
            printf "${CYAN}  NFS enumeration...${NC}\n"
            ${nmapType} --script nfs-ls,nfs-showmount,nfs-statfs \
                -p2049 --open \
                -oN "nmap/pentest/PT_NFS_Enum_${HOST}.nmap" ${HOST} ${DNSSTRING} >/dev/null 2>&1
            printf "${CYAN}  NFS enumeration complete${NC}\n"
        fi

        # VNC
        if echo "${ptPorts}" | grep -qE "(^|,)(5900|5901)(,|$)"; then
            printf "${CYAN}  VNC enumeration...${NC}\n"
            ${nmapType} --script vnc-info,vnc-title,realvnc-auth-bypass \
                -p5900,5901 --open \
                -oN "nmap/pentest/PT_VNC_Enum_${HOST}.nmap" ${HOST} ${DNSSTRING} >/dev/null 2>&1
            printf "${CYAN}  VNC enumeration complete${NC}\n"
        fi

        # IPSec / VPN
        if echo "${udpPorts}" | grep -qE "(^|,)500(,|$)"; then
            printf "${CYAN}  IKE/IPSec enumeration...${NC}\n"
            ${SUDO_CMD} ${nmapType} -sU --script ike-version \
                -p500 --open \
                -oN "nmap/pentest/PT_IKE_Enum_${HOST}.nmap" ${HOST} ${DNSSTRING} >/dev/null 2>&1
            printf "${CYAN}  IKE enumeration complete${NC}\n"
        fi

        echo
    else
        printf "${YELLOW}No open ports found in SYN scan.${NC}\n"
    fi

    # ═══════════════════════════════════════════════
    # Phase 3: Authentication & Access Checks
    # ═══════════════════════════════════════════════
    printf "${MAGENTA}━━━ Phase 3: Authentication & Default Credentials ━━━${NC}\n\n"

    if [ -n "${ptPorts}" ]; then
        printf "${YELLOW}[3a] Auth category scripts (anonymous access, default creds)...${NC}\n\n"
        nmapProgressBar "${nmapType} --script auth -p${ptPorts} --open \
            -oN nmap/pentest/PT_Auth_${HOST}.nmap ${HOST} ${DNSSTRING}" 3
        echo

        printf "${YELLOW}[3b] Default credentials check...${NC}\n\n"
        ${nmapType} --script http-default-accounts,ftp-anon,mysql-empty-password,ms-sql-empty-password \
            -p${ptPorts} --open \
            -oN "nmap/pentest/PT_DefaultCreds_${HOST}.nmap" ${HOST} ${DNSSTRING} >/dev/null 2>&1
        printf "${CYAN}  Default credential checks complete${NC}\n"
    fi
    echo

    # ═══════════════════════════════════════════════
    # Phase 4: SSL/TLS Assessment
    # ═══════════════════════════════════════════════
    printf "${MAGENTA}━━━ Phase 4: SSL/TLS Security Assessment ━━━${NC}\n\n"

    if [ -n "${ptPorts}" ]; then
        ${nmapType} --script ssl-enum-ciphers,ssl-cert,ssl-heartbleed,ssl-poodle,ssl-ccs-injection,ssl-dh-params,ssl-known-key,tls-ticketbleed \
            -p${ptPorts} --open \
            -oN "nmap/pentest/PT_SSL_${HOST}.nmap" ${HOST} ${DNSSTRING} 2>&1 | \
            grep -E "TLSv|SSLv|VULNERABLE|Grade|WARNING|expired|self-signed|NULL|WEAK|SHA1" || \
            printf "  ${GREEN}No SSL/TLS issues on scanned ports${NC}\n"
    fi
    echo

    # ═══════════════════════════════════════════════
    # Phase 5: Comprehensive Vulnerability Scan
    # ═══════════════════════════════════════════════
    printf "${MAGENTA}━━━ Phase 5: Vulnerability Assessment ━━━${NC}\n\n"

    if [ -n "${ptPorts}" ]; then
        printf "${YELLOW}[5a] Nmap vuln category scripts...${NC}\n\n"
        nmapProgressBar "${nmapType} -sV --script vuln -p${ptPorts} --open \
            -oN nmap/pentest/PT_Vulns_${HOST}.nmap ${HOST} ${DNSSTRING}" 3
        echo

        # vulners
        if ${NMAPPATH} --script-help vulners >/dev/null 2>&1; then
            printf "${YELLOW}[5b] CVE scan (vulners — mincvss=4.0)...${NC}\n\n"
            nmapProgressBar "${nmapType} -sV --script vulners --script-args mincvss=4.0 -p${ptPorts} --open \
                -oN nmap/pentest/PT_CVEs_${HOST}.nmap ${HOST} ${DNSSTRING}" 3
            echo
        fi

        # vulscan
        if ${NMAPPATH} --script-help vulscan >/dev/null 2>&1; then
            printf "${YELLOW}[5c] vulscan CVE database scan...${NC}\n\n"
            nmapProgressBar "${nmapType} -sV --script vulscan/vulscan.nse --script-args vulscandb=cve.csv -p${ptPorts} --open \
                -oN nmap/pentest/PT_Vulscan_${HOST}.nmap ${HOST} ${DNSSTRING}" 3
            echo
        fi

        # Exploit category (safe checks only)
        printf "${YELLOW}[5d] Exploit category scripts (safe)...${NC}\n\n"
        ${nmapType} --script "exploit and safe" -p${ptPorts} --open \
            -oN "nmap/pentest/PT_Exploits_${HOST}.nmap" ${HOST} ${DNSSTRING} >/dev/null 2>&1
        if [ -f "nmap/pentest/PT_Exploits_${HOST}.nmap" ]; then
            grep -E "VULNERABLE|EXPLOITABLE" "nmap/pentest/PT_Exploits_${HOST}.nmap" 2>/dev/null || \
                printf "  ${GREEN}No safe exploits triggered${NC}\n"
        fi
    fi
    echo

    # ═══════════════════════════════════════════════
    # Phase 6: Firewall & IDS Detection
    # ═══════════════════════════════════════════════
    printf "${MAGENTA}━━━ Phase 6: Firewall & Network Security Detection ━━━${NC}\n\n"

    printf "${YELLOW}[6a] ACK scan — stateful firewall detection...${NC}\n"
    ${SUDO_CMD} ${nmapType} -sA -T4 --top-ports 100 \
        -oN "nmap/pentest/PT_ACK_${HOST}.nmap" ${HOST} ${DNSSTRING} 2>&1 | \
        grep -E "filtered|unfiltered|PORT" || true
    echo

    printf "${YELLOW}[6b] IP Protocol scan...${NC}\n"
    ${SUDO_CMD} ${nmapType} -sO --top-ports 10 \
        -oN "nmap/pentest/PT_Protocols_${HOST}.nmap" ${HOST} ${DNSSTRING} 2>&1 | \
        grep -E "^[0-9].*open" || true
    echo

    printf "${YELLOW}[6c] Traceroute with service detection...${NC}\n"
    ${nmapType} --traceroute -sV --top-ports 10 \
        -oN "nmap/pentest/PT_Traceroute_${HOST}.nmap" ${HOST} ${DNSSTRING} 2>&1 | \
        grep -E "HOP|TRACEROUTE|[0-9]\.\.\." || true
    echo

    # ═══════════════════════════════════════════════
    # Phase 7: UDP Scan
    # ═══════════════════════════════════════════════
    printf "${MAGENTA}━━━ Phase 7: UDP Service Discovery ━━━${NC}\n\n"

    ${SUDO_CMD:+${SUDO_CMD} -v} 2>/dev/null
    nmapProgressBar "${SUDO_CMD} ${nmapType} -sU --top-ports 200 --max-retries 1 --open --reason \
        -oN nmap/pentest/PT_UDP_${HOST}.nmap ${HOST} ${DNSSTRING}" 5

    ptUdpPorts="$(awk -vORS=, -F/ '/^[0-9].*open /{print $1}' "nmap/pentest/PT_UDP_${HOST}.nmap" 2>/dev/null | sed 's/.$//')"
    if [ -n "${ptUdpPorts}" ]; then
        echo
        printf "${YELLOW}Running version detection on UDP ports: ${ptUdpPorts}${NC}\n\n"
        ${SUDO_CMD} ${nmapType} -sCVU -p${ptUdpPorts} --open \
            -oN "nmap/pentest/PT_UDP_Extra_${HOST}.nmap" ${HOST} ${DNSSTRING} >/dev/null 2>&1
    fi
    echo

    # ═══════════════════════════════════════════════
    # Pentest Summary Report
    # ═══════════════════════════════════════════════
    printf "${GREEN}═══════════════════════════════════════════════════════════════${NC}\n"
    printf "${GREEN}       PENETRATION TEST SCAN SUMMARY — ${HOST}${NC}\n"
    printf "${GREEN}═══════════════════════════════════════════════════════════════${NC}\n\n"

    summaryFile="nmap/pentest/PT_Summary_${HOST}.txt"
    {
        echo "============================================================"
        echo "PENETRATION TEST SCAN REPORT"
        echo "============================================================"
        echo "Date:   $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Target: ${HOST}"
        echo "OS:     ${osType:-Unknown}"
        echo "Tool:   nmapauto ${VERSION}"
        echo "============================================================"
        echo ""
        echo "=== OPEN TCP PORTS ==="
        if [ -f "nmap/pentest/PT_SYN_${HOST}.nmap" ]; then
            grep "^[0-9].*open" "nmap/pentest/PT_SYN_${HOST}.nmap" || echo "  None"
        fi
        echo ""
        echo "=== OPEN UDP PORTS ==="
        if [ -f "nmap/pentest/PT_UDP_${HOST}.nmap" ]; then
            grep "^[0-9].*open " "nmap/pentest/PT_UDP_${HOST}.nmap" || echo "  None"
        fi
        echo ""
        echo "=== SERVICE VERSIONS ==="
        if [ -f "nmap/pentest/PT_Versions_${HOST}.nmap" ]; then
            grep "^[0-9].*open" "nmap/pentest/PT_Versions_${HOST}.nmap" || echo "  N/A"
        fi
        echo ""
        echo "=== SSL/TLS ISSUES ==="
        if [ -f "nmap/pentest/PT_SSL_${HOST}.nmap" ]; then
            grep -E "VULNERABLE|WEAK|SSLv2|SSLv3|TLSv1\.0|TLSv1\.1|expired|self-signed|NULL|RC4|DES|MD5" \
                "nmap/pentest/PT_SSL_${HOST}.nmap" || echo "  None found"
        fi
        echo ""
        echo "=== VULNERABILITIES ==="
        for f in nmap/pentest/PT_Vulns_${HOST}.nmap nmap/pentest/PT_CVEs_${HOST}.nmap nmap/pentest/PT_Exploits_${HOST}.nmap; do
            if [ -f "$f" ]; then
                grep -E "VULNERABLE|CVE-|EXPLOITABLE" "$f" 2>/dev/null
            fi
        done | sort -u || echo "  None found"
        echo ""
        echo "=== AUTHENTICATION ISSUES ==="
        if [ -f "nmap/pentest/PT_Auth_${HOST}.nmap" ]; then
            grep -iE "anon|guest|empty|default|no auth" "nmap/pentest/PT_Auth_${HOST}.nmap" || echo "  None found"
        fi
        if [ -f "nmap/pentest/PT_DefaultCreds_${HOST}.nmap" ]; then
            grep -iE "valid|credentials|login|success" "nmap/pentest/PT_DefaultCreds_${HOST}.nmap" || true
        fi
        echo ""
        echo "=== FIREWALL/FILTERING ==="
        if [ -f "nmap/pentest/PT_ACK_${HOST}.nmap" ]; then
            grep -cE "filtered" "nmap/pentest/PT_ACK_${HOST}.nmap" | xargs -I{} echo "  {} filtered ports detected"
            grep -cE "unfiltered" "nmap/pentest/PT_ACK_${HOST}.nmap" | xargs -I{} echo "  {} unfiltered ports detected"
        fi
        echo ""
        echo "=== SMB FINDINGS ==="
        if [ -f "nmap/pentest/PT_SMB_Enum_${HOST}.nmap" ]; then
            grep -E "VULNERABLE|share|access|signing" "nmap/pentest/PT_SMB_Enum_${HOST}.nmap" | head -20 || echo "  N/A"
        fi
        echo ""
        echo "============================================================"
        echo "All detailed results in: nmap/pentest/"
        echo "============================================================"
    } | tee "${summaryFile}"

    printf "\n${GREEN}Full pentest report: ${summaryFile}${NC}\n"
    echo; echo; echo
}

# ═══════════════════════════════════════════════════════════════════
# SCAN: Recon Recommendations (Enhanced)
# ═══════════════════════════════════════════════════════════════════
recon() {
    IFS="${NEWLINE}"

    reconRecommend "${HOST}" | tee "nmap/Recon_${HOST}.nmap"
    allRecon="$(grep "${HOST}" "nmap/Recon_${HOST}.nmap" | cut -d " " -f 1 | sort | uniq)"

    for tool in ${allRecon}; do
        if ! type "${tool}" >/dev/null 2>&1; then
            missingTools="$(echo ${missingTools} ${tool} | awk '{$1=$1};1')"
        fi
    done

    if [ -n "${missingTools}" ]; then
        printf "${RED}Missing tools: ${NC}${missingTools}\n"
        printf "\n${RED}Install with:\n"
        printf "${YELLOW}sudo apt install ${missingTools} -y\n"
        printf "${NC}\n\n"
        availableRecon="$(echo "${allRecon}" | tr " " "\n" | awk -vORS=', ' '!/'"$(echo "${missingTools}" | tr " " "|")"'/' | sed 's/..$//')"
    else
        availableRecon="$(echo "${allRecon}" | tr "\n" " " | sed 's/\ /,\ /g' | sed 's/..$//')"
    fi

    secs=30
    count=0

    if [ -n "${availableRecon}" ]; then
        if $SKIP_RECON_PROMPT; then
            runRecon "${HOST}" "All"
        else
            while [ "${reconCommand}" != "!" ]; do
                printf "${YELLOW}\nWhich commands would you like to run?${NC}\nAll (Default), ${availableRecon}, Skip <!>\n\n"
                while [ ${count} -lt ${secs} ]; do
                    tlimit=$((secs - count))
                    printf "\033[2K\rRunning Default in (${tlimit})s: "
                    # Use bash read -t for timeout; fallback for sh/dash
                    if reconCommand="$(bash -c 'read -t 1 input 2>/dev/null && echo "$input"' 2>/dev/null)"; then
                        :
                    else
                        reconCommand=""
                    fi
                    count=$((count + 1))
                    [ -n "${reconCommand}" ] && break
                done
                if echo "${reconCommand}" | grep -qi "^all$" || [ -z "${reconCommand}" ]; then
                    runRecon "${HOST}" "All"
                    reconCommand="!"
                elif echo " ${availableRecon}," | grep -q " ${reconCommand},"; then
                    runRecon "${HOST}" "${reconCommand}"
                    reconCommand="!"
                elif [ "${reconCommand}" = "Skip" ] || [ "${reconCommand}" = "!" ]; then
                    reconCommand="!"
                    echo; echo; echo
                else
                    printf "${NC}\n${RED}Incorrect choice!\n${NC}\n"
                fi
            done
        fi
    else
        printf "${YELLOW}No Recon Recommendations found...\n${NC}\n\n\n"
    fi

    IFS="${origIFS}"
}

# ═══════════════════════════════════════════════════════════════════
# Recon Recommendations (Enhanced with modern tools)
# ═══════════════════════════════════════════════════════════════════
reconRecommend() {
    printf "${GREEN}---------------------Recon Recommendations---------------------${NC}\n\n"

    IFS="${NEWLINE}"

    if [ -f "nmap/Full_Extra_${HOST}.nmap" ]; then
        ports="${allPorts}"
        file="$(cat "nmap/Script_${HOST}.nmap" "nmap/Full_Extra_${HOST}.nmap" 2>/dev/null | grep "open" | grep -v "#" | sort | uniq)"
    elif [ -f "nmap/Script_${HOST}.nmap" ]; then
        ports="${commonPorts}"
        file="$(grep "open" "nmap/Script_${HOST}.nmap" | grep -v "#")"
    fi

    # SMTP
    if echo "${file}" | grep -q "25/tcp"; then
        printf "${NC}\n${YELLOW}SMTP Recon:\n${NC}\n"
        echo "smtp-user-enum -U /usr/share/wordlists/metasploit/unix_users.txt -t \"${HOST}\" | tee \"recon/smtp_user_enum_${HOST}.txt\""
        echo "nmap -Pn -p 25 --script smtp-commands,smtp-enum-users,smtp-open-relay,smtp-vuln-cve2010-4344,smtp-vuln-cve2011-1720,smtp-vuln-cve2011-1764 \"${HOST}\" -oN \"recon/nmap_smtp_${HOST}.txt\""
        echo
    fi

    # DNS
    if echo "${file}" | grep -q "53/tcp" && [ -n "${DNSSERVER}" ]; then
        printf "${NC}\n${YELLOW}DNS Recon:\n${NC}\n"
        echo "host -l \"${HOST}\" \"${DNSSERVER}\" | tee \"recon/hostname_${HOST}.txt\""
        echo "dnsrecon -r \"${subnet}/24\" -n \"${DNSSERVER}\" | tee \"recon/dnsrecon_${HOST}.txt\""
        echo "dnsrecon -r 127.0.0.0/24 -n \"${DNSSERVER}\" | tee \"recon/dnsrecon-local_${HOST}.txt\""
        echo "dig -x \"${HOST}\" @${DNSSERVER} | tee \"recon/dig_${HOST}.txt\""
        echo "dig axfr \"${HOST}\" @${DNSSERVER} | tee \"recon/dig_axfr_${HOST}.txt\""
        echo
    fi

    # Web
    if echo "${file}" | grep -i -q http; then
        printf "${NC}\n${YELLOW}Web Servers Recon:\n${NC}\n"
        for line in ${file}; do
            if echo "${line}" | grep -i -q http; then
                port="$(echo "${line}" | cut -d "/" -f 1)"
                if echo "${line}" | grep -q ssl/http; then
                    urlType='https://'
                    echo "sslscan \"${HOST}:${port}\" | tee \"recon/sslscan_${HOST}_${port}.txt\""
                    echo "nikto -host \"${urlType}${HOST}:${port}\" -ssl | tee \"recon/nikto_${HOST}_${port}.txt\""
                else
                    urlType='http://'
                    echo "nikto -host \"${urlType}${HOST}:${port}\" | tee \"recon/nikto_${HOST}_${port}.txt\""
                fi
                # Directory bruteforcing
                if type ffuf >/dev/null 2>&1; then
                    echo "ffuf -ic -w /usr/share/wordlists/dirb/common.txt -u \"${urlType}${HOST}:${port}/FUZZ\" -mc 200,301,302,403 | tee \"recon/ffuf_${HOST}_${port}.txt\""
                elif type gobuster >/dev/null 2>&1; then
                    echo "gobuster dir -w /usr/share/wordlists/dirb/common.txt -t 30 -u \"${urlType}${HOST}:${port}\" -o \"recon/gobuster_${HOST}_${port}.txt\""
                elif type feroxbuster >/dev/null 2>&1; then
                    echo "feroxbuster -u \"${urlType}${HOST}:${port}\" -w /usr/share/wordlists/dirb/common.txt -o \"recon/feroxbuster_${HOST}_${port}.txt\""
                fi
                # Nuclei if available
                if type nuclei >/dev/null 2>&1; then
                    echo "nuclei -u \"${urlType}${HOST}:${port}\" -severity low,medium,high,critical -o \"recon/nuclei_${HOST}_${port}.txt\""
                fi
                # whatweb
                if type whatweb >/dev/null 2>&1; then
                    echo "whatweb \"${urlType}${HOST}:${port}\" -a 3 | tee \"recon/whatweb_${HOST}_${port}.txt\""
                fi
                echo
            fi
        done

        # CMS detection
        if [ -f "nmap/Script_${HOST}.nmap" ]; then
            cms="$(grep http-generator "nmap/Script_${HOST}.nmap" | cut -d " " -f 2)"
            if [ -n "${cms}" ]; then
                for line in ${cms}; do
                    port="$(sed -n 'H;x;s/\/.*'"${line}"'.*//p' "nmap/Script_${HOST}.nmap")"
                    if ! case "${cms}" in Joomla|WordPress|Drupal) false ;; esac then
                        printf "${NC}\n${YELLOW}CMS Recon:\n${NC}\n"
                    fi
                    case "${cms}" in
                        Joomla!)   echo "joomscan --url \"${HOST}:${port}\" | tee \"recon/joomscan_${HOST}_${port}.txt\"" ;;
                        WordPress) echo "wpscan --url \"${HOST}:${port}\" --enumerate ap,at,u | tee \"recon/wpscan_${HOST}_${port}.txt\"" ;;
                        Drupal)    echo "droopescan scan drupal -u \"${HOST}:${port}\" | tee \"recon/droopescan_${HOST}_${port}.txt\"" ;;
                    esac
                done
            fi
        fi
    fi

    # SNMP
    if [ -f "nmap/UDP_Extra_${HOST}.nmap" ] && grep -q "161/udp.*open" "nmap/UDP_Extra_${HOST}.nmap"; then
        printf "${NC}\n${YELLOW}SNMP Recon:\n${NC}\n"
        echo "snmp-check \"${HOST}\" -c public | tee \"recon/snmpcheck_${HOST}.txt\""
        echo "snmpwalk -Os -c public -v2c \"${HOST}\" | tee \"recon/snmpwalk_${HOST}.txt\""
        echo "onesixtyone -c /usr/share/wordlists/seclists/Discovery/SNMP/common-snmp-community-strings.txt \"${HOST}\" | tee \"recon/onesixtyone_${HOST}.txt\""
        echo
    fi

    # LDAP
    if echo "${file}" | grep -q "389/tcp"; then
        printf "${NC}\n${YELLOW}LDAP Recon:\n${NC}\n"
        echo "ldapsearch -x -h \"${HOST}\" -s base | tee \"recon/ldapsearch_${HOST}.txt\""
        echo "ldapsearch -x -h \"${HOST}\" -b \"\$(grep rootDomainNamingContext \"recon/ldapsearch_${HOST}.txt\" | cut -d ' ' -f2)\" | tee \"recon/ldapsearch_DC_${HOST}.txt\""
        echo "nmap -Pn -p 389 --script ldap-search,ldap-rootdse,ldap-novell-getpass \"${HOST}\" -oN \"recon/nmap_ldap_${HOST}.txt\""
        echo
    fi

    # SMB
    if echo "${file}" | grep -q "445/tcp"; then
        printf "${NC}\n${YELLOW}SMB Recon:\n${NC}\n"
        echo "smbmap -H \"${HOST}\" | tee \"recon/smbmap_${HOST}.txt\""
        echo "smbclient -L \"//${HOST}/\" -U \"guest\"% | tee \"recon/smbclient_${HOST}.txt\""
        echo "crackmapexec smb \"${HOST}\" --shares -u '' -p '' | tee \"recon/cme_smb_${HOST}.txt\"" 2>/dev/null
        if [ "${osType}" = "Windows" ]; then
            echo "nmap -Pn -p445 --script smb-vuln-ms17-010,smb-vuln-ms08-067,smb-vuln-cve-2017-7494,smb-vuln-conficker,smb-double-pulsar-backdoor,smb-enum-shares,smb-enum-users,smb-protocols -oN \"recon/SMB_vulns_${HOST}.txt\" \"${HOST}\""
            echo "enum4linux-ng -A \"${HOST}\" | tee \"recon/enum4linux_${HOST}.txt\"" 2>/dev/null
        elif [ "${osType}" = "Linux" ]; then
            echo "enum4linux -a \"${HOST}\" | tee \"recon/enum4linux_${HOST}.txt\""
        fi
        echo
    elif echo "${file}" | grep -q "139/tcp" && [ "${osType}" = "Linux" ]; then
        printf "${NC}\n${YELLOW}SMB Recon:\n${NC}\n"
        echo "enum4linux -a \"${HOST}\" | tee \"recon/enum4linux_${HOST}.txt\""
        echo
    fi

    # RDP
    if echo "${file}" | grep -q "3389/tcp"; then
        printf "${NC}\n${YELLOW}RDP Recon:\n${NC}\n"
        echo "nmap -Pn -p 3389 --script rdp-enum-encryption,rdp-vuln-ms12-020,rdp-ntlm-info \"${HOST}\" -oN \"recon/nmap_rdp_${HOST}.txt\""
        echo
    fi

    # SSH
    if echo "${file}" | grep -q "22/tcp"; then
        printf "${NC}\n${YELLOW}SSH Recon:\n${NC}\n"
        echo "nmap -Pn -p 22 --script ssh2-enum-algos,ssh-auth-methods,ssh-hostkey \"${HOST}\" -oN \"recon/nmap_ssh_${HOST}.txt\""
        if type ssh-audit >/dev/null 2>&1; then
            echo "ssh-audit \"${HOST}\" | tee \"recon/ssh_audit_${HOST}.txt\""
        fi
        echo
    fi

    # FTP
    if echo "${file}" | grep -q "21/tcp"; then
        printf "${NC}\n${YELLOW}FTP Recon:\n${NC}\n"
        echo "nmap -Pn -p 21 --script ftp-anon,ftp-bounce,ftp-syst,ftp-vsftpd-backdoor,ftp-vuln-cve2010-4221,ftp-proftpd-backdoor \"${HOST}\" -oN \"recon/nmap_ftp_${HOST}.txt\""
        echo
    fi

    # Oracle
    if echo "${file}" | grep -q "1521/tcp"; then
        printf "${NC}\n${YELLOW}Oracle Recon:\n${NC}\n"
        echo "odat sidguesser -s \"${HOST}\" -p 1521"
        echo "odat passwordguesser -s \"${HOST}\" -p 1521 -d XE --accounts-file accounts/accounts-multiple.txt"
        echo "nmap -Pn -p 1521 --script oracle-sid-brute,oracle-tns-version \"${HOST}\" -oN \"recon/nmap_oracle_${HOST}.txt\""
        echo
    fi

    # MySQL
    if echo "${file}" | grep -q "3306/tcp"; then
        printf "${NC}\n${YELLOW}MySQL Recon:\n${NC}\n"
        echo "nmap -Pn -p 3306 --script mysql-info,mysql-enum,mysql-empty-password,mysql-vuln-cve2012-2122 \"${HOST}\" -oN \"recon/nmap_mysql_${HOST}.txt\""
        echo
    fi

    # MSSQL
    if echo "${file}" | grep -q "1433/tcp"; then
        printf "${NC}\n${YELLOW}MSSQL Recon:\n${NC}\n"
        echo "nmap -Pn -p 1433 --script ms-sql-info,ms-sql-config,ms-sql-empty-password,ms-sql-ntlm-info \"${HOST}\" -oN \"recon/nmap_mssql_${HOST}.txt\""
        echo
    fi

    # Redis
    if echo "${file}" | grep -q "6379/tcp"; then
        printf "${NC}\n${YELLOW}Redis Recon:\n${NC}\n"
        echo "nmap -Pn -p 6379 --script redis-info \"${HOST}\" -oN \"recon/nmap_redis_${HOST}.txt\""
        echo
    fi

    # NFS
    if echo "${file}" | grep -q "2049/tcp"; then
        printf "${NC}\n${YELLOW}NFS Recon:\n${NC}\n"
        echo "nmap -Pn -p 2049 --script nfs-ls,nfs-showmount,nfs-statfs \"${HOST}\" -oN \"recon/nmap_nfs_${HOST}.txt\""
        echo "showmount -e \"${HOST}\" | tee \"recon/showmount_${HOST}.txt\""
        echo
    fi

    # VNC
    if echo "${file}" | grep -q "5900/tcp\|5901/tcp"; then
        printf "${NC}\n${YELLOW}VNC Recon:\n${NC}\n"
        echo "nmap -Pn -p 5900,5901 --script vnc-info,vnc-title,realvnc-auth-bypass \"${HOST}\" -oN \"recon/nmap_vnc_${HOST}.txt\""
        echo
    fi

    # Telnet
    if echo "${file}" | grep -q "23/tcp"; then
        printf "${NC}\n${YELLOW}Telnet Recon:\n${NC}\n"
        echo "nmap -Pn -p 23 --script telnet-ntlm-info,telnet-encryption \"${HOST}\" -oN \"recon/nmap_telnet_${HOST}.txt\""
        echo
    fi

    IFS="${origIFS}"
    echo; echo; echo
}

# Run chosen recon commands
runRecon() {
    echo; echo; echo
    printf "${GREEN}---------------------Running Recon Commands--------------------${NC}\n\n"

    IFS="${NEWLINE}"
    mkdir -p recon/

    if [ "$2" = "All" ]; then
        reconCommands="$(grep "${HOST}" "nmap/Recon_${HOST}.nmap")"
    else
        reconCommands="$(grep "${HOST}" "nmap/Recon_${HOST}.nmap" | grep "$2")"
    fi

    for line in ${reconCommands}; do
        currentScan="$(echo "${line}" | cut -d ' ' -f 1)"
        fileName="$(echo "${line}" | awk -F "recon/" '{print $2}')"
        if [ -n "${fileName}" ] && [ ! -f recon/"${fileName}" ]; then
            printf "${NC}\n${YELLOW}Starting ${currentScan} scan\n${NC}\n"
            eval "${line}"
            printf "${NC}\n${YELLOW}Finished ${currentScan} scan\n${NC}\n"
            printf "${YELLOW}=========================\n"
        fi
    done

    IFS="${origIFS}"
    echo; echo; echo
}

# ═══════════════════════════════════════════════════════════════════
# Footer
# ═══════════════════════════════════════════════════════════════════
footer() {
    printf "${GREEN}---------------------Finished all scans------------------------${NC}\n\n"

    elapsedEnd="$(date '+%s')"
    elapsedSeconds=$((elapsedEnd - elapsedStart))

    if [ ${elapsedSeconds} -gt 3600 ]; then
        hours=$((elapsedSeconds / 3600))
        minutes=$(((elapsedSeconds % 3600) / 60))
        seconds=$(((elapsedSeconds % 3600) % 60))
        printf "${YELLOW}Completed in ${hours} hour(s), ${minutes} minute(s) and ${seconds} second(s)\n"
    elif [ ${elapsedSeconds} -gt 60 ]; then
        minutes=$(((elapsedSeconds % 3600) / 60))
        seconds=$(((elapsedSeconds % 3600) % 60))
        printf "${YELLOW}Completed in ${minutes} minute(s) and ${seconds} second(s)\n"
    else
        printf "${YELLOW}Completed in ${elapsedSeconds} seconds\n"
    fi

    printf "${NC}\n"
    printf "${CYAN}Results saved in: $(pwd)/${NC}\n\n"
}

# ═══════════════════════════════════════════════════════════════════
# Main Logic
# ═══════════════════════════════════════════════════════════════════
main() {
    assignPorts "${HOST}"
    header

    case "${TYPE}" in
        [Nn]etwork)  networkScan "${HOST}" ;;
        [Pp]ort)     portScan "${HOST}" ;;
        [Ss]cript)
            [ ! -f "nmap/Port_${HOST}.nmap" ] && portScan "${HOST}"
            scriptScan "${HOST}"
            ;;
        [Ff]ull)     fullScan "${HOST}" ;;
        [Uu][Dd][Pp]) UDPScan "${HOST}" ;;
        [Vv]ulns)
            [ ! -f "nmap/Port_${HOST}.nmap" ] && portScan "${HOST}"
            vulnsScan "${HOST}"
            ;;
        [Ss][Ss][Ll])
            [ ! -f "nmap/Port_${HOST}.nmap" ] && portScan "${HOST}"
            sslScan "${HOST}"
            ;;
        [Ff]irewall)
            [ ! -f "nmap/Port_${HOST}.nmap" ] && portScan "${HOST}"
            firewallScan "${HOST}"
            ;;
        [Pp][Cc][Ii])
            pciScan "${HOST}"
            ;;
        [Pp]entest)
            pentestScan "${HOST}"
            ;;
        [Rr]econ)
            [ ! -f "nmap/Port_${HOST}.nmap" ] && portScan "${HOST}"
            [ ! -f "nmap/Script_${HOST}.nmap" ] && scriptScan "${HOST}"
            recon "${HOST}"
            ;;
        [Aa]ll)
            portScan "${HOST}"
            scriptScan "${HOST}"
            fullScan "${HOST}"
            UDPScan "${HOST}"
            vulnsScan "${HOST}"
            sslScan "${HOST}"
            firewallScan "${HOST}"
            pciScan "${HOST}"
            pentestScan "${HOST}"
            recon "${HOST}"
            ;;
    esac

    footer
}

# ═══════════════════════════════════════════════════════════════════
# Input Validation & Entry Point
# ═══════════════════════════════════════════════════════════════════
# Show help if -h flag or missing required args
if [ "${SHOW_HELP}" = "true" ] || { [ -z "${TYPE}" ] && [ -z "${HOST}" ]; }; then
    usage
fi

if [ -z "${TYPE}" ] || [ -z "${HOST}" ]; then
    usage
fi

# Validate host is IP or domain
if ! expr "${HOST}" : '^\([0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\)$' >/dev/null && \
   ! expr "${HOST}" : '^\(\([[:alnum:]-]\{1,63\}\.\)*[[:alpha:]]\{2,6\}\)$' >/dev/null; then
    printf "${RED}\nInvalid IP or URL!\n"
    usage
fi

# Also accept CIDR notation for network scans
if expr "${HOST}" : '^\([0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/[0-9]\{1,2\}\)$' >/dev/null; then
    if ! echo "${TYPE}" | grep -qi "network"; then
        printf "${RED}\nCIDR notation is only supported for Network scan type!\n"
        usage
    fi
fi

# Validate scan type
if ! case "${TYPE}" in [Nn]etwork|[Pp]ort|[Ss]cript|[Ff]ull|[Uu][Dd][Pp]|[Vv]ulns|[Rr]econ|[Ss][Ss][Ll]|[Ff]irewall|[Pp][Cc][Ii]|[Pp]entest|[Aa]ll) false;; esac then
    mkdir -p "${OUTPUTDIR}" && cd "${OUTPUTDIR}" && mkdir -p nmap/ || usage
    main | tee "nmapauto_${HOST}_${TYPE}.txt"
else
    printf "${RED}\nInvalid Type!\n"
    usage
fi
