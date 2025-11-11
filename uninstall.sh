#!/usr/bin/env bash
# uninstall.sh - Docker uninstaller for Debian/Ubuntu
# Author: AZ.L
# Description: Interactive script to completely uninstall Docker from the system.

set -o pipefail

# Colors
BLUE="\e[34m"
CYAN="\e[36m"
WHITE="\e[97m"
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
RESET="\e[0m"

# Globals
LOGFILE="/tmp/uninstall-docker-azl.log"
:> "$LOGFILE"

log(){
  echo "$(date +'%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOGFILE"
}

run_and_check(){
  desc="$1"; shift
  if "$@" >> "$LOGFILE" 2>&1; then
    printf "%b\n" "${GREEN}[✔]${RESET} $desc"
    log "OK: $desc"
  else
    printf "%b\n" "${RED}[✖]${RESET} $desc (see $LOGFILE)"
    log "ERR: $desc"
  fi
}

print_banner(){
  printf "%b\n" "${BLUE}───────────────────────────────────────────────${RESET}"
  printf "%b\n" "${CYAN}           DOCKER UNINSTALLER | A.Z.L${RESET}"
  printf "%b\n" "${BLUE}───────────────────────────────────────────────${RESET}\n"
}

confirm_uninstall(){
  read -r -p "Are you sure you want to uninstall Docker? [y/N]: " confirm
  confirm=${confirm:-N}
  if [[ ! "$confirm" =~ ^[Yy] ]]; then
    echo -e "${YELLOW}Uninstallation cancelled by user.${RESET}"
    exit 0
  fi
}

uninstall_docker(){
  echo -e "\n${CYAN}Starting Docker uninstallation...${RESET}\n"

  run_and_check "Stopping Docker services" systemctl stop docker docker.socket containerd || true

  run_and_check "Removing Docker packages" apt-get purge -y docker-ce docker-ce-cli containerd.io docker-compose-plugin || true

  run_and_check "Removing Docker dependencies" apt-get autoremove -y --purge || true

  run_and_check "Deleting Docker directories" bash -c "rm -rf /var/lib/docker /var/lib/containerd /etc/docker /opt/docker-data" || true

  run_and_check "Deleting Docker group if exists" bash -c "getent group docker && groupdel docker || true"

  echo -e "\n${GREEN}All Docker components have been removed successfully.${RESET}\n"
}

print_goodbye(){
  echo -e "${BLUE}┌───────────────────────────────────────────────┐${RESET}"
  echo -e "${BLUE}│${WHITE}                   Bye, User!                  ${BLUE}│${RESET}"
  echo -e "${BLUE}└───────────────────────────────────────────────┘${RESET}\n"
}

main(){
  print_banner
  confirm_uninstall
  uninstall_docker
  print_goodbye
}

main "$@"
