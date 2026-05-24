#!/usr/bin/env bash
# =============================================================
# teardown.sh — Clean cluster teardown
# WARNING: This will destroy the entire cluster. Use with care.
# Usage: ./scripts/teardown.sh --confirm
# =============================================================

set -euo pipefail

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

CONFIRMED=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --confirm) CONFIRMED=true; shift ;;
    *) echo -e "${RED}Unknown arg: $1${NC}"; exit 1 ;;
  esac
done

if [ "$CONFIRMED" = false ]; then
  echo -e "${RED}WARNING: This will completely destroy your K3s cluster!${NC}"
  echo ""
  echo "This will:"
  echo "  - Uninstall K3s from all nodes"
  echo "  - Remove all containers and pods"
  echo "  - Unmount NFS shares"
  echo "  - Remove Ceph data (if wiped)"
  echo ""
  echo "To proceed: ./scripts/teardown.sh --confirm"
  exit 1
fi

INVENTORY="ansible/inventory.ini"

echo -e "${YELLOW}Tearing down cluster...${NC}"

# Run Ansible teardown
ansible all -i "$INVENTORY" -m shell -a "
  # Uninstall K3s agent (workers)
  if [ -f /usr/local/bin/k3s-agent-uninstall.sh ]; then
    /usr/local/bin/k3s-agent-uninstall.sh
  fi

  # Uninstall K3s server (master)
  if [ -f /usr/local/bin/k3s-uninstall.sh ]; then
    /usr/local/bin/k3s-uninstall.sh
  fi

  # Unmount NFS
  umount -f /mnt/cluster-nfs 2>/dev/null || true

  # Clean up Rook/Ceph data dirs
  rm -rf /var/lib/rook
" --become 2>/dev/null || true

# Remove local kubeconfig
rm -f ./kubeconfig.yml

echo -e "${GREEN}Cluster torn down. All nodes are clean.${NC}"
