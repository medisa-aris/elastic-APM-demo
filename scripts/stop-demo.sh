#!/usr/bin/env bash
# Stop the Elastic APM demo.
#
# Usage:
#   ./scripts/stop-demo.sh [options]
#
# Options:
#   -m, --mode          compose | kubernetes | openshift  (default: compose)
#   -v, --clean-volumes Remove named volumes (wipes database data)
#   -i, --clean-images  Remove locally built Docker images
#   -h, --help          Show this help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MODE="compose"
CLEAN_VOLUMES=false
CLEAN_IMAGES=false

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

step() { echo -e "\n${CYAN}==> $*${NC}"; }

usage() {
  grep '^#' "$0" | grep -v '#!/' | sed 's/^# \?//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--mode)          MODE="$2"; shift 2 ;;
    -v|--clean-volumes) CLEAN_VOLUMES=true; shift ;;
    -i|--clean-images)  CLEAN_IMAGES=true; shift ;;
    -h|--help)          usage ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ ! "$MODE" =~ ^(compose|kubernetes|openshift)$ ]]; then
  echo "Invalid mode: $MODE. Must be compose, kubernetes, or openshift." >&2
  exit 1
fi

cd "$PROJECT_ROOT"

case "$MODE" in

  compose)
    step "Stopping Docker Compose services"

    DOWN_ARGS=("compose" "down")
    if $CLEAN_VOLUMES; then
      DOWN_ARGS+=("-v")
      echo -e "    ${YELLOW}-v flag set: named volumes will be removed (database data wiped)${NC}"
    fi
    if $CLEAN_IMAGES; then
      DOWN_ARGS+=("--rmi" "local")
      echo -e "    ${YELLOW}--rmi local flag set: locally built images will be removed${NC}"
    fi

    docker "${DOWN_ARGS[@]}"
    ;;

  kubernetes)
    step "Deleting Kubernetes resources"
    kubectl delete -f deployment/kubernetes/ --ignore-not-found
    ;;

  openshift)
    step "Deleting OpenShift resources"
    oc delete -f deployment/openshift/ --ignore-not-found
    ;;
esac

echo ""
echo -e "  ${GREEN}Demo stopped.${NC}"
echo ""
