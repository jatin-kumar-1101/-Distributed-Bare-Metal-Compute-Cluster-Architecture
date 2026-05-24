#!/usr/bin/env bash
# =============================================================
# bootstrap.sh — One-shot cluster bootstrap script
# Usage: ./scripts/bootstrap.sh [--dry-run] [--tags <tag>]
# =============================================================

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ── Config ────────────────────────────────────────────────────
INVENTORY="ansible/inventory.ini"
PLAYBOOK="ansible/playbooks/site.yml"
DRY_RUN=false
TAGS=""

# ── Arg Parsing ───────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run) DRY_RUN=true; shift ;;
    --tags)    TAGS="$2"; shift 2 ;;
    *)         echo -e "${RED}Unknown argument: $1${NC}"; exit 1 ;;
  esac
done

# ── Banner ────────────────────────────────────────────────────
echo -e "${BLUE}"
cat << 'EOF'
  ██████╗ ██████╗ ███╗   ███╗██████╗ ██╗   ██╗████████╗███████╗
 ██╔════╝██╔═══██╗████╗ ████║██╔══██╗██║   ██║╚══██╔══╝██╔════╝
 ██║     ██║   ██║██╔████╔██║██████╔╝██║   ██║   ██║   █████╗
 ██║     ██║   ██║██║╚██╔╝██║██╔═══╝ ██║   ██║   ██║   ██╔══╝
 ╚██████╗╚██████╔╝██║ ╚═╝ ██║██║     ╚██████╔╝   ██║   ███████╗
  ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚═╝      ╚═════╝    ╚═╝   ╚══════╝
  Distributed Bare-Metal Cluster Bootstrap — GLA University
EOF
echo -e "${NC}"

# ── Pre-flight Checks ─────────────────────────────────────────
echo -e "${YELLOW}[1/4] Running pre-flight checks...${NC}"

command -v ansible-playbook >/dev/null 2>&1 || {
  echo -e "${RED}ERROR: ansible-playbook not found. Install with: pip install ansible${NC}"
  exit 1
}

if [ ! -f "$INVENTORY" ]; then
  echo -e "${RED}ERROR: Inventory not found at $INVENTORY${NC}"
  echo "Edit ansible/inventory.ini with your node IPs before running this script."
  exit 1
fi

if [ ! -f "$HOME/.ssh/cluster_key" ]; then
  echo -e "${YELLOW}WARNING: SSH key ~/.ssh/cluster_key not found.${NC}"
  echo "Generate one with: ssh-keygen -t ed25519 -f ~/.ssh/cluster_key"
fi

# ── Ansible Connectivity Check ────────────────────────────────
echo -e "${YELLOW}[2/4] Testing Ansible connectivity to all nodes...${NC}"
ansible all -i "$INVENTORY" -m ping || {
  echo -e "${RED}ERROR: Cannot reach all nodes. Check IPs and SSH access.${NC}"
  exit 1
}
echo -e "${GREEN}All nodes reachable!${NC}"

# ── Run Playbook ──────────────────────────────────────────────
echo -e "${YELLOW}[3/4] Starting cluster bootstrap...${NC}"

ANSIBLE_CMD="ansible-playbook -i $INVENTORY $PLAYBOOK -v"

if [ "$DRY_RUN" = true ]; then
  ANSIBLE_CMD="$ANSIBLE_CMD --check"
  echo -e "${YELLOW}DRY RUN MODE — no changes will be made${NC}"
fi

if [ -n "$TAGS" ]; then
  ANSIBLE_CMD="$ANSIBLE_CMD --tags $TAGS"
fi

echo -e "${BLUE}Running: $ANSIBLE_CMD${NC}"
eval "$ANSIBLE_CMD"

# ── Post-install Verification ─────────────────────────────────
echo -e "${YELLOW}[4/4] Verifying cluster...${NC}"
./scripts/health-check.sh

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  Cluster bootstrap complete!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo "  Kubeconfig saved to: ./kubeconfig.yml"
echo "  Export: export KUBECONFIG=\$(pwd)/kubeconfig.yml"
echo ""
echo "  Grafana:    http://$(grep 'master-1' $INVENTORY | grep -oP 'ansible_host=\K[^ ]+')" \
  ":30300  (admin / admin)"
echo "  Prometheus: http://$(grep 'master-1' $INVENTORY | grep -oP 'ansible_host=\K[^ ]+')" \
  ":9090"
echo ""
