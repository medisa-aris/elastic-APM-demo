#!/usr/bin/env bash
# Add a registry to Docker's insecure-registries list and restart the daemon.
#
# Required when pushing to a registry with a self-signed cert (e.g. CRC).
# Only needed when skopeo/podman are not available — those tools bypass this
# requirement with --dest-tls-verify=false / --tls-verify=false.
#
# Usage:
#   sudo bash ./scripts/setup-docker-insecure-registry.sh <registry-host>
#
# Example:
#   sudo bash ./scripts/setup-docker-insecure-registry.sh \
#     default-route-openshift-image-registry.apps-crc.testing

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

REGISTRY="${1:-}"
DAEMON_JSON="/etc/docker/daemon.json"

if [[ -z "$REGISTRY" ]]; then
  echo "Usage: sudo bash $0 <registry-host>" >&2
  exit 1
fi

if [[ "$EUID" -ne 0 ]]; then
  echo -e "${RED}This script must be run as root (sudo).${NC}" >&2
  exit 1
fi

echo -e "${YELLOW}Adding $REGISTRY to Docker insecure-registries...${NC}"

# Create daemon.json if it doesn't exist
if [[ ! -f "$DAEMON_JSON" ]]; then
  echo '{}' > "$DAEMON_JSON"
fi

# Idempotent: only add if not already present
if grep -q "$REGISTRY" "$DAEMON_JSON" 2>/dev/null; then
  echo -e "${GREEN}Already configured.${NC}"
else
  # Use python3 to safely merge JSON (always available on RHEL/Fedora/CentOS)
  python3 - <<EOF
import json
with open("$DAEMON_JSON") as f:
    d = json.load(f)
regs = d.setdefault("insecure-registries", [])
if "$REGISTRY" not in regs:
    regs.append("$REGISTRY")
with open("$DAEMON_JSON", "w") as f:
    json.dump(d, f, indent=2)
print("Updated $DAEMON_JSON")
EOF
fi

echo -e "${YELLOW}Restarting Docker daemon...${NC}"
if command -v systemctl &>/dev/null; then
  systemctl restart docker
elif command -v service &>/dev/null; then
  service docker restart
else
  echo -e "${RED}Could not restart Docker automatically. Please restart it manually.${NC}"
  exit 1
fi

echo -e "${GREEN}Done. Docker now trusts $REGISTRY as an insecure registry.${NC}"
echo "Re-run: ./scripts/push-images-openshift.sh"
