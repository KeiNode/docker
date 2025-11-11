#!/usr/bin/env bash
# install.sh - Installer Docker untuk Debian / Ubuntu
# Author: AZ.L
# Deskripsi: Script interaktif untuk menginstall Docker, mengatur data-root, membuat/menambahkan user untuk menjalankan Docker tanpa sudo,
# dan menampilkan banner + animasi progress.

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
OS=""
OS_VERSION=""
ERR_COUNT=0
LOGFILE="/tmp/install-docker-azl.log"
:> "$LOGFILE"

log(){
  echo "$(date +'%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOGFILE"
}

print_banner(){
  printf "%b\n" "${BLUE}             ┌──────────────────────────────────┐"
  printf "%b\n" "${BLUE}             │                                  │"
  printf "%b\n" "${BLUE}             │          █████╗   ██╗            │"
  printf "%b\n" "${BLUE}             │         ██╔══██╗  ██║            │"
  printf "%b\n" "${BLUE}             │         ███████║  ██║            │"
  printf "%b\n" "${BLUE}             │         ██╔══██║  ██║            │"
  printf "%b\n" "${BLUE}             │         ██║  ██║  ███████╗       │"
  printf "%b\n" "${BLUE}             │         ╚═╝  ╚═╝  ╚══════╝       │"
  printf "%b\n" "${BLUE}             │                                  │"
  printf "%b\n" "${BLUE}             │       ${WHITE}A.L${BLUE}         │"
  printf "%b\n" "${BLUE}             └──────────────────────────────────┘${RESET}\n"

  printf "%b\n" "${BLUE}____________________________"
  printf "%b\n" "< Halo dari Docker | A.Z.L ! >"
  printf "%b\n" " ----------------------------"
  printf "%b\n" "  \\"
  printf "%b\n" "   \\"
  printf "%b\n" "        ##         ."
  printf "%b\n" "      ## ## ## =="
  printf "%b\n" "    ## ## ## ## ==="
  printf "%b\n" "\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\\___/ ==="
  printf "%b\n" "~~~ {~~ ~~~~ ~~~ ~~~~ ~~ ~ / ===-- ~~~\\"
  printf "%b\n" "     \\______ o __/"
  printf "%b\n" "      \\ \\ __/"
  printf "%b\n" "       \\____\\______/\n"

  printf "%b\n" "${WHITE}────────────────────────────────────────────────────────${RESET}\n"
  printf "%b\n" "                       ${CYAN}DOCKER | A.Z.L${RESET}\n"
  printf "%b\n" "${WHITE}────────────────────────────────────────────────────────${RESET}\n"
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
        echo -e "${RED}Maaf: script ini hanya mendukung Ubuntu dan Debian.${RESET}"
        exit 1
        ;;
    esac
  else
    echo -e "${RED}Tidak bisa mendeteksi OS.${RESET}"
    exit 1
  fi
  log "Detected OS=$OS version=$OS_VERSION"
}

# Simple check helper
run_and_check(){
  desc="$1"; shift
  if "$@" >> "$LOGFILE" 2>&1; then
    printf "%b" "${GREEN}[OK]${RESET} $desc\n"
    log "OK: $desc"
    return 0
  else
    printf "%b" "${RED}[ERR]${RESET} $desc (lihat $LOGFILE)\n"
    log "ERR: $desc"
    ERR_COUNT=$((ERR_COUNT+1))
    return 1
  fi
}

# Install prerequisites, add repo and install docker
install_docker(){
  # Update
  run_and_check "apt update" apt-get update -y

  # Install prerequisites
  run_and_check "install apt-transport-https ca-certificates curl gnupg lsb-release" \
    apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

  # Add Docker official GPG key
  run_and_check "add Docker GPG key" bash -c "curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg"

  # Set up repository
  echo "\nSetting up Docker repo..." | tee -a "$LOGFILE"
  repo_line="deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$OS $(lsb_release -cs) stable"
  echo "$repo_line" > /etc/apt/sources.list.d/docker.list
  run_and_check "apt update (after adding repo)" apt-get update -y

  # Install docker packages
  run_and_check "install docker packages (docker-ce docker-ce-cli containerd.io)" \
    apt-get install -y docker-ce docker-ce-cli containerd.io
}

# Configure data-root (safe default: /opt/docker-data)
configure_data_root(){
  SAFE_DEFAULT="/opt/docker-data"
  echo -e "\nDefault recommended Docker data directory: ${CYAN}$SAFE_DEFAULT${RESET}"
  read -r -p "Gunakan lokasi ini? [Y/n]: " use_safe
n=${use_safe:-Y}
  if [[ "$n" =~ ^[Nn] ]]; then
    read -r -p "Masukkan path custom untuk data-root (contoh: /mnt/docker-data): " custom_path
    DATA_ROOT="$custom_path"
  else
    DATA_ROOT="$SAFE_DEFAULT"
  fi

  # create and set permissions
  run_and_check "create data-root $DATA_ROOT" bash -c "mkdir -p '$DATA_ROOT' && chown root:root '$DATA_ROOT' && chmod 711 '$DATA_ROOT'"

  # Write daemon.json
  mkdir -p /etc/docker
  cat > /etc/docker/daemon.json <<EOF
{
  "data-root": "$DATA_ROOT",
  "log-driver": "json-file",
  "log-opts": {"max-size": "10m", "max-file": "3"}
}
EOF
  run_and_check "write /etc/docker/daemon.json" bash -c "test -f /etc/docker/daemon.json"

  run_and_check "reload systemd" systemctl daemon-reload || true
  run_and_check "enable docker service" systemctl enable docker || true
  run_and_check "start docker service" systemctl restart docker || true
}

# Create or add a user to docker group for running without sudo
create_or_add_user(){
  echo -e "\nAgar dapat menjalankan docker tanpa sudo, kita perlu menambahkan user ke group 'docker'."
  DEFAULT_USER_NAME="docker"
  read -r -p "Buat/gunakan user bernama '${DEFAULT_USER_NAME}'? [Y/n]: " use_default
  use_default=${use_default:-Y}
  if [[ "$use_default" =~ ^[Yy] ]]; then
    TARGET_USER="$DEFAULT_USER_NAME"
    if id -u "$TARGET_USER" >/dev/null 2>&1; then
      log "User $TARGET_USER sudah ada. Menambahkan ke group docker."
      run_and_check "add existing user $TARGET_USER to docker group" usermod -aG docker "$TARGET_USER"
    else
      # create a system user with no-login but can sudo? We'll create without password
      run_and_check "create system user $TARGET_USER" useradd -m -s /usr/sbin/nologin "$TARGET_USER"
      run_and_check "add $TARGET_USER to docker group" usermod -aG docker "$TARGET_USER"
    fi
  else
    read -r -p "Masukkan nama user yang ingin ditambahkan ke group docker: " TARGET_USER
    if [ -z "$TARGET_USER" ]; then
      echo -e "${YELLOW}Nama user kosong — melewatkan penambahan user.${RESET}"
      log "User add skipped (empty name)"
      return
    fi
    if id -u "$TARGET_USER" >/dev/null 2>&1; then
      run_and_check "add existing user $TARGET_USER to docker group" usermod -aG docker "$TARGET_USER"
    else
      read -r -p "User tidak ditemukan. Buat user baru bernama '$TARGET_USER'? [Y/n]: " create_user_confirm
      create_user_confirm=${create_user_confirm:-Y}
      if [[ "$create_user_confirm" =~ ^[Yy] ]]; then
        run_and_check "create user $TARGET_USER" useradd -m -s /bin/bash "$TARGET_USER"
        run_and_check "add $TARGET_USER to docker group" usermod -aG docker "$TARGET_USER"
      else
        echo -e "${YELLOW}Penambahan user dibatalkan.${RESET}"
        log "User add cancelled"
      fi
    fi
  fi

  # Inform
  if id -u "$TARGET_USER" >/dev/null 2>&1; then
    echo -e "${GREEN}User '$TARGET_USER' sekarang anggota group 'docker'.${RESET}"
    echo -e "${YELLOW}Catatan: untuk berlaku, user yang sudah login perlu logout/login kembali (atau jalankan: newgrp docker).${RESET}"
  fi
}

# Simple progress animation (percentage) while running background PID
progress_bar(){
  pid=$1
  desc="$2"
  echo -n "$desc"
  i=0
  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i + 5) % 100 ))
    printf "\r%s %3d%%" "$desc" "$i"
    sleep 0.25
  done
  printf "\r%s %3d%%\n" "$desc" 100
}

# Simulate percentage for operations that take time (for nicer UX)
simulate_progress(){
  total=$1
  desc="$2"
  for ((p=0; p<=100; p+=10)); do
    printf "\r%s %3d%%" "$desc" "$p"
    sleep $(( (RANDOM%2)+1 ))
  done
  printf "\r%s %3d%%\n" "$desc" 100
}

# Check docker status quickly
check_docker_health(){
  echo -e "\nMemeriksa status Docker..."
  if docker info >/dev/null 2>&1; then
    printf "%b\n" "${GREEN}Docker berjalan dan dapat dijalankan.${RESET}"
    log "Docker OK"
  else
    printf "%b\n" "${RED}Docker tidak merespon. Cek service dan log di $LOGFILE${RESET}"
    log "Docker not responding"
    ERR_COUNT=$((ERR_COUNT+1))
  fi
}

main(){
  print_banner
  detect_os

  echo -e "Detected: ${CYAN}$OS $OS_VERSION${RESET}\n"

  # Confirm continue
  read -r -p "Lanjutkan instalasi Docker di sistem ini? [Y/n]: " proceed
  proceed=${proceed:-Y}
  if [[ ! "$proceed" =~ ^[Yy] ]]; then
    echo "Dibatalkan oleh user."
    exit 0
  fi

  # Start installation in background and show simulated progress
  (
    install_docker
  ) &
  pid_install=$!
  progress_bar "$pid_install" "Menginstall Docker..."

  # If docker install failed, still attempt to continue gracefully
  if [ $ERR_COUNT -gt 0 ]; then
    echo -e "\n${YELLOW}Terjadi beberapa peringatan/eror selama instalasi. Lihat $LOGFILE untuk detail.${RESET}"
  fi

  # Configure data root
  configure_data_root

  # Add user to docker group / create user
  create_or_add_user

  # Final checks with simulated progress
  simulate_progress 5 "Memeriksa dan membersihkan..."
  check_docker_health

  if [ $ERR_COUNT -eq 0 ]; then
    echo -e "\n${GREEN}SUCCESSFULLY INSTALL DOCKER ON YOUR SYSTEM, YEAYYY${RESET}"
  else
    echo -e "\n${YELLOW}Instalasi selesai dengan ${ERR_COUNT} peringatan/eror. Periksa $LOGFILE untuk detail.${RESET}"
  fi

  echo -e "\n${CYAN}Author: AZ.L${RESET}"
  echo -e "${WHITE}Terima kasih telah menggunakan installer ini. Selamat mencoba!${RESET}\n"

  log "Finish. ERR_COUNT=$ERR_COUNT"
}

# Run
main "$@"
