#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# bootstrap_env.sh
# Contract:
#   - Primary target: Ubuntu 24.04 LTS (noble)
#   - Best-effort:    Ubuntu 22.04 LTS (jammy)
# Assumes:
#   - sudo works
#   - internet works
#   - GPU drivers/CUDA already working if --gpu (WSL is fine)
# Does:
#   - installs system deps, python venv, repo deps
#   - optional: installs Docker, installs Ollama, pulls model
#   - runs pytest, runs Ollama sanity prompt
# ------------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

WITH_OLLAMA=1
WITH_DOCKER=1
USE_GPU=1
MODEL="qwen2.5-coder:7b-instruct"
NONINTERACTIVE=0
DRY_RUN=0

log() { echo -e "[$(date +'%H:%M:%S')] $*"; }
die() { echo -e "\nERROR: $*\n" >&2; exit 1; }

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY-RUN: $*"
    return 0
  fi
  log "RUN: $*"
  eval "$@"
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

usage() {
  cat <<EOF
Usage: ./bootstrap_env.sh [options]

Options:
  --with-ollama | --no-ollama     Install/use Ollama (default: with)
  --with-docker | --no-docker     Install/use Docker (default: with)
  --gpu | --cpu                   Expect GPU-ready env or force CPU mode (default: gpu)
  --model <name>                  Ollama model to pull (default: $MODEL)
  --noninteractive                Don't prompt (default: off)
  --dry-run                       Print actions without executing (default: off)
  -h, --help                      Show help

Examples:
  ./bootstrap_env.sh
  ./bootstrap_env.sh --cpu --no-docker
  ./bootstrap_env.sh --model qwen2.5-coder:7b-instruct
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-ollama) WITH_OLLAMA=1; shift ;;
    --no-ollama)   WITH_OLLAMA=0; shift ;;
    --with-docker) WITH_DOCKER=1; shift ;;
    --no-docker)   WITH_DOCKER=0; shift ;;
    --gpu)         USE_GPU=1; shift ;;
    --cpu)         USE_GPU=0; shift ;;
    --model)       MODEL="${2:-}"; [[ -n "$MODEL" ]] || die "--model requires a value"; shift 2 ;;
    --noninteractive) NONINTERACTIVE=1; shift ;;
    --dry-run)     DRY_RUN=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    *)             die "Unknown option: $1" ;;
  esac
done

confirm() {
  local msg="$1"
  if [[ "$NONINTERACTIVE" -eq 1 ]]; then
    return 0
  fi
  read -r -p "$msg [y/N] " ans
  [[ "${ans:-}" =~ ^[Yy]$ ]]
}

# ---------------------------
# Phase 0: sanity checks
# ---------------------------
need_cmd bash
need_cmd sudo
need_cmd curl
need_cmd git

if [[ ! -f /etc/os-release ]]; then
  die "Cannot detect OS version (/etc/os-release missing)."
fi

. /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
  die "This bootstrap supports Ubuntu only. Detected: ${ID:-unknown}"
fi

UBU_VER="${VERSION_ID:-}"
UBU_CODENAME="${VERSION_CODENAME:-}"
log "Detected OS: Ubuntu ${UBU_VER} (${UBU_CODENAME})"

if [[ "$UBU_VER" != "24.04" && "$UBU_VER" != "22.04" ]]; then
  log "WARNING: Unsupported Ubuntu version ($UBU_VER). Proceeding best-effort."
fi

# Internet check (simple, avoids fancy DNS debugging)
if ! curl -fsSL --max-time 8 https://www.google.com >/dev/null 2>&1; then
  die "No outbound internet (or blocked). Bootstrap requires internet access."
fi

# GPU check only if requested
if [[ "$USE_GPU" -eq 1 ]]; then
  if command -v nvidia-smi >/dev/null 2>&1; then
    log "GPU check: nvidia-smi present."
    nvidia-smi >/dev/null 2>&1 || die "nvidia-smi failed. GPU stack may not be working."
  else
    log "WARNING: nvidia-smi not found. If this is WSL, that might still be OK. Otherwise GPU is likely not configured."
  fi
else
  log "CPU mode selected."
fi

# Disk space sanity (models + docker layers add up)
AVAIL_GB=$(df -BG "$REPO_ROOT" | awk 'NR==2 {gsub("G","",$4); print $4}')
if [[ "${AVAIL_GB:-0}" -lt 15 ]]; then
  log "WARNING: Less than ~15GB free on repo filesystem. You may run out of space (models + docker images)."
fi

# ---------------------------
# Phase 1: install deps
# ---------------------------
log "Updating apt and installing baseline packages..."
run "sudo apt-get update -y"
run "sudo apt-get install -y ca-certificates curl git build-essential python3 python3-venv python3-pip"

# Docker install (optional)
install_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "Docker already installed."
    return 0
  fi

  log "Installing Docker Engine..."
  if ! confirm "This will install Docker Engine system-wide. Continue?"; then
    die "User declined Docker install."
  fi

  run "sudo apt-get install -y ca-certificates curl gnupg"
  run "sudo install -m 0755 -d /etc/apt/keyrings"
  run "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg"
  run "sudo chmod a+r /etc/apt/keyrings/docker.gpg"

  # Determine codename for docker repo line
  local codename="$UBU_CODENAME"
  if [[ -z "$codename" ]]; then
    codename="noble"
  fi

  run "echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $codename stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null"
  run "sudo apt-get update -y"
  run "sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"

  # Enable + add user to group
  run "sudo systemctl enable --now docker || true"
  run "sudo usermod -aG docker \$USER || true"

  log "Docker installed. You may need to log out/in for docker group membership to take effect."
}

verify_docker() {
  need_cmd docker
  log "Verifying Docker..."
  run "docker version >/dev/null"
}

# Ollama install (optional)
install_ollama() {
  if command -v ollama >/dev/null 2>&1; then
    log "Ollama already installed."
    return 0
  fi

  log "Installing Ollama..."
  if ! confirm "This will install Ollama system-wide. Continue?"; then
    die "User declined Ollama install."
  fi

  run "curl -fsSL https://ollama.com/install.sh | sh"
}

verify_ollama() {
  need_cmd ollama
  log "Verifying Ollama service..."
  # Try start if systemd is present; if not, user must start manually
  if command -v systemctl >/dev/null 2>&1; then
    run "sudo systemctl enable --now ollama || true"
  else
    log "systemctl not found; ensure ollama is running (WSL may differ)."
  fi

  # Pull model
  log "Pulling model: $MODEL"
  run "ollama pull \"$MODEL\""

  # Sanity prompt (fast, low token)
  log "Running Ollama sanity prompt..."
  run "ollama run \"$MODEL\" \"Return only the word OK.\" | head -n 1"
}

# Python venv + deps
setup_python() {
  log "Setting up Python venv..."
  cd "$REPO_ROOT"

  if [[ ! -d ".venv" ]]; then
    run "python3 -m venv .venv"
  fi

  # shellcheck disable=SC1091
  source ".venv/bin/activate"

  run "python -m pip install --upgrade pip wheel setuptools"

  if [[ -f "requirements.txt" ]]; then
    run "pip install -r requirements.txt"
  elif [[ -f "pyproject.toml" ]]; then
    # Simple path: rely on pip installing project editable
    run "pip install -e ."
  else
    # Minimal test deps for early days
    run "pip install pytest"
  fi

  log "Python deps installed."
}

verify_pytest() {
  cd "$REPO_ROOT"
  # shellcheck disable=SC1091
  source ".venv/bin/activate"

  if [[ -d "tests" ]]; then
    log "Running pytest..."
    run "python -m pytest -q"
  else
    log "No tests/ directory yet; skipping pytest."
  fi
}

# Execute selected installs
if [[ "$WITH_DOCKER" -eq 1 ]]; then
  install_docker
  verify_docker
else
  log "Skipping Docker install/verify (--no-docker)."
fi

if [[ "$WITH_OLLAMA" -eq 1 ]]; then
  install_ollama
  verify_ollama
else
  log "Skipping Ollama install/verify (--no-ollama)."
fi

setup_python
verify_pytest

log ""
log "Bootstrap complete."
log "Summary:"
log "  - OS: Ubuntu ${UBU_VER} (${UBU_CODENAME})"
log "  - Python venv: .venv"
log "  - Docker: $([[ $WITH_DOCKER -eq 1 ]] && echo enabled || echo skipped)"
log "  - Ollama: $([[ $WITH_OLLAMA -eq 1 ]] && echo enabled || echo skipped)"
log "  - Model: $MODEL"
log ""
log "NOTE: If Docker was installed, you may need to log out/in for 'docker' group membership."
