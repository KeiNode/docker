#!/usr/bin/env bash
# install.sh — Docker installer untuk Debian / Ubuntu (NotRedHat)
# Author: A.Z.L
set -o errexit
set -o nounset
set -o pipefail

# -------------------------
# Helper functions
# -------------------------
yellow() { printf '\033[1;33m%s\033[0m\n' "$*"; }
green()  { printf '\033[1;32m%s\033[0m\n' "$*"; }
red()    { printf '\033[1;31m%s\033[0m\n' "$*"; }
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }

status_box() {
  case "${2:-}" in
    ok)   printf "[\033[1;32m✔\033[0m] %s\n" "$1" ;;
    fail) printf "[\033[1;31m✖\033[0m] %s\n" "$1" ;;
    info) printf "[\033[1;34m i\033[0m] %s\n" "$1" ;;
    *)    printf "[ ] %s\n" "$1" ;;
  esac
}

err_exit() {
  red "ERROR: $1"
  exit 1
}

confirm_prompt_default_yes() {
  local resp
  read -rp "$1 [Y/n]: " resp
  resp=${resp:-Y}
  case "$resp" in
    [Yy]* ) return 0 ;;
    [Nn]* ) return 1 ;;
    * ) return 0 ;;
  esac
}

# -------------------------
# Banner
# -------------------------
cat <<'BANNER'

             ##         .
           ## ##       ==
        ## ## ##      ===
     /""""""""""""\___/ ===
    {                   /  ===-
     \  O   O   O   O  /    ===-
      \               /      ===-
       '-------------'
        \  A . Z . L /      ⚓
         `---------'

BANNER

bold "A.Z.L"
echo
status_box "Starting Docker installer for Debian/Ubuntu (NotRedHat)" info
echo

# Ensure run as root (re-run with sudo if needed)
if [ "$(id -u)" -ne 0 ]; then
  status_box "Installer requires root privileges. Re-running with sudo..." info
  exec sudo bash "$0" "$@"
fi

# Detect OS: only allow Debian/Ubuntu
if [ -r /etc/os-release ]; then
  . /etc/os-release
  OS_ID="${ID,,}"
  OS_ID_LIKE="${ID_LIKE:-}"
else
  err_exit "Cannot detect OS. /etc/os-release not found."
fi

if [[ "$OS_ID" != "debian" && "$OS_ID" != "ubuntu" && "$OS_ID_LIKE" != *"debian"* ]]; then
  err_exit "This installer supports Debian/Ubuntu only. Detected: $OS_ID"
fi
status_box "OS check passed: ${PRETTY_NAME:-$OS_ID}" ok

# Docker data dir (use recommended default automatically)
DOCKER_DATA_DIR="/var/lib/docker"
status_box "Docker data directory (auto): $DOCKER_DATA_DIR" info

# Ask about docker username (default or custom)
echo
if confirm_prompt_default_yes "Use default docker username 'docker'?"; then
  DOCKER_USER="docker"
  status_box "Using default username: $DOCKER_USER" ok
else
  while true; do
    read -rp "Enter desired username to be in 'docker' group (no spaces): " CUSTOM_USER
    CUSTOM_USER=${CUSTOM_USER:-}
    if [[ -z "$CUSTOM_USER" ]]; then
      red "Username cannot be empty."
      continue
    fi
    if [[ "$CUSTOM_USER" =~ [[:space:]] ]]; then
      red "Username cannot contain spaces."
      continue
    fi
    DOCKER_USER="$CUSTOM_USER"
    break
  done
  status_box "Selected username: $DOCKER_USER" info
fi

# Summary & confirm
echo
bold "Summary of choices:"
echo "  - OS: ${PRETTY_NAME:-$OS_ID}"
echo "  - Docker data dir: $DOCKER_DATA_DIR (automatic)"
echo "  - Docker user to add to 'docker' group: $DOCKER_USER"
echo
if ! confirm_prompt_default_yes "Proceed with installation?"; then
  red "Installation aborted by user."
  exit 1
fi

# -------------------------
# Install prerequisites (tolerant)
# -------------------------
status_box "Step 1: apt update & install prerequisites (tolerant mode)" info
export DEBIAN_FRONTEND=noninteractive
apt-get update -y || err_exit "apt-get update failed"

# Define core required packages and optional extras
CORE_PKGS=(ca-certificates curl gnupg lsb-release apt-transport-https)
OPTIONAL_PKGS=(software-properties-common)

# Install core packages — fail if these are missing
apt-get install -y --no-install-recommends "${CORE_PKGS[@]}" || err_exit "Failed installing core prerequisites: ${CORE_PKGS[*]}"

# Try to install optional packages but do NOT fail the whole run if unavailable
for pkg in "${OPTIONAL_PKGS[@]}"; do
  if apt-cache show "$pkg" >/dev/null 2>&1; then
    apt-get install -y --no-install-recommends "$pkg" || yellow "Warning: installing optional package $pkg failed — continuing"
  else
    yellow "Optional package $pkg not found in repo — skipping"
  fi
done
status_box "Prerequisites installed (core) — optional pkgs handled" ok

# -------------------------
# Add Docker's official GPG key & repo
# -------------------------
status_box "Step 2: Add Docker's official GPG key & apt repo" info
mkdir -p /etc/apt/keyrings
if curl -fsSL "https://download.docker.com/linux/${OS_ID}/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg; then
  chmod a+r /etc/apt/keyrings/docker.gpg
else
  err_exit "Failed to download or store Docker GPG key"
fi

ARCH=$(dpkg --print-architecture)
CODENAME=$(lsb_release -cs 2>/dev/null || echo "stable")
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${OS_ID} ${CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list || err_exit "Failed to add Docker apt repo"
step_ok() { status_box "$1" ok; }

step_ok "Docker apt repo added"

# -------------------------
# Install docker packages
# -------------------------
status_box "Step 3: apt update & install docker packages" info
apt-get update -y || err_exit "apt-get update (repo) failed"

# Try installing the modern recommended set, fallback gracefully
if apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin; then
  step_ok "Docker packages installed (docker-ce, docker-ce-cli, containerd.io, docker-compose-plugin)"
else
  yellow "Primary docker package set failed; attempting fallback install..."
  if apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose; then
    step_ok "Docker packages installed (fallback: docker-compose)"
  else
    err_exit "Failed installing Docker packages (both primary & fallback attempts failed)"
  fi
fi

# -------------------------
# Create docker group and add users
# -------------------------
status_box "Step 4: Configure docker group & add user(s)" info
groupadd -f docker || err_exit "Failed ensuring docker group"

if id -u "$DOCKER_USER" >/dev/null 2>&1; then
  usermod -aG docker "$DOCKER_USER" || err_exit "Failed to add $DOCKER_USER to docker group"
  step_ok "User '$DOCKER_USER' added to docker group"
else
  if confirm_prompt_default_yes "User '$DOCKER_USER' does not exist. Create it now?"; then
    adduser --disabled-password --gecos "" "$DOCKER_USER" || err_exit "Failed to create user $DOCKER_USER"
    usermod -aG docker "$DOCKER_USER" || err_exit "Failed to add $DOCKER_USER to docker group after creation"
    step_ok "User '$DOCKER_USER' created and added to docker group"
  else
    yellow "User '$DOCKER_USER' not present and not created. You must add an existing user to 'docker' group later."
  fi
fi

# Also add the original sudo caller (SUDO_USER) if present and not root
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
  if id -u "$SUDO_USER" >/dev/null 2>&1; then
    usermod -aG docker "$SUDO_USER" || yellow "Warning: failed to add SUDO_USER '$SUDO_USER' to docker group"
    step_ok "SUDO_USER '$SUDO_USER' added to docker group (if exists)"
  fi
fi

# Ensure docker data dir exists and permissions are sane
if [ ! -d "$DOCKER_DATA_DIR" ]; then
  mkdir -p "$DOCKER_DATA_DIR" || err_exit "Failed to create $DOCKER_DATA_DIR"
  chown root:root "$DOCKER_DATA_DIR"
  chmod 711 "$DOCKER_DATA_DIR"
  step_ok "Created docker data directory: $DOCKER_DATA_DIR"
else
  status_box "Docker data directory already exists: $DOCKER_DATA_DIR" info
fi

mkdir -p /etc/docker

# We use default daemon config (no changes) when using default data dir

# -------------------------
# Enable & start Docker
# -------------------------
status_box "Step 5: Enable & start docker service" info
systemctl daemon-reload || true
systemctl enable --now docker || err_exit "Failed to enable/start Docker service"
step_ok "Docker service enabled & started"

# -------------------------
# Verify docker
# -------------------------
status_box "Step 6: Verify docker" info
if docker version >/dev/null 2>&1; then
  docker version --format 'Docker Engine: {{.Server.Version}}' || true
  step_ok "Docker engine is responsive"
else
  yellow "Warning: 'docker version' failed to run. You may need to relogin or check logs (sudo journalctl -u docker)."
fi

# -------------------------
# Report group membership
# -------------------------
echo
status_box "Step 7: Verify group membership for users" info
check_and_report_user() {
  local u=$1
  if id -u "$u" >/dev/null 2>&1; then
    if id -nG "$u" | grep -qw docker; then
      green "User '$u' is member of 'docker' group"
    else
      yellow "User '$u' is NOT member of 'docker' group (you may need to logout/login)"
    fi
  else
    yellow "User '$u' does not exist on the system"
  fi
}
check_and_report_user "$DOCKER_USER"
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
  check_and_report_user "$SUDO_USER"
fi

echo
green "============================================"
green "Instalasi selesai — ringkasan & langkah berikutnya"
echo "  - Docker data dir: $DOCKER_DATA_DIR"
echo "  - Docker service: enabled & started"
echo "  - User yang ditambahkan ke group 'docker': $DOCKER_USER"
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
  echo "  - Pengguna yang menjalankan script (SUDO_USER): ${SUDO_USER} (juga ditambahkan ke group 'docker')"
fi
green "============================================"
echo
bold "Agar dapat menjalankan 'docker' tanpa sudo (langsung):"
echo "  - **Logout & login kembali** untuk user yang ditambahkan, atau"
echo "  - Jalankan perintah ini di shell user yang bersangkutan untuk sementara (aktifkan group sekarang):"
echo "      newgrp docker"
echo
bold "Selamat — Docker berhasil diinstall. Yeayy!! 🎉"
green "Note: Jika masih memerlukan sudo untuk menjalankan 'docker', pastikan user yang Anda gunakan sudah logout/login setelah penambahan ke grup 'docker'."

exit 0
