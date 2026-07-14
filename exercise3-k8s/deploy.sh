#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Build and deploy the hello-world REST service on minikube
#
# Usage:
#   ./deploy.sh           # full deploy (install tools if missing, start minikube,
#                         #              build image, apply manifests, port-forward)
#   ./deploy.sh --clean   # tear down the deployment and stop port-forward
#   ./deploy.sh --status  # print current pod/service status
#
# Requirements (auto-installed on macOS / Debian-based Linux if absent):
#   docker, minikube, kubectl
# =============================================================================
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
APP_IMAGE="hello-world-app:1.0"
NAMESPACE="hello-world"
LOCAL_PORT=8080
REMOTE_PORT=8080
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PF_PID_FILE="/tmp/hello-world-port-forward.pid"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }
step()    { echo -e "\n${BOLD}==> $*${RESET}"; }

# ── OS detection ──────────────────────────────────────────────────────────────
detect_os() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux)  echo "linux" ;;
    *)      error "Unsupported OS: $(uname -s). Supported: macOS, Linux." ;;
  esac
}

OS=$(detect_os)
ARCH=$(uname -m)

# ── Tool installation helpers ─────────────────────────────────────────────────
install_brew() {
  if ! command -v brew &>/dev/null; then
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
}

install_docker() {
  warn "Docker is not installed."
  if [[ "$OS" == "macos" ]]; then
    info "Please install Docker Desktop from https://www.docker.com/products/docker-desktop/ and re-run this script."
    exit 1
  else
    info "Installing Docker via apt..."
    sudo apt-get update -qq
    sudo apt-get install -y docker.io
    sudo systemctl enable --now docker
    sudo usermod -aG docker "$USER"
    warn "Docker installed. You may need to log out and back in for group changes to take effect."
    warn "Re-run this script after logging back in."
    exit 0
  fi
}

install_minikube() {
  info "minikube not found — installing..."
  if [[ "$OS" == "macos" ]]; then
    install_brew
    brew install minikube
  else
    local mk_arch
    case "$ARCH" in
      x86_64)  mk_arch="amd64" ;;
      aarch64) mk_arch="arm64" ;;
      arm64)   mk_arch="arm64" ;;
      *)       error "Unsupported architecture: $ARCH" ;;
    esac
    local url="https://storage.googleapis.com/minikube/releases/latest/minikube-linux-${mk_arch}"
    info "Downloading minikube from ${url}..."
    curl -fsSL "$url" -o /tmp/minikube
    sudo install /tmp/minikube /usr/local/bin/minikube
    rm /tmp/minikube
  fi
  success "minikube installed: $(minikube version --short)"
}

install_kubectl() {
  info "kubectl not found — installing..."
  if [[ "$OS" == "macos" ]]; then
    install_brew
    brew install kubectl
  else
    local kb_arch
    case "$ARCH" in
      x86_64)  kb_arch="amd64" ;;
      aarch64) kb_arch="arm64" ;;
      arm64)   kb_arch="arm64" ;;
      *)       error "Unsupported architecture: $ARCH" ;;
    esac
    local version
    version=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
    curl -fsSLO "https://dl.k8s.io/release/${version}/bin/linux/${kb_arch}/kubectl"
    sudo install kubectl /usr/local/bin/kubectl
    rm kubectl
  fi
  success "kubectl installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
}

# ── Prerequisite checks ───────────────────────────────────────────────────────
check_prerequisites() {
  step "Checking prerequisites"

  if ! command -v docker &>/dev/null; then
    install_docker
  else
    success "docker $(docker --version | awk '{print $3}' | tr -d ',')"
  fi

  if ! command -v minikube &>/dev/null; then
    install_minikube
  else
    success "minikube $(minikube version --short)"
  fi

  if ! command -v kubectl &>/dev/null; then
    install_kubectl
  else
    success "kubectl $(kubectl version --client --short 2>/dev/null | awk '{print $3}' || echo 'ok')"
  fi

  # Verify Docker daemon is actually running
  if ! docker info &>/dev/null; then
    error "Docker daemon is not running. Start Docker Desktop (macOS) or run: sudo systemctl start docker"
  fi
}

# ── minikube lifecycle ────────────────────────────────────────────────────────
start_minikube() {
  step "Starting minikube"

  local mk_status
  mk_status=$(minikube status --format='{{.Host}}' 2>/dev/null || echo "Nonexistent")

  if [[ "$mk_status" == "Running" ]]; then
    success "minikube is already running"
  else
    info "Starting minikube cluster..."
    minikube start --driver=docker
    success "minikube started"
  fi
}

# ── Image build (uses minikube's built-in Docker daemon = local registry) ─────
build_image() {
  step "Building Docker image in minikube's local registry"

  info "Pointing Docker CLI at minikube's internal daemon (no remote registry needed)..."
  # shellcheck disable=SC2046
  eval $(minikube docker-env)

  info "Building ${APP_IMAGE}..."
  docker build -t "${APP_IMAGE}" "${SCRIPT_DIR}"

  success "Image ${APP_IMAGE} built and stored in minikube's local registry"
}

# ── Kubernetes deploy ─────────────────────────────────────────────────────────
deploy_k8s() {
  step "Deploying to Kubernetes"

  kubectl apply -f "${SCRIPT_DIR}/k8s/namespace.yaml"
  kubectl apply -f "${SCRIPT_DIR}/k8s/deployment.yaml"
  kubectl apply -f "${SCRIPT_DIR}/k8s/service.yaml"

  info "Waiting for rollout to complete..."
  kubectl rollout status deployment/hello-world -n "${NAMESPACE}" --timeout=120s

  success "Deployment is live"
}

# ── Port-forward ──────────────────────────────────────────────────────────────
start_port_forward() {
  step "Starting port-forward localhost:${LOCAL_PORT} → service/${NAMESPACE}:${REMOTE_PORT}"

  # Kill any existing port-forward for this app
  stop_port_forward 2>/dev/null || true

  kubectl port-forward \
    service/hello-world \
    "${LOCAL_PORT}:${REMOTE_PORT}" \
    -n "${NAMESPACE}" \
    &>/tmp/hello-world-pf.log &

  echo $! > "${PF_PID_FILE}"
  sleep 2  # Give the tunnel a moment to establish

  # Quick smoke-test
  local response
  response=$(curl -sf "http://localhost:${LOCAL_PORT}/hello-world" 2>/dev/null || echo "")
  if [[ -n "$response" ]]; then
    success "Service is reachable!"
    echo ""
    echo -e "  ${BOLD}Endpoint:${RESET}  http://localhost:${LOCAL_PORT}/hello-world"
    echo -e "  ${BOLD}Response:${RESET}  ${response}"
    echo ""
    echo -e "  ${YELLOW}Port-forward is running in the background (PID $(cat ${PF_PID_FILE})).${RESET}"
    echo -e "  To stop it:  ${BOLD}./deploy.sh --clean${RESET}"
  else
    warn "Port-forward started (PID $(cat ${PF_PID_FILE})) but the smoke-test did not return a response yet."
    warn "Try:  curl http://localhost:${LOCAL_PORT}/hello-world"
  fi
}

stop_port_forward() {
  if [[ -f "${PF_PID_FILE}" ]]; then
    local pid
    pid=$(cat "${PF_PID_FILE}")
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid"
      info "Port-forward (PID ${pid}) stopped"
    fi
    rm -f "${PF_PID_FILE}"
  fi
}

# ── Clean-up ──────────────────────────────────────────────────────────────────
clean() {
  step "Cleaning up"
  stop_port_forward

  if kubectl get namespace "${NAMESPACE}" &>/dev/null 2>&1; then
    kubectl delete namespace "${NAMESPACE}" --ignore-not-found
    success "Namespace ${NAMESPACE} deleted"
  else
    info "Namespace ${NAMESPACE} not found — nothing to delete"
  fi
}

# ── Status ────────────────────────────────────────────────────────────────────
status() {
  step "Current status"
  kubectl get pods,svc -n "${NAMESPACE}" 2>/dev/null || warn "Namespace ${NAMESPACE} does not exist yet. Run ./deploy.sh to deploy."
}

# ── Entry point ───────────────────────────────────────────────────────────────
case "${1:-}" in
  --clean)
    clean
    ;;
  --status)
    status
    ;;
  "")
    check_prerequisites
    start_minikube
    build_image
    deploy_k8s
    start_port_forward
    ;;
  *)
    echo "Usage: $0 [--clean | --status]"
    exit 1
    ;;
esac
