#!/usr/bin/env bash
# Start the Elastic APM demo.
#
# Usage:
#   ./scripts/start-demo.sh [options]
#
# Options:
#   -m, --mode      compose | kubernetes | openshift  (default: compose)
#   -b, --build     Force rebuild of Docker images
#   --scenario2     Activate Scenario 2: Payment Failure (PAYMENT_FAILURE_RATE=100)
#   --scenario3     Activate Scenario 3: Slow Inventory  (INVENTORY_SLOW_MS=3000)
#   -h, --help      Show this help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Defaults ──────────────────────────────────────────────────────────────────
MODE="compose"
BUILD=false
SCENARIO2=false
SCENARIO3=false

# ── Colour helpers ────────────────────────────────────────────────────────────
CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

step()  { echo -e "\n${CYAN}==> $*${NC}"; }
ok()    { echo -e "    ${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "    ${YELLOW}[WARN]${NC} $*"; }
fail()  { echo -e "    ${RED}[FAIL]${NC} $*"; }

# ── Argument parsing ──────────────────────────────────────────────────────────
usage() {
  grep '^#' "$0" | grep -v '#!/' | sed 's/^# \?//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--mode)       MODE="$2"; shift 2 ;;
    -b|--build)      BUILD=true; shift ;;
    --scenario2)     SCENARIO2=true; shift ;;
    --scenario3)     SCENARIO3=true; shift ;;
    -h|--help)       usage ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ ! "$MODE" =~ ^(compose|kubernetes|openshift)$ ]]; then
  echo "Invalid mode: $MODE. Must be compose, kubernetes, or openshift." >&2
  exit 1
fi

cd "$PROJECT_ROOT"

# ── Load .env ─────────────────────────────────────────────────────────────────
load_dotenv() {
  local envfile="$1"
  [[ -f "$envfile" ]] || return
  while IFS= read -r line; do
    # Skip comments and blank lines; only set if not already exported
    if [[ "$line" =~ ^[[:space:]]*([^#][^=]+)=(.*)$ ]]; then
      local key="${BASH_REMATCH[1]// /}"
      local val="${BASH_REMATCH[2]}"
      val="${val%\"}"
      val="${val#\"}"
      val="${val%\'}"
      val="${val#\'}"
      [[ -z "${!key+x}" ]] && export "$key=$val"
    fi
  done < "$envfile"
}

# ── Health check helper ────────────────────────────────────────────────────────
wait_for_healthy() {
  local name="$1"
  local url="$2"
  local max_seconds="${3:-180}"
  local deadline=$(( $(date +%s) + max_seconds ))

  printf "    Waiting for %s at %s" "$name" "$url"
  while [[ $(date +%s) -lt $deadline ]]; do
    if curl -sf --max-time 3 "$url" > /dev/null 2>&1; then
      echo -e " ${GREEN}Ready${NC}"
      return 0
    fi
    printf '.'
    sleep 3
  done
  echo -e " ${RED}TIMED OUT${NC}"
  return 1
}

# ── Validation ────────────────────────────────────────────────────────────────
step "Validating environment"

ENV_FILE="$PROJECT_ROOT/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  fail ".env file not found."
  echo "    Copy the example and fill in your Elastic Cloud credentials:"
  echo "      cp .env.example .env"
  exit 1
fi

load_dotenv "$ENV_FILE"

if [[ -z "${ELASTIC_APM_SERVER_URL:-}" || "$ELASTIC_APM_SERVER_URL" == *"your-apm"* ]]; then
  fail "ELASTIC_APM_SERVER_URL is not set or still contains the placeholder value."
  echo "    Edit .env and set your real Elastic Cloud APM Server URL."
  exit 1
fi
ok "APM Server: $ELASTIC_APM_SERVER_URL"

# ── Scenario overrides ────────────────────────────────────────────────────────
if $SCENARIO2; then
  warn "Scenario 2 active: PAYMENT_FAILURE_RATE=100"
  export PAYMENT_FAILURE_RATE=100
fi
if $SCENARIO3; then
  warn "Scenario 3 active: INVENTORY_SLOW_MS=3000"
  export INVENTORY_SLOW_MS=3000
fi

# ── Start ─────────────────────────────────────────────────────────────────────
build_images() {
  local images=(
    "demo-frontend:local|./frontend"
    "demo-gateway:local|./gateway"
    "demo-order-service:local|./services/order-service"
    "demo-payment-service:local|./services/payment-service"
    "demo-inventory-service:local|./services/inventory-service"
  )
  for entry in "${images[@]}"; do
    local tag="${entry%%|*}"
    local ctx="${entry##*|}"
    printf "    Building %s..." "$tag"
    docker build -t "$tag" "$ctx" -q
    echo -e " ${GREEN}done${NC}"
  done
}

case "$MODE" in

  compose)
    step "Starting services with Docker Compose"

    # Run go mod tidy for inventory-service if go.sum is missing/empty
    GO_SUM="$PROJECT_ROOT/services/inventory-service/go.sum"
    if $BUILD && { [[ ! -s "$GO_SUM" ]] || grep -q '^\s*#' "$GO_SUM" 2>/dev/null; }; then
      printf "    Running go mod tidy for inventory-service..."
      if command -v go &>/dev/null; then
        (cd "$PROJECT_ROOT/services/inventory-service" && go mod tidy)
        echo -e " ${GREEN}done${NC}"
      else
        warn "go not found in PATH — go.sum will be generated inside the Docker build"
      fi
    fi

    COMPOSE_ARGS=("compose" "up" "-d")
    $BUILD && COMPOSE_ARGS+=("--build")
    docker "${COMPOSE_ARGS[@]}"

    step "Waiting for services to be healthy"
    HEALTHY=true
    wait_for_healthy "otel-collector"    "http://localhost:13133/"              || HEALTHY=false
    wait_for_healthy "inventory-service" "http://localhost:8082/health"         || HEALTHY=false
    wait_for_healthy "payment-service"   "http://localhost:8081/health"         || HEALTHY=false
    wait_for_healthy "order-service"     "http://localhost:8080/actuator/health" || HEALTHY=false
    wait_for_healthy "gateway"           "http://localhost:4000/health"         || HEALTHY=false
    wait_for_healthy "frontend"          "http://localhost:3000"                || HEALTHY=false

    if ! $HEALTHY; then
      fail "One or more services failed to become healthy."
      echo "    Check logs: docker compose logs --tail=50"
      exit 1
    fi
    ;;

  kubernetes)
    step "Building Docker images for Kubernetes (imagePullPolicy: Never)"
    build_images

    if command -v minikube &>/dev/null; then
      step "Loading images into minikube"
      for tag in demo-frontend:local demo-gateway:local demo-order-service:local demo-payment-service:local demo-inventory-service:local; do
        minikube image load "$tag"
      done
    fi

    step "Applying Kubernetes manifests"
    kubectl apply -f deployment/kubernetes/

    step "Waiting for rollouts"
    kubectl rollout status deployment -n elastic-apm-demo --timeout=180s
    ;;

  openshift)
    step "Building Docker images"
    build_images

    step "Pushing images to OpenShift internal registry"
    bash "$SCRIPT_DIR/push-images-openshift.sh" --namespace elastic-apm-demo

    step "Creating demo-secrets from .env"
    oc create secret generic demo-secrets \
      --from-literal=ELASTIC_APM_SERVER_URL="${ELASTIC_APM_SERVER_URL}" \
      --from-literal=ELASTIC_API_KEY="${ELASTIC_API_KEY}" \
      --from-literal=NEXT_PUBLIC_ELASTIC_APM_SERVER_URL="${NEXT_PUBLIC_ELASTIC_APM_SERVER_URL:-$ELASTIC_APM_SERVER_URL}" \
      -n elastic-apm-demo \
      --dry-run=client -o yaml | oc apply -f -

    step "Applying OpenShift manifests"
    oc apply -f deployment/openshift/

    step "Waiting for rollouts"
    oc rollout status deployment -n elastic-apm-demo --timeout=180s
    ;;
esac

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  Demo is running!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""

if [[ "$MODE" == "openshift" ]]; then
  FRONTEND_URL=$(oc get route frontend -n elastic-apm-demo -o jsonpath='{.spec.host}' 2>/dev/null || echo "check: oc get route -n elastic-apm-demo")
  GATEWAY_URL=$(oc get route gateway   -n elastic-apm-demo -o jsonpath='{.spec.host}' 2>/dev/null || echo "check: oc get route -n elastic-apm-demo")
  echo "  Frontend:    https://$FRONTEND_URL"
  echo "  Gateway API: https://$GATEWAY_URL"
else
  echo "  Frontend:          http://localhost:3000"
  echo "  Gateway API:       http://localhost:4000"
  echo "  OTel Collector:    http://localhost:13133  (health check)"
fi
echo ""
echo "  APM Server:        $ELASTIC_APM_SERVER_URL"
echo ""
$SCENARIO2 && echo -e "  ${YELLOW}[Scenario 2] Payment failures are ON  (PAYMENT_FAILURE_RATE=100)${NC}"
$SCENARIO3 && echo -e "  ${YELLOW}[Scenario 3] Slow inventory is ON  (INVENTORY_SLOW_MS=3000)${NC}"
echo ""
echo "  To stop:   ./scripts/stop-demo.sh"
echo "  To reset:  ./scripts/reset-demo.sh"
echo ""
