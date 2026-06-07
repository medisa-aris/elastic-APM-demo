#!/usr/bin/env bash
# Push locally built Docker images to the OpenShift internal registry.
#
# Run this after building images with:
#   docker build -t demo-<name>:local ./<service>
#
# Or use start-demo.sh --mode openshift --build which calls this automatically.
#
# Usage:
#   ./scripts/push-images-openshift.sh [--namespace <ns>]
#
# Options:
#   -n, --namespace   OpenShift namespace (default: elastic-apm-demo)
#   -h, --help        Show this help
#
# Requirements:
#   - oc CLI logged in (oc whoami must work)
#   - docker or podman installed locally
#   - Local images already built (demo-*:local tags)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="elastic-apm-demo"

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
step()  { echo -e "\n${CYAN}==> $*${NC}"; }
ok()    { echo -e "    ${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "    ${YELLOW}[WARN]${NC} $*"; }
fail()  { echo -e "    ${RED}[FAIL]${NC} $*"; }

usage() { grep '^#' "$0" | grep -v '#!/' | sed 's/^# \?//'; exit 0; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--namespace) NAMESPACE="$2"; shift 2 ;;
    -h|--help)      usage ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

IMAGES=(
  demo-frontend
  demo-gateway
  demo-order-service
  demo-payment-service
  demo-inventory-service
)

# ── Preflight ─────────────────────────────────────────────────────────────────
step "Pre-flight checks"

if ! command -v oc &>/dev/null; then
  fail "oc CLI not found. Install OpenShift CLI and log in first."
  exit 1
fi

OC_USER=$(oc whoami 2>/dev/null) || { fail "Not logged in. Run: oc login <cluster-url>"; exit 1; }
ok "Logged in as: $OC_USER"

# Prefer podman (ships with CRC/OpenShift Local), fall back to docker
if command -v podman &>/dev/null; then
  RUNTIME="podman"
elif command -v docker &>/dev/null; then
  RUNTIME="docker"
else
  fail "Neither podman nor docker found. Install one of them."
  exit 1
fi
ok "Container runtime: $RUNTIME"

# Verify local images exist
for name in "${IMAGES[@]}"; do
  if ! $RUNTIME image inspect "${name}:local" &>/dev/null; then
    fail "Image ${name}:local not found. Build it first:"
    echo "    docker build -t ${name}:local ./<service-dir>"
    exit 1
  fi
done
ok "All local images present"

# ── Expose internal registry route ────────────────────────────────────────────
step "Getting OpenShift internal registry route"

REGISTRY=$(oc get route default-route -n openshift-image-registry \
  -o jsonpath='{.spec.host}' 2>/dev/null || true)

if [[ -z "$REGISTRY" ]]; then
  warn "Registry route not exposed — enabling it now..."
  oc patch configs.imageregistry.operator.openshift.io/cluster \
    --patch '{"spec":{"defaultRoute":true}}' --type=merge
  echo -n "    Waiting for route"
  for i in $(seq 1 20); do
    sleep 3
    REGISTRY=$(oc get route default-route -n openshift-image-registry \
      -o jsonpath='{.spec.host}' 2>/dev/null || true)
    [[ -n "$REGISTRY" ]] && break
    printf '.'
  done
  echo ""
fi

if [[ -z "$REGISTRY" ]]; then
  fail "Could not get the registry route after waiting."
  echo "    Check: oc get route -n openshift-image-registry"
  exit 1
fi
ok "Registry: $REGISTRY"

# ── Login ─────────────────────────────────────────────────────────────────────
step "Logging in to registry"

OC_TOKEN=$(oc whoami -t)

if [[ "$RUNTIME" == "podman" ]]; then
  # podman supports --tls-verify=false which avoids self-signed cert issues on CRC
  podman login --tls-verify=false -u "$OC_USER" -p "$OC_TOKEN" "$REGISTRY"
else
  # docker requires the registry to be in insecure-registries for self-signed certs
  docker login -u "$OC_USER" -p "$OC_TOKEN" "$REGISTRY" || {
    warn "docker login failed — registry may use a self-signed cert."
    warn "Add to /etc/docker/daemon.json:  { \"insecure-registries\": [\"$REGISTRY\"] }"
    warn "Then restart Docker and retry."
    exit 1
  }
fi
ok "Login successful"

# ── Push ──────────────────────────────────────────────────────────────────────
step "Pushing images to $REGISTRY/$NAMESPACE"

for name in "${IMAGES[@]}"; do
  DEST="${REGISTRY}/${NAMESPACE}/${name}:latest"
  printf "    %-40s" "$name:local → latest"

  if [[ "$RUNTIME" == "podman" ]]; then
    podman tag "${name}:local" "$DEST"
    podman push --tls-verify=false "$DEST" -q
  else
    docker tag "${name}:local" "$DEST"
    docker push "$DEST" -q
  fi

  echo -e " ${GREEN}done${NC}"
done

echo ""
ok "All images pushed. OpenShift pods can now pull them."
echo ""
echo "  Internal registry URL (used by pods):"
echo "  image-registry.openshift-image-registry.svc:5000/$NAMESPACE/<name>:latest"
echo ""
