#!/usr/bin/env bash
# install - Docker installer (interactive, idempotent)
# Author: A.Z.L
# Language: English
# Usage: sudo ./install [--yes] [--dry-run] [--install-compose plugin|binary|none] [--add-user <user>] [--skip-verify] [--reinstall] [--rollback-on-failure] [--log-file <path>]

set -euo pipefail
IFS=$'\n\t'

# ---------------------------
# Banner (whale ASCII)
# ---------------------------
WHale_BANNER='''
              ##         .
           ## ## ##        ==
        ## ## ## ## ##    ===
    /""""""""""""""""""""\___/ ===
   {                       /  ===-
    \______A.Z.L__________/          
      /  /  /  /  /  /          
    -----------------------------
          Docker Installer
'''

# ---------------------------
# Defaults
# ---------------------------
DRY_RUN=0
ASSUME_YES=0
INSTALL_COMPOSE="none"
ADD_USER=""
SKIP_VERIFY=0
REINSTALL=0
ROLLBACK_ON_FAILURE=0
LOG_FILE=""

# auto timestamp
TS=$(date +"%Y%m%d_%H%M%S")
DEFAULT_LOG="/var/log/docker_install_${TS}.log"

# Temp state for rollback
ADDED_REPO=0
ADDED_KEY=0
INSTALLED_PKGS=()

# ---------------------------
# Helpers
# ---------------------------
log(){
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*" | tee -a "$LOG_FILE"
}

run(){
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "DRY-RUN: $*"
  else
    log "+ $*"
    eval "$@"
  fi
}

prompt_yes_no(){
  local prompt="$1"
  if [ "$ASSUME_YES" -eq 1 ]; then
    return 0
  fi
  local resp
  read -r -p "$prompt [Y/n]: " resp
  resp=${resp:-Y}
  case "${resp^^}" in
    Y|YES) return 0;;
    N|NO) return 1;;
    *) return 1;;
  esac
}

detect_distro(){
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO_ID=${ID,,}
    DISTRO_NAME=$NAME
    DISTRO_VER=$VERSION_ID
  else
    DISTRO_ID="unknown"
    DISTRO_NAME="unknown"
    DISTRO_VER=""
  fi
}

is_root(){
  [ "$(id -u)" -eq 0 ]
}

ensure_root(){
  if ! is_root; then
    echo "This installer must be run as root. Re-run with sudo or as root." >&2
    exit 2
  fi
}

# ---------------------------
# Rollback logic
# ---------------------------
do_rollback(){
  log "Rollback initiated"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry-run: no rollback actions executed"
    return
  fi
  # Attempt to remove installed packages
  if [ "${#INSTALLED_PKGS[@]}" -gt 0 ]; then
    log "Removing packages: ${INSTALLED_PKGS[*]}"
    if [[ "$PKG_MANAGER" == "apt" ]]; then
      apt-get remove -y "${INSTALLED_PKGS[@]}" || true
    elif [[ "$PKG_MANAGER" == "dnf" || "$PKG_MANAGER" == "yum" ]]; then
      ${PKG_MANAGER} remove -y "${INSTALLED_PKGS[@]}" || true
    fi
  fi
  # Remove repo file if added
  if [ "$ADDED_REPO" -eq 1 ]; then
    log "Removing Docker repo file"
    rm -f /etc/apt/sources.list.d/docker.list || true
    rm -f /etc/apt/sources.list.d/docker*.repo || true
  fi
  # Remove keyring if added
  if [ "$ADDED_KEY" -eq 1 ]; then
    log "Removing docker keyring (best-effort)"
    rm -f /usr/share/keyrings/docker-archive-keyring.gpg || true
  fi
  log "Rollback complete"
}

on_error(){
  local rc=$?
  log "Error: installer failed with exit code $rc"
  if [ "$ROLLBACK_ON_FAILURE" -eq 1 ]; then
    do_rollback
  fi
  log "Log file: $LOG_FILE"
  exit $rc
}

trap on_error ERR

# ---------------------------
# Arg parsing
# ---------------------------
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift;;
    --yes|-y) ASSUME_YES=1; shift;;
    --install-compose) INSTALL_COMPOSE="$2"; shift 2;;
    --add-user) ADD_USER="$2"; shift 2;;
    --skip-verify) SKIP_VERIFY=1; shift;;
    --reinstall) REINSTALL=1; shift;;
    --rollback-on-failure) ROLLBACK_ON_FAILURE=1; shift;;
    --log-file) LOG_FILE="$2"; shift 2;;
    --help|-h) echo "Usage: sudo ./install [--yes] [--dry-run] [--install-compose plugin|binary|none] [--add-user user] [--skip-verify] [--reinstall] [--rollback-on-failure] [--log-file path]"; exit 0;;
    *) echo "Unknown arg: $1"; exit 2;;
  esac
done

# set log file default
if [ -z "$LOG_FILE" ]; then
  LOG_FILE="$DEFAULT_LOG"
fi

# ensure writable log file (if not dry-run)
if [ "$DRY_RUN" -eq 0 ]; then
  mkdir -p "$(dirname "$LOG_FILE")" || true
  touch "$LOG_FILE" || true
  chmod 644 "$LOG_FILE" || true
fi

# ---------------------------
# Start
# ---------------------------
clear
echo "$WHale_BANNER"
echo "Installer: A.Z.L — Docker automated installer"

detect_distro
log "Detected distro: $DISTRO_NAME ($DISTRO_ID) $DISTRO_VER"

ensure_root

if ! prompt_yes_no "Proceed with Docker installation on $DISTRO_NAME ($DISTRO_VER)?"; then
  log "User aborted"
  exit 0
fi

# ---------------------------
# Basic checks
# ---------------------------
if command -v docker >/dev/null 2>&1; then
  EXISTING_DOCKER_VERSION=$(docker --version 2>/dev/null || true)
  log "Existing Docker detected: ${EXISTING_DOCKER_VERSION:-unknown}"
  if [ "$REINSTALL" -eq 0 ]; then
    if prompt_yes_no "Docker is already installed. Do you want to (re)install/upgrade anyway?"; then
      REINSTALL=1
    else
      log "Skipping installation because Docker exists and reinstall not requested"
      exit 0
    fi
  fi
fi

# ---------------------------
# Distro-specific implementation (focus: Debian/Ubuntu, fallback warn)
# ---------------------------
PKG_MANAGER=""
if [[ "$DISTRO_ID" == "ubuntu" || "$DISTRO_ID" == "debian" ]]; then
  PKG_MANAGER=apt
  log "Using apt-based installation"
  # update
  run "apt-get update -y"
  # prerequisites
  run "apt-get install -y ca-certificates curl gnupg lsb-release"
  # add docker GPG key
  if [ ! -f /usr/share/keyrings/docker-archive-keyring.gpg ]; then
    run "curl -fsSL https://download.docker.com/linux/$DISTRO_ID/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg"
    ADDED_KEY=1
  else
    log "Docker keyring already present"
  fi
  # add repo
  if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
    run "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$DISTRO_ID $(lsb_release -cs) stable\" > /etc/apt/sources.list.d/docker.list"
    ADDED_REPO=1
  else
    log "Docker repo already present"
  fi
  run "apt-get update -y"
  # install docker packages
  DOCKER_PKGS=(docker-ce docker-ce-cli containerd.io)
  run "apt-get install -y ${DOCKER_PKGS[*]}"
  INSTALLED_PKGS+=("${DOCKER_PKGS[@]}")
  # enable & start
  run "systemctl enable docker"
  run "systemctl start docker"
  
elif [[ "$DISTRO_ID" == "fedora" || "$DISTRO_ID" == "centos" || "$DISTRO_ID" == "rhel" || "$DISTRO_ID" == "rocky" || "$DISTRO_ID" == "almalinux" ]]; then
  PKG_MANAGER=dnf
  log "Detected RPM-based distro. Attempting dnf/yum flow (best-effort)."
  if command -v dnf >/dev/null 2>&1; then
    PKG_MANAGER=dnf
  else
    PKG_MANAGER=yum
  fi
  run "$PKG_MANAGER -y install dnf-plugins-core"
  run "$PKG_MANAGER config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo"
  run "$PKG_MANAGER install -y docker-ce docker-ce-cli containerd.io"
  INSTALLED_PKGS+=(docker-ce docker-ce-cli containerd.io)
  run "systemctl enable --now docker"
else
  log "Unsupported or unrecognized distro: $DISTRO_ID. The installer currently supports Debian/Ubuntu and RPM-based distros. For others, please follow Docker official docs: https://docs.docker.com/engine/install/"
  if ! prompt_yes_no "Continue anyway with best-effort install?"; then
    exit 3
  fi
fi

# ---------------------------
# Post install: user group
# ---------------------------
if [ -n "$ADD_USER" ]; then
  if id "$ADD_USER" >/dev/null 2>&1; then
    run "usermod -aG docker $ADD_USER"
    log "Added $ADD_USER to docker group"
  else
    log "User $ADD_USER does not exist — skipping add-user"
  fi
else
  # prompt to add current user (non-root)
  if [ "$SUDO_USER" != "" ] && prompt_yes_no "Add $SUDO_USER to docker group to allow non-root docker usage?"; then
    run "usermod -aG docker $SUDO_USER"
    log "Added $SUDO_USER to docker group"
  fi
fi

# ---------------------------
# Optional: Docker Compose
# ---------------------------
if [[ "$INSTALL_COMPOSE" == "plugin" ]]; then
  log "Installing Docker Compose plugin (v2 as plugin)"
  if [[ "$PKG_MANAGER" == "apt" ]]; then
    run "apt-get install -y docker-compose-plugin"
    INSTALLED_PKGS+=(docker-compose-plugin)
  else
    # best-effort: use package if available
    run "$PKG_MANAGER install -y docker-compose-plugin || true"
  fi
elif [[ "$INSTALL_COMPOSE" == "binary" ]]; then
  log "Installing Docker Compose (binary)"
  COMPOSE_DL_URL="https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)"
  run "curl -L "$COMPOSE_DL_URL" -o /usr/local/bin/docker-compose"
  run "chmod +x /usr/local/bin/docker-compose"
fi

# ---------------------------
# Verification
# ---------------------------
if [ "$SKIP_VERIFY" -eq 0 ]; then
  if prompt_yes_no "Run test container (hello-world) to verify Docker?"; then
    run "docker run --rm hello-world || true"
  fi
else
  log "Skipping verification as requested"
fi

log "Docker installation flow completed"
log "Installed packages (best-effort list): ${INSTALLED_PKGS[*]:-none}"
log "Log file: $LOG_FILE"

if [ "$DRY_RUN" -eq 0 ]; then
  echo
  echo "========================================"
  echo "Docker install finished — A.Z.L" | tee -a "$LOG_FILE"
  echo "If you added a user to the docker group, ask them to logout & login again." | tee -a "$LOG_FILE"
  echo "========================================="
fi

exit 0
