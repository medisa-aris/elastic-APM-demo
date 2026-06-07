#!/usr/bin/env bash
# Push locally built Docker images to the OpenShift internal registry.
#
# Supports CRC (OpenShift Local) where the registry uses a self-signed cert.
# Runtime selection order (first available wins):
#   1. skopeo  — reads from Docker daemon, --dest-tls-verify=false (best for CRC)
#   2. podman  — --tls-verify=false
#   3. docker  — only works when the registry has a trusted cert
#                (for CRC: run setup-docker-insecure-registry.sh first)
#
# Usage:
#   ./scripts/push-images-openshift.sh [--namespace <ns>]
#
# Options:
#   -n, --namespace   OpenShift namespace (default: elastic-apm-demo)
#   -h, --help        Show this help

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
  fail "oc CLI not found. Install the OpenShift CLI and log in first."
  exit 1
fi

OC_USER=$(oc whoami 2>/dev/null) || { fail "Not logged in. Run: oc login <cluster-url>"; exit 1; }
ok "Logged in as: $OC_USER"

# Runtime selection: skopeo > podman > docker
# skopeo is the best choice for CRC because it reads directly from the Docker
# daemon and supports --dest-tls-verify=false without any daemon configuration.
if command -v skopeo &>/dev/null; then
  RUNTIME="skopeo"
elif command -v podman &>/dev/null; then
  RUNTIME="podman"
elif command -v docker &>/dev/null; then
  RUNTIME="docker"
else
  fail "No container runtime found (need skopeo, podman, or docker)."
  exit 1
fi
ok "Container runtime: $RUNTIME"

# Verify local images exist in Docker daemon
if ! command -v docker &>/dev/null; then
  fail "docker is required to read local images (even when pushing with skopeo/podman)."
  exit 1
fi
for name in "${IMAGES[@]}"; do
  if ! docker image inspect "${name}:local" &>/dev/null; then
    fail "Image ${name}:local not found. Build it first:"
    echo "    docker build -t ${name}:local ./<service-dir>"
    exit 1
  fi
done
ok "All local images found in Docker"

# ── Registry route ────────────────────────────────────────────────────────────
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

OC_TOKEN=$(oc whoami -t)

# Detect CRC (self-signed cert) and warn if using docker
IS_CRC=false
[[ "$REGISTRY" =~ \.apps-crc\.testing$ ]] && IS_CRC=true

if [[ "$RUNTIME" == "docker" ]] && $IS_CRC; then
  warn "CRC detected but only docker is available."
  warn "docker push will fail with x509 TLS errors unless the registry is"
  warn "added to insecure-registries. Run this to fix it:"
  warn ""
  warn "  sudo bash $SCRIPT_DIR/setup-docker-insecure-registry.sh $REGISTRY"
  warn ""
  warn "Then re-run this script. Or install skopeo for a zero-config alternative:"
  warn "  sudo dnf install -y skopeo   # RHEL/Fedora/CentOS"
  warn "  sudo apt install -y skopeo   # Debian/Ubuntu"
  warn ""
  warn "Attempting push anyway — it may succeed if you already configured Docker."
fi

# ── Login (not needed for skopeo — it uses --dest-creds inline) ──────────────
if [[ "$RUNTIME" != "skopeo" ]]; then
  step "Logging in to registry"
  if [[ "$RUNTIME" == "podman" ]]; then
    podman login --tls-verify=false -u "$OC_USER" -p "$OC_TOKEN" "$REGISTRY"
  else
    docker login -u "$OC_USER" -p "$OC_TOKEN" "$REGISTRY"
  fi
  ok "Login successful"
fi

# ── Push ──────────────────────────────────────────────────────────────────────
step "Pushing images to $REGISTRY/$NAMESPACE"

for name in "${IMAGES[@]}"; do
  DEST="${REGISTRY}/${NAMESPACE}/${name}:latest"
  printf "    %-42s" "${name}:local → latest"

  case "$RUNTIME" in
    skopeo)
      skopeo copy \
        --dest-creds="${OC_USER}:${OC_TOKEN}" \
        --dest-tls-verify=false \
        "docker-daemon:${name}:local" \
        "docker://${DEST}"
      ;;
    podman)
      podman tag "${name}:local" "$DEST"
      podman push --tls-verify=false "$DEST" -q
      ;;
    docker)
      docker tag "${name}:local" "$DEST"
      docker push "$DEST" -q
      ;;
  esac

  echo -e " ${GREEN}done${NC}"
done

echo ""
ok "All images pushed. OpenShift pods can now pull them."
echo ""
echo "  Internal registry URL (used by pods):"
echo "  image-registry.openshift-image-registry.svc:5000/$NAMESPACE/<name>:latest"
echo ""
