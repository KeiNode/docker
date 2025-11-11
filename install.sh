#!/usr/bin/env bash
# install.sh - Docker installer for Debian/Ubuntu
# Author: AZ.L
# Description: Interactive script to install Docker, configure data-root, add/create a user to run Docker without sudo,
# and display a clean banner with check/cross feedback.

set -o pipefail
set -u

# Colors
BLUE="\e[34m"
CYAN="\e[36m"
WHITE="\e[97m"
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
RESET="\e[0m"

# Globals
OS=""
OS_VERSION=""
ERR_COUNT=0
LOGFILE="/tmp/install-docker-azl.log"
:> "$LOGFILE"

log(){
  echo "$(date +'%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOGFILE"
}

print_banner(){
  printf "%b\n" "${BLUE}┌──────────────────────────────────┐${RESET}"
  printf "%b\n" "${BLUE}│                                  │${RESET}"
  printf "%b\n" "${BLUE}│       ${WHITE}A.L${BLUE}                       │${RESET}"
  printf "%b\n" "${BLUE}└──────────────────────────────────┘${RESET}"
  printf "%b\n" ""
  printf "%b\n" "${WHITE}────────────────────────────────────────────────────────${RESET}"
  printf "%b\n" "                       ${CYAN}DOCKER | A.Z.L${RESET}"
  printf "%b\n" "${WHITE}────────────────────────────────────────────────────────${RESET}"
  printf "%b\n" ""
}

# Print success or error with consistent symbols
ok(){
  printf '%b\n' "${GREEN}[✔]${RESET} $*"
}
err(){
  printf '%b\n' "${RED}[✖]${RESET} $*"
}

# Detect OS
detect_os(){
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
      ubuntu|debian)
        OS="$ID"
        OS_VERSION="$VERSION_ID"
        ;;
      *)
        log "Unsupported OS: $ID"
        err "Sorry: this script supports only Ubuntu and Debian."
        exit 1
        ;;
    esac
  else
    err "Unable to detect OS."
    exit 1
  fi
  log "Detected OS=$OS version=$OS_VERSION"
  ok "Detected OS: $OS $OS_VERSION"
}

# Run command and print check/cross
run_and_check(){
  desc="$1"
  shift || true
  if "$@" >>"$LOGFILE" 2>&1; then
    ok "$desc"
    return 0
  else
    err "$desc (see $LOGFILE)"
    ERR_COUNT=$((ERR_COUNT+1))
    return 1
  fi
}

# Install prerequisites, add repo and install docker
install_docker(){
  ok "Updating apt cache..."
  run_and_check "apt update" apt-get update -y

  ok "Installing prerequisites..."
  run_and_check "install apt-transport-https ca-certificates curl gnupg lsb-release" \
    apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

  ok "Adding Docker GPG key..."
  run_and_check "add Docker GPG key" bash -c "curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg"

  ok "Setting up Docker repository..."
  repo_line="deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$OS $(lsb_release -cs) stable"
  if echo "$repo_line" > /etc/apt/sources.list.d/docker.list 2>>"$LOGFILE"; then
    ok "wrote /etc/apt/sources.list.d/docker.list"
  else
    err "failed to write docker.list (see $LOGFILE)"
    ERR_COUNT=$((ERR_COUNT+1))
  fi

  ok "Refreshing apt cache after adding repo..."
  run_and_check "apt update (after adding repo)" apt-get update -y

  ok "Installing Docker packages..."
  run_and_check "install docker packages (docker-ce docker-ce-cli containerd.io)" \
    apt-get install -y docker-ce docker-ce-cli containerd.io
}

# Configure data-root (safe default: /opt/docker-data)
configure_data_root(){
  SAFE_DEFAULT="/opt/docker-data"
  printf "\nDefault recommended Docker data directory: %b%s%b\n" "$CYAN" "$SAFE_DEFAULT" "$RESET"
  read -r -p "Use this location? [Y/n]: " use_safe
  use_safe=${use_safe:-Y}

  if [[ "$use_safe" =~ ^[Nn] ]]; then
    read -r -p "Enter a custom path for data-root (e.g. /mnt/docker-data): " custom_path
    DATA_ROOT="$custom_path"
  else
    DATA_ROOT="$SAFE_DEFAULT"
  fi

  run_and_check "create data-root $DATA_ROOT" bash -c "mkdir -p '$DATA_ROOT' && chown root:root '$DATA_ROOT' && chmod 711 '$DATA_ROOT'"

  mkdir -p /etc/docker
  if cat > /etc/docker/daemon.json <<EOF
{
  "data-root": "$DATA_ROOT",
  "log-driver": "json-file",
  "log-opts": {"max-size": "10m", "max-file": "3"}
}
EOF
  then
    ok "wrote /etc/docker/daemon.json"
  else
    err "failed to write /etc/docker/daemon.json"
  fi

  run_and_check "reload systemd" systemctl daemon-reload || true
  run_and_check "enable docker service" systemctl enable docker || true
  run_and_check "start docker service" systemctl restart docker || true
}

# Create or add a user to docker group for running without sudo
create_or_add_user(){
  printf "\nTo run docker without sudo, we will add a user to the 'docker' group.\n"
  DEFAULT_USER_NAME="docker"
  read -r -p "Create/use a user named '${DEFAULT_USER_NAME}'? [Y/n]: " use_default
  use_default=${use_default:-Y}
  if [[ "$use_default" =~ ^[Yy] ]]; then
    TARGET_USER="$DEFAULT_USER_NAME"
    if id -u "$TARGET_USER" >/dev/null 2>&1; then
      log "User $TARGET_USER already exists. Adding to docker group."
      run_and_check "add existing user $TARGET_USER to docker group" usermod -aG docker "$TARGET_USER"
    else
      run_and_check "create system user $TARGET_USER (nologin)" useradd -m -s /usr/sbin/nologin "$TARGET_USER"
      run_and_check "add $TARGET_USER to docker group" usermod -aG docker "$TARGET_USER"
    fi
  else
    read -r -p "Enter the username to add to the docker group: " TARGET_USER
    if [ -z "$TARGET_USER" ]; then
      printf "%b\n" "${YELLOW}Empty username — skipping user add.${RESET}"
      log "User add skipped (empty name)"
      return
    fi
    if id -u "$TARGET_USER" >/dev/null 2>&1; then
      run_and_check "add existing user $TARGET_USER to docker group" usermod -aG docker "$TARGET_USER"
    else
      read -r -p "User not found. Create new user named '$TARGET_USER'? [Y/n]: " create_user_confirm
      create_user_confirm=${create_user_confirm:-Y}
      if [[ "$create_user_confirm" =~ ^[Yy] ]]; then
        run_and_check "create user $TARGET_USER" useradd -m -s /bin/bash "$TARGET_USER"
        run_and_check "add $TARGET_USER to docker group" usermod -aG docker "$TARGET_USER"
      else
        printf "%b\n" "${YELLOW}User addition canceled.${RESET}"
        log "User add cancelled"
      fi
    fi
  fi

  if id -u "$TARGET_USER" >/dev/null 2>&1; then
    ok "User '$TARGET_USER' is now a member of the 'docker' group."
    printf "%b\n" "${YELLOW}Note: to apply, the user must log out and back in (or run: newgrp docker).${RESET}"
  fi
}

# Quick docker health check
check_docker_health(){
  printf "\nChecking Docker status...\n"
  if docker info >/dev/null 2>&1; then
    ok "Docker is running and responding."
  else
    err "Docker is not responding. Check service and logs in $LOGFILE"
  fi
}

main(){
  print_banner
  detect_os

  echo ""
  read -r -p "Continue to install Docker on this system? [Y/n]: " proceed
  proceed=${proceed:-Y}
  if [[ ! "$proceed" =~ ^[Yy] ]]; then
    printf "%b\n" "${YELLOW}Cancelled by user.${RESET}"
    exit 0
  fi

  install_docker

  if [ $ERR_COUNT -gt 0 ]; then
    printf "\n%b\n" "${YELLOW}There were some warnings/errors during installation. See $LOGFILE for details.${RESET}"
  fi

  configure_data_root
  create_or_add_user
  check_docker_health

  if [ $ERR_COUNT -eq 0 ]; then
    printf "\n%b\n" "${GREEN}SUCCESSFULLY INSTALLED DOCKER ON YOUR SYSTEM. YAY!${RESET}"
  else
    printf "\n%b\n" "${YELLOW}Installation completed with ${ERR_COUNT} warnings/errors. Check $LOGFILE for details.${RESET}"
  fi

  echo ""
  printf "%b\n" "${CYAN}Author: AZ.L${RESET}"
  printf "%b\n" "${WHITE}Thank you for using this installer. Good luck!${RESET}"
  log "Finish. ERR_COUNT=$ERR_COUNT"
}

# Run
main "$@"
