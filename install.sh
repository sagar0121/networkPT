#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# nmapauto — Installer Script
# Installs nmapauto globally and optionally installs all dependencies
# ═══════════════════════════════════════════════════════════════

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo
printf "${BOLD}${GREEN}nmapauto — Installer${NC}\n"
printf "${GREEN}═══════════════════════════════════════${NC}\n\n"

# ─── Detect package manager ───
detect_pm() {
    if command -v apt >/dev/null 2>&1; then
        PM="apt"
        INSTALL="sudo apt install -y"
        UPDATE="sudo apt update"
    elif command -v dnf >/dev/null 2>&1; then
        PM="dnf"
        INSTALL="sudo dnf install -y"
        UPDATE="sudo dnf check-update"
    elif command -v yum >/dev/null 2>&1; then
        PM="yum"
        INSTALL="sudo yum install -y"
        UPDATE=""
    elif command -v pacman >/dev/null 2>&1; then
        PM="pacman"
        INSTALL="sudo pacman -S --noconfirm"
        UPDATE="sudo pacman -Sy"
    elif command -v brew >/dev/null 2>&1; then
        PM="brew"
        INSTALL="brew install"
        UPDATE="brew update"
    else
        PM="unknown"
    fi
}

detect_pm

# ─── Step 1: Check nmap ───
printf "${YELLOW}[1/4] Checking nmap...${NC}\n"
if command -v nmap >/dev/null 2>&1; then
    nmapVer="$(nmap --version 2>/dev/null | head -1)"
    printf "  ${GREEN}Found: ${nmapVer}${NC}\n"
else
    printf "  ${RED}nmap not found!${NC}\n"
    if [ "${PM}" != "unknown" ]; then
        printf "  ${YELLOW}Installing nmap...${NC}\n"
        [ -n "${UPDATE}" ] && ${UPDATE} >/dev/null 2>&1
        ${INSTALL} nmap
    else
        printf "  ${RED}Please install nmap manually.${NC}\n"
        exit 1
    fi
fi
echo

# ─── Step 2: Install nmapauto globally ───
printf "${YELLOW}[2/4] Installing nmapauto to /usr/local/bin/...${NC}\n"
if [ -f "${SCRIPT_DIR}/nmapauto.sh" ]; then
    sudo cp "${SCRIPT_DIR}/nmapauto.sh" /usr/local/bin/nmapauto
    sudo chmod +x /usr/local/bin/nmapauto
    printf "  ${GREEN}Installed: /usr/local/bin/nmapauto${NC}\n"
    printf "  ${CYAN}You can now run 'nmapauto' from anywhere${NC}\n"
else
    printf "  ${RED}nmapauto.sh not found in current directory!${NC}\n"
    exit 1
fi
echo

# ─── Step 3: Install vulners.nse ───
printf "${YELLOW}[3/4] Checking nmap NSE scripts...${NC}\n"
if nmap --script-help vulners >/dev/null 2>&1; then
    printf "  ${GREEN}vulners.nse: installed${NC}\n"
else
    printf "  ${YELLOW}vulners.nse: not found — installing...${NC}\n"
    NMAP_SCRIPTS="$(nmap --script-help default 2>/dev/null | grep 'NSE script' | head -1 | sed 's|/scripts/.*|/scripts/|')"
    if [ -z "${NMAP_SCRIPTS}" ]; then
        NMAP_SCRIPTS="/usr/share/nmap/scripts/"
    fi
    if [ -d "${NMAP_SCRIPTS}" ]; then
        sudo curl -sL https://raw.githubusercontent.com/vulnersCom/nmap-vulners/master/vulners.nse \
            -o "${NMAP_SCRIPTS}/vulners.nse" 2>/dev/null && \
            sudo nmap --script-updatedb >/dev/null 2>&1 && \
            printf "  ${GREEN}vulners.nse: installed${NC}\n" || \
            printf "  ${RED}Failed to install vulners.nse — install manually${NC}\n"
    fi
fi
echo

# ─── Step 4: Optional tools ───
printf "${YELLOW}[4/4] Install optional tools?${NC}\n"
printf "  These enhance Recon and SSL scans but are NOT required.\n"
printf "  Package manager detected: ${CYAN}${PM}${NC}\n\n"

if [ "${PM}" = "unknown" ]; then
    printf "  ${RED}No supported package manager found. Install optional tools manually.${NC}\n"
    echo
else
    printf "  Install all optional tools? [y/N]: "
    read -r answer
    if [ "${answer}" = "y" ] || [ "${answer}" = "Y" ]; then
        printf "\n  ${YELLOW}Installing optional tools...${NC}\n\n"
        [ -n "${UPDATE}" ] && ${UPDATE} >/dev/null 2>&1

        # Tools available via apt/dnf/yum
        TOOLS="sslscan nikto whatweb enum4linux smbmap smbclient ssh-audit dnsutils"

        # Try each tool — some may not be available on all distros
        for tool in ${TOOLS}; do
            printf "  Installing ${tool}... "
            ${INSTALL} "${tool}" >/dev/null 2>&1 && \
                printf "${GREEN}OK${NC}\n" || \
                printf "${YELLOW}not available${NC}\n"
        done

        # Tools with different package names
        printf "  Installing snmp tools... "
        ${INSTALL} snmp snmp-check onesixtyone >/dev/null 2>&1 && \
            printf "${GREEN}OK${NC}\n" || printf "${YELLOW}partial${NC}\n"

        printf "  Installing ldap-utils... "
        ${INSTALL} ldap-utils >/dev/null 2>&1 && \
            printf "${GREEN}OK${NC}\n" || printf "${YELLOW}not available${NC}\n"

        printf "  Installing dnsrecon... "
        ${INSTALL} dnsrecon >/dev/null 2>&1 && \
            printf "${GREEN}OK${NC}\n" || printf "${YELLOW}not available${NC}\n"

        printf "  Installing testssl.sh... "
        ${INSTALL} testssl.sh >/dev/null 2>&1 && \
            printf "${GREEN}OK${NC}\n" || printf "${YELLOW}not available${NC}\n"

        printf "  Installing ffuf... "
        ${INSTALL} ffuf >/dev/null 2>&1 && \
            printf "${GREEN}OK${NC}\n" || printf "${YELLOW}not available${NC}\n"

        printf "  Installing gobuster... "
        ${INSTALL} gobuster >/dev/null 2>&1 && \
            printf "${GREEN}OK${NC}\n" || printf "${YELLOW}not available${NC}\n"

        printf "  Installing nfs-common... "
        ${INSTALL} nfs-common >/dev/null 2>&1 && \
            printf "${GREEN}OK${NC}\n" || printf "${YELLOW}not available${NC}\n"

        printf "  Installing smtp-user-enum... "
        ${INSTALL} smtp-user-enum >/dev/null 2>&1 && \
            printf "${GREEN}OK${NC}\n" || printf "${YELLOW}not available${NC}\n"

        printf "  Installing wpscan... "
        ${INSTALL} wpscan >/dev/null 2>&1 && \
            printf "${GREEN}OK${NC}\n" || printf "${YELLOW}not available${NC}\n"

        echo
    else
        printf "\n  ${CYAN}Skipped. You can install them later with:${NC}\n"
        printf "  sudo apt install sslscan nikto ffuf whatweb enum4linux smbmap ssh-audit\n"
    fi
fi

# ─── Done ───
echo
printf "${BOLD}${GREEN}═══════════════════════════════════════${NC}\n"
printf "${BOLD}${GREEN}  Installation Complete!${NC}\n"
printf "${BOLD}${GREEN}═══════════════════════════════════════${NC}\n\n"
printf "  Run: ${CYAN}nmapauto -h${NC}  for full help\n"
printf "  Run: ${CYAN}nmapauto -H <target> -t All${NC}  to start scanning\n\n"
