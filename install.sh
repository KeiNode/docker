#!/usr/bin/env bash
# install.sh - Robust Docker installer for non-RedHat Linux (Ubuntu/Debian/Alpine/Arch/openSUSE)
# Usage: sudo ./install.sh
set -euo pipefail

# Colors
CYAN='\033[96m'
GREEN='\033[32m'
RED='\033[31m'
YELLOW='\033[33m'
NC='\033[0m'

PKG_DIR="/opt/docker-packages"
trap 'rc=$?; if [ $rc -ne 0 ]; then echo -e "${RED}[ERROR] Installer failed (exit $rc)${NC}"; fi; exit $rc' EXIT

print_banner() {
  echo -e "${PURPLE}"
  cat <<'BANNER'
███████╗ █████╗ ███╗   ██╗      ██╗██╗      ██████╗  ██████╗  ██████╗██╗  ██╗███████╗██████╗           
██╔════╝██╔══██╗████╗  ██║     ██╔╝╚██╗     ██╔══██╗██╔═══██╗██╔════╝██║ ██╔╝██╔════╝██╔══██╗          
█████╗  ███████║██╔██╗ ██║    ██╔╝  ╚██╗    ██║  ██║██║   ██║██║     █████╔╝ █████╗  ██████╔╝    █████╗
██╔══╝  ██╔══██║██║╚██╗██║    ╚██╗  ██╔╝    ██║  ██║██║   ██║██║     ██╔═██╗ ██╔══╝  ██╔══██╗    ╚════╝
██║     ██║  ██║██║ ╚████║     ╚██╗██╔╝     ██████╔╝╚██████╔╝╚██████╗██║  ██╗███████╗██║  ██║          
╚═╝     ╚═╝  ╚═╝╚═╝  ╚═══╝      ╚═╝╚═╝      ╚═════╝  ╚═════╝  ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝          
                                                                                                       
BANNER
  echo -e "${NC}"
}

require_root() {
  if [[ $(id -u) -ne 0 ]]; then
    echo -e "${RED}This script must be run as root. Use sudo.${NC}" >&2
    exit 1
  fi
}

fix_line_endings() {
  # harmless if not installed
  if command -v dos2unix >/dev/null 2>&1; then
    dos2unix "$0" >/dev/null 2>&1 || true
  else
    # fallback: remove CR (\r) from this script in-place as best-effort
    sed -i 's/\r$//' "$0" 2>/dev/null || true
  fi
}

ask_confirm_default_n() {
  local prompt="$1"
  local reply
  read -r -p "$prompt [y/N]: " reply
  reply=${reply:-N}
  reply=$(echo "$reply" | tr '[:upper:]' '[:lower:]')
  if [[ "$reply" =~ ^(y|yes)$ ]]; then
    return 0
  else
    return 1
  fi
}

detect_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "${ID,,}"
  else
    echo "unknown"
  fi
}

# Choose a non-root user to add to docker group
choose_user_to_add() {
  # 1) prefer SUDO_USER
  if [ -n "${SUDO_USER-}" ] && [ "${SUDO_USER-}" != "root" ]; then
    printf '%s\n' "$SUDO_USER"
    return 0
  fi
  # 2) if USER env set and not root
  if [ -n "${USER-}" ] && [ "${USER-}" != "root" ]; then
    printf '%s\n' "$USER"
    return 0
  fi
  # 3) pick first real user with UID >=1000 (exclude nobody)
  if command -v awk >/dev/null 2>&1; then
    candidate=$(awk -F: '($3>=1000)&&($1!="nobody"){print $1; exit}' /etc/passwd || true)
    if [ -n "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi
  # 4) fail
  return 1
}

add_user_to_docker_group() {
  local user="$1"
  if id -nG "$user" | grep -qw docker; then
    echo -e "${YELLOW}[INFO] User '$user' already in group 'docker'.${NC}"
    return 0
  fi

  # create docker group if needed
  if ! getent group docker >/dev/null 2>&1; then
    if command -v groupadd >/dev/null 2>&1; then
      groupadd docker || true
    fi
  fi

  # add user to group
  if command -v usermod >/dev/null 2>&1; then
    usermod -aG docker "$user" || {
      echo -e "${RED}[WARN] Failed to add $user to docker via usermod. Trying gpasswd...${NC}"
      gpasswd -a "$user" docker || true
    }
  elif command -v gpasswd >/dev/null 2>&1; then
    gpasswd -a "$user" docker || true
  else
    echo -e "${RED}[WARN] Could not find usermod/gpasswd to add $user to docker group. Please add manually.${NC}"
    return 2
  fi

  echo -e "${YELLOW}[INFO] Added user '$user' to group 'docker'.${NC}"
  echo -e "${YELLOW}[INFO] User may need to re-login (or run: newgrp docker) for changes to take effect.${NC}"
  return 0
}

install_on_debian_ubuntu() {
  echo -e "${YELLOW}[INFO] Installing prerequisites (Debian/Ubuntu)...${NC}"
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg lsb-release apt-transport-https

  mkdir -p /etc/apt/keyrings
  chmod 0755 /etc/apt/keyrings

  # fetch and store key
  if command -v gpg >/dev/null 2>&1; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  else
    apt-get install -y gnupg
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  fi
  chmod a+r /etc/apt/keyrings/docker.gpg || true

  ARCH=$(dpkg --print-architecture)
  CODENAME=$(lsb_release -cs 2>/dev/null || echo "")
  if [ -z "$CODENAME" ] && [ -n "${VERSION_CODENAME-}" ]; then
    CODENAME="$VERSION_CODENAME"
  fi
  if [ -z "$CODENAME" ]; then
    echo -e "${RED}[ERROR] Could not determine distro codename.${NC}" >&2
    exit 1
  fi
  DIST_ID=$(. /etc/os-release; echo "$ID")

  echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$DIST_ID $CODENAME stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null

  apt-get update -y
  echo -e "${YELLOW}[INFO] Installing Docker packages...${NC}"
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # copy apt cache debs (best-effort)
  if [ -d /var/cache/apt/archives ]; then
    cp -a /var/cache/apt/archives/*.deb "$PKG_DIR" 2>/dev/null || true
  fi
}

install_on_alpine() {
  echo -e "${YELLOW}[INFO] Installing Docker (Alpine)...${NC}"
  apk update
  apk add --no-cache docker openrc
  # openrc: ensure docker starts
  if command -v rc-update >/dev/null 2>&1; then
    rc-update add docker default || true
  fi
}

install_on_arch() {
  echo -e "${YELLOW}[INFO] Installing Docker (Arch)...${NC}"
  pacman -Sy --noconfirm docker || true
}

install_on_opensuse() {
  echo -e "${YELLOW}[INFO] Installing Docker (openSUSE/SUSE)...${NC}"
  zypper refresh
  zypper install -y docker || true
}

enable_and_start_docker() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable --now docker || true
  else
    # fallback start
    if command -v service >/dev/null 2>&1; then
      service docker start || true
    fi
  fi
}

validate_install() {
  if command -v docker >/dev/null 2>&1; then
    DOCKER_VER=$(docker --version 2>/dev/null || echo "(unknown)")
    echo -e "${YELLOW}[INFO] Docker installed: ${DOCKER_VER}${NC}"
  else
    echo -e "${RED}[ERROR] Docker binary not found after installation.${NC}" >&2
    exit 1
  fi
}

main() {
  require_root
  fix_line_endings
  print_banner

  if ! ask_confirm_default_n "Do you next installation?"; then
    echo -e "${YELLOW}Installation canceled by user.${NC}"
    # successful cancel -> exit 0 (trap won't treat as error)
    trap - EXIT
    exit 0
  fi

  mkdir -p "$PKG_DIR"
  chown root:root "$PKG_DIR"
  chmod 0755 "$PKG_DIR"
  echo -e "${YELLOW}[INFO] Artefak / packages will be stored at: ${PKG_DIR}${NC}"

  OS=$(detect_os)
  echo -e "${YELLOW}[INFO] Detected OS: ${OS}${NC}"

  case "$OS" in
    ubuntu|debian)
      install_on_debian_ubuntu
      ;;
    alpine)
      install_on_alpine
      ;;
    arch)
      install_on_arch
      ;;
    opensuse*|suse)
      install_on_opensuse
      ;;
    fedora|centos|rhel|rocky|almalinux)
      echo -e "${RED}[ERROR] RedHat-family distro detected. This installer is for non-RedHat systems. Aborting.${NC}" >&2
      exit 2
      ;;
    *)
      echo -e "${RED}[ERROR] Unsupported or unknown distribution: ${OS}.${NC}" >&2
      exit 3
      ;;
  esac

  enable_and_start_docker
  validate_install

  # Add user to docker group so docker can be run without sudo
  if user_to_add=$(choose_user_to_add); then
    add_user_to_docker_group "$user_to_add" || true
  else
    echo -e "${YELLOW}[WARN] Could not determine a non-root user to add to 'docker' group. Please add a user manually:${NC}"
    echo -e "${YELLOW}  sudo usermod -aG docker <username>${NC}"
  fi

  # Final inline success message (green single-line)
  echo -e "${GREEN}INSTALLATION SUCCESS YEAYY!!!${NC}"

  # all good: disable trap exit error message
  trap - EXIT
  return 0
}

main "$@"
