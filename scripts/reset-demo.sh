#!/usr/bin/env bash
# Reset the Elastic APM demo to a clean state.
#
# Stops all services, wipes database volumes, resets scenario flags to 0
# in .env, then rebuilds and restarts everything with fresh seed data.
#
# Usage:
#   ./scripts/reset-demo.sh [options]
#
# Options:
#   -m, --mode   compose | kubernetes | openshift  (default: compose)
#   -h, --help   Show this help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MODE="compose"

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

step() { echo -e "\n${CYAN}==> $*${NC}"; }

usage() {
  grep '^#' "$0" | grep -v '#!/' | sed 's/^# \?//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--mode) MODE="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ ! "$MODE" =~ ^(compose|kubernetes|openshift)$ ]]; then
  echo "Invalid mode: $MODE. Must be compose, kubernetes, or openshift." >&2
  exit 1
fi

cd "$PROJECT_ROOT"

# ── Stop ──────────────────────────────────────────────────────────────────────
step "Stopping demo"
bash "$SCRIPT_DIR/stop-demo.sh" --mode "$MODE" --clean-volumes

# ── Reset scenario flags in .env ──────────────────────────────────────────────
step "Resetting scenario flags in .env"

ENV_FILE="$PROJECT_ROOT/.env"
if [[ -f "$ENV_FILE" ]]; then
  # Use sed for in-place replacement; handle both macOS (BSD sed) and Linux (GNU sed)
  if sed --version 2>/dev/null | grep -q GNU; then
    sed -i 's/^PAYMENT_FAILURE_RATE=.*/PAYMENT_FAILURE_RATE=0/' "$ENV_FILE"
    sed -i 's/^INVENTORY_SLOW_MS=.*/INVENTORY_SLOW_MS=0/'      "$ENV_FILE"
  else
    # macOS BSD sed requires an extension argument (use empty string for in-place)
    sed -i '' 's/^PAYMENT_FAILURE_RATE=.*/PAYMENT_FAILURE_RATE=0/' "$ENV_FILE"
    sed -i '' 's/^INVENTORY_SLOW_MS=.*/INVENTORY_SLOW_MS=0/'      "$ENV_FILE"
  fi
  echo -e "    ${GREEN}PAYMENT_FAILURE_RATE=0${NC}"
  echo -e "    ${GREEN}INVENTORY_SLOW_MS=0${NC}"
else
  echo -e "    ${YELLOW}.env not found — skipping flag reset${NC}"
fi

# ── Restart ───────────────────────────────────────────────────────────────────
step "Starting demo with fresh build"
bash "$SCRIPT_DIR/start-demo.sh" --mode "$MODE" --build
