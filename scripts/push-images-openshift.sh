#!/usr/bin/env bash
# Push locally built Docker images to the OpenShift internal registry.
#
# Supports CRC (OpenShift Local) where the registry uses a self-signed cert.
# Runtime selection order (first available wins):
#   1. buildah — native RHEL/CRC tool, --tls-verify=false, no daemon restart
#   2. skopeo  — reads from Docker daemon, --dest-tls-verify=false
#   3. podman  — --tls-verify=false
#   4. docker  — requires insecure-registry config for CRC self-signed certs
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

# Runtime selection: buildah > skopeo > podman > docker
# buildah and skopeo support --tls-verify=false without daemon config changes.
if command -v buildah &>/dev/null; then
  RUNTIME="buildah"
elif command -v skopeo &>/dev/null; then
  RUNTIME="skopeo"
elif command -v podman &>/dev/null; then
  RUNTIME="podman"
elif command -v docker &>/dev/null; then
  RUNTIME="docker"
else
  fail "No container runtime found (need buildah, skopeo, podman, or docker)."
  exit 1
fi
ok "Container runtime: $RUNTIME"

# Verify local images exist in Docker daemon
if ! command -v docker &>/dev/null; then
  fail "docker is required to read local images even when pushing with buildah/skopeo/podman."
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

# ── Ensure namespace exists ───────────────────────────────────────────────────
step "Ensuring namespace '$NAMESPACE' exists"

if oc get namespace "$NAMESPACE" &>/dev/null; then
  ok "Namespace already exists"
else
  oc new-project "$NAMESPACE" --display-name="Elastic APM Demo" || \
    oc create namespace "$NAMESPACE"
  ok "Namespace created"
fi

# ── Pre-create ImageStreams ───────────────────────────────────────────────────
# The registry returns 500 if it can't create/resolve the ImageStream on-the-fly
# during a push. Pre-creating them ensures the push has somewhere to land.
step "Pre-creating ImageStreams in '$NAMESPACE'"
for name in "${IMAGES[@]}"; do
  oc create imagestream "$name" -n "$NAMESPACE" 2>/dev/null && \
    echo "    Created: $name" || \
    echo "    Exists:  $name"
done

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

# Detect CRC (self-signed cert)
IS_CRC=false
[[ "$REGISTRY" =~ \.apps-crc\.testing$ ]] && IS_CRC=true

# ── RBAC ──────────────────────────────────────────────────────────────────────
step "Granting registry push permissions in '$NAMESPACE'"
oc policy add-role-to-user registry-editor "$OC_USER" -n "$NAMESPACE" 2>/dev/null && \
  ok "registry-editor role granted to $OC_USER" || \
  warn "Could not grant registry-editor (may already be set)"

# Refresh token after role grant
OC_TOKEN=$(oc whoami -t)

# ── Verify registry pod is healthy ────────────────────────────────────────────
step "Checking registry pod health"
REG_PODS=$(oc get pods -n openshift-image-registry \
  -l docker-registry=default --field-selector=status.phase=Running \
  -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
if [[ -z "$REG_PODS" ]]; then
  warn "No running registry pod found — checking all pods:"
  oc get pods -n openshift-image-registry 2>/dev/null || true
  fail "Registry pod is not running. Check: oc logs -n openshift-image-registry deployment/image-registry"
  exit 1
fi
ok "Registry pod(s) running: $REG_PODS"

# ── Login ─────────────────────────────────────────────────────────────────────
if [[ "$RUNTIME" != "skopeo" && "$RUNTIME" != "buildah" ]]; then
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

PUSH_FAILED=false
for name in "${IMAGES[@]}"; do
  DEST="${REGISTRY}/${NAMESPACE}/${name}:latest"
  printf "    %-42s" "${name}:local → latest"

  case "$RUNTIME" in
    buildah)
      # buildah reads from Docker daemon via containers-storage or docker-daemon transport
      buildah push --tls-verify=false \
        --creds="${OC_USER}:${OC_TOKEN}" \
        "docker-daemon:${name}:local" \
        "docker://${DEST}" 2>&1 | tail -1
      ;;
    skopeo)
      skopeo copy \
        --dest-creds="${OC_USER}:${OC_TOKEN}" \
        --dest-tls-verify=false \
        "docker-daemon:${name}:local" \
        "docker://${DEST}" 2>&1 | tail -1
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

  if [[ $? -eq 0 ]]; then
    echo -e " ${GREEN}done${NC}"
  else
    echo -e " ${RED}FAILED${NC}"
    PUSH_FAILED=true
  fi
done

if $PUSH_FAILED; then
  echo ""
  warn "One or more pushes failed. Showing last 20 lines of registry logs:"
  oc logs -n openshift-image-registry deployment/image-registry --tail=20 2>/dev/null || \
    oc logs -n openshift-image-registry -l docker-registry=default --tail=20 2>/dev/null || true
  echo ""
  fail "Push failed. Fix the errors above and retry."
  exit 1
fi

echo ""
ok "All images pushed. OpenShift pods can now pull them."
echo ""
echo "  Internal registry URL (used by pods):"
echo "  image-registry.openshift-image-registry.svc:5000/$NAMESPACE/<name>:latest"
echo ""
