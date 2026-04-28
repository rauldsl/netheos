#!/usr/bin/env bash
# hack/dev.sh — Netheos local development helper
# Default cluster: netheos-dev  (override with CLUSTER_NAME=<your-cluster>)
#
# Usage:
#   ./hack/dev.sh up            Build → load images → deploy → port-forward
#   ./hack/dev.sh down          Undeploy operator and delete namespace
#   ./hack/dev.sh build         Build all images with podman
#   ./hack/dev.sh load          Load images into kind cluster
#   ./hack/dev.sh deploy        Apply kustomize manifests + sample CR
#   ./hack/dev.sh port-forward  Forward WebUI to localhost:8080
#   ./hack/dev.sh logs [svc]    Tail logs (operator|aggregator|webui|agent)
#   ./hack/dev.sh status        Show pod status in netheos-system
#   ./hack/dev.sh reset         Full teardown + redeploy
#   ./hack/dev.sh compose-up    Start local dev with podman-compose (no k8s)
#   ./hack/dev.sh compose-down  Stop podman-compose stack

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-netheos-dev}"
NAMESPACE="${NAMESPACE:-netheos-system}"
REGISTRY="${REGISTRY:-ghcr.io/netheos-io}"
VERSION="${VERSION:-dev}"
CONTAINER_TOOL="${CONTAINER_TOOL:-$(command -v podman 2>/dev/null || echo docker)}"

IMG_OPERATOR="${REGISTRY}/netheos-operator:${VERSION}"
IMG_AGGREGATOR="${REGISTRY}/netheos-aggregator:${VERSION}"
IMG_AGENT="${REGISTRY}/netheos-agent:${VERSION}"
IMG_WEBUI="${REGISTRY}/netheos-webui:${VERSION}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Colour helpers ─────────────────────────────────────────────────────────

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[netheos]${NC} $*"; }
success() { echo -e "${GREEN}[netheos] ✓${NC} $*"; }
warn()    { echo -e "${YELLOW}[netheos] ⚠${NC} $*"; }
die()     { echo -e "${RED}[netheos] ✗${NC} $*" >&2; exit 1; }

# ── Preflight ──────────────────────────────────────────────────────────────

check_deps() {
  local missing=()
  for cmd in kubectl kustomize kind "${CONTAINER_TOOL}"; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  [[ ${#missing[@]} -eq 0 ]] || die "Missing tools: ${missing[*]}"
}

check_cluster() {
  info "Checking cluster: ${CLUSTER_NAME}"
  if ! kubectl cluster-info --context "kind-${CLUSTER_NAME}" &>/dev/null; then
    warn "Cluster kind-${CLUSTER_NAME} not reachable — trying default context"
    kubectl cluster-info &>/dev/null || die "No reachable cluster. Run: kind create cluster --name ${CLUSTER_NAME}"
  fi
  success "Cluster reachable"
}

# ── Build ──────────────────────────────────────────────────────────────────

cmd_build() {
  info "Building images with ${CONTAINER_TOOL}..."
  cd "${ROOT_DIR}"

  "${CONTAINER_TOOL}" build -f Dockerfile.operator   -t "${IMG_OPERATOR}"   . && success "operator image built"
  "${CONTAINER_TOOL}" build -f Dockerfile.aggregator -t "${IMG_AGGREGATOR}" . && success "aggregator image built"
  "${CONTAINER_TOOL}" build -f Dockerfile.agent      -t "${IMG_AGENT}"      . && success "agent image built"
  "${CONTAINER_TOOL}" build -f Dockerfile.webui      -t "${IMG_WEBUI}"      . && success "webui image built"
}

# ── Kind load ─────────────────────────────────────────────────────────────

cmd_load() {
  info "Loading images into kind cluster: ${CLUSTER_NAME}"
  cd "${ROOT_DIR}"

  for img in "${IMG_OPERATOR}" "${IMG_AGGREGATOR}" "${IMG_AGENT}" "${IMG_WEBUI}"; do
    info "  Loading ${img} ..."
    local archive="/tmp/netheos-$(basename "${img%%:*}").tar"

    if "${CONTAINER_TOOL}" save "${img}" -o "${archive}" 2>/dev/null; then
      kind load image-archive "${archive}" --name "${CLUSTER_NAME}" \
        && success "  Loaded ${img}" \
        || die "  Failed to load ${img}"
      rm -f "${archive}"
    else
      # Fallback: pipe directly (works when podman and kind share cgroup)
      "${CONTAINER_TOOL}" save "${img}" | kind load docker-image --name "${CLUSTER_NAME}" "${img}" \
        && success "  Loaded ${img}" \
        || die "  Failed to load ${img}"
    fi
  done
}

# ── Deploy ─────────────────────────────────────────────────────────────────

cmd_deploy() {
  info "Deploying CRDs and operator..."
  cd "${ROOT_DIR}"

  kustomize build config/default | kubectl apply -f -
  kubectl wait --for=condition=Available deployment/netheos-operator \
    -n "${NAMESPACE}" --timeout=120s \
    && success "Operator deployment ready" \
    || warn "Operator not yet ready — check: kubectl -n ${NAMESPACE} get pods"

  info "Applying NetheosConfig CR..."
  kubectl apply -f config/samples/netheos_v1alpha1_netheosconfig.yaml
  success "NetheosConfig applied"
}

# ── Port-forward ───────────────────────────────────────────────────────────

cmd_port_forward() {
  info "Waiting for netheos-webui to be ready..."
  kubectl wait --for=condition=Available deployment/netheos-webui \
    -n "${NAMESPACE}" --timeout=180s 2>/dev/null \
    || warn "WebUI not yet ready, forwarding anyway..."

  success "Forwarding netheos-webui → http://localhost:8080 (Ctrl-C to stop)"
  kubectl port-forward -n "${NAMESPACE}" svc/netheos-webui 8080:8080
}

# ── Logs ──────────────────────────────────────────────────────────────────

cmd_logs() {
  local svc="${1:-operator}"
  local selector
  case "${svc}" in
    operator)   selector="app=netheos-operator" ;;
    aggregator) selector="app=netheos-aggregator" ;;
    webui)      selector="app=netheos-webui" ;;
    agent)      selector="app=netheos-agent" ;;
    ollama)     selector="app=netheos-ollama" ;;
    *)          die "Unknown service '${svc}'. Use: operator|aggregator|webui|agent|ollama" ;;
  esac
  info "Tailing logs for ${svc} (${selector})..."
  kubectl logs -n "${NAMESPACE}" -l "${selector}" -f --tail=100
}

# ── Status ────────────────────────────────────────────────────────────────

cmd_status() {
  echo ""
  info "Pods in namespace ${NAMESPACE}:"
  kubectl get pods -n "${NAMESPACE}" -o wide 2>/dev/null || warn "Namespace ${NAMESPACE} not found"
  echo ""
  info "NetheosConfig:"
  kubectl get netheosconfig 2>/dev/null || warn "NetheosConfig CRD not installed"
  echo ""
  info "Services:"
  kubectl get svc -n "${NAMESPACE}" 2>/dev/null || true
}

# ── Down ──────────────────────────────────────────────────────────────────

cmd_down() {
  warn "Removing Netheos from cluster..."
  cd "${ROOT_DIR}"
  kubectl delete -f config/samples/netheos_v1alpha1_netheosconfig.yaml --ignore-not-found
  kustomize build config/default | kubectl delete --ignore-not-found -f -
  success "Netheos removed"
}

# ── Reset ─────────────────────────────────────────────────────────────────

cmd_reset() {
  warn "Full reset: undeploy → rebuild → redeploy"
  cmd_down || true
  cmd_build
  cmd_load
  cmd_deploy
  success "Reset complete — run './hack/dev.sh port-forward' to open the UI"
}

# ── Up (full workflow) ─────────────────────────────────────────────────────

cmd_up() {
  info "Starting full local dev workflow..."
  check_deps
  check_cluster
  cmd_build
  cmd_load
  cmd_deploy
  echo ""
  success "Netheos is deployed!"
  echo -e "  ${CYAN}Open UI:${NC}     make port-forward  (or ./hack/dev.sh port-forward)"
  echo -e "  ${CYAN}Check pods:${NC}  ./hack/dev.sh status"
  echo -e "  ${CYAN}Tail logs:${NC}   ./hack/dev.sh logs [operator|aggregator|webui|agent]"
  echo ""
}

# ── Compose helpers ───────────────────────────────────────────────────────

cmd_compose_up() {
  info "Starting local dev stack via podman-compose (no k8s)..."
  cd "${ROOT_DIR}"
  podman-compose up --build -d
  success "Stack running — WebUI at http://localhost:8080"
}

cmd_compose_down() {
  info "Stopping podman-compose stack..."
  cd "${ROOT_DIR}"
  podman-compose down
  success "Stack stopped"
}

# ── Dispatch ──────────────────────────────────────────────────────────────

CMD="${1:-help}"
shift || true

case "${CMD}" in
  up)           cmd_up ;;
  down)         cmd_down ;;
  build)        cmd_build ;;
  load)         cmd_load ;;
  deploy)       cmd_deploy ;;
  port-forward) cmd_port_forward ;;
  logs)         cmd_logs "${1:-operator}" ;;
  status)       cmd_status ;;
  reset)        cmd_reset ;;
  compose-up)   cmd_compose_up ;;
  compose-down) cmd_compose_down ;;
  help|*)
    echo ""
    echo "Usage: ./hack/dev.sh <command>"
    echo ""
    echo "Commands:"
    echo "  up            Full workflow: build → load → deploy → done"
    echo "  down          Remove Netheos from the cluster"
    echo "  build         Build all images with ${CONTAINER_TOOL}"
    echo "  load          Load images into kind cluster (${CLUSTER_NAME})"
    echo "  deploy        Apply kustomize manifests and NetheosConfig CR"
    echo "  port-forward  Forward WebUI → http://localhost:8080"
    echo "  logs [svc]    Tail pod logs (operator|aggregator|webui|agent)"
    echo "  status        Show pods, services, NetheosConfig"
    echo "  reset         Full teardown + rebuild + redeploy"
    echo "  compose-up    Start local stack with podman-compose (no k8s)"
    echo "  compose-down  Stop podman-compose stack"
    echo ""
    echo "Environment variables:"
    echo "  CLUSTER_NAME   kind cluster name (default: netheos-dev)"
    echo "  NAMESPACE      deployment namespace (default: netheos-system)"
    echo "  REGISTRY       image registry prefix"
    echo "  VERSION        image tag (default: dev)"
    echo "  CONTAINER_TOOL container runtime (default: podman)"
    echo ""
    ;;
esac
