#!/usr/bin/env bash
# =============================================================
# fault-test.sh — Fault Tolerance Simulation Script
# Simulates node failures and validates automatic pod rescheduling
# Usage: ./scripts/fault-test.sh --node <node> --action <shutdown|isolate|restore>
# =============================================================

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

KUBECONFIG="${KUBECONFIG:-./kubeconfig.yml}"
NODE=""
ACTION=""
TIMEOUT=120  # seconds to wait for rescheduling

while [[ $# -gt 0 ]]; do
  case $1 in
    --node)    NODE="$2"; shift 2 ;;
    --action)  ACTION="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *) echo -e "${RED}Unknown arg: $1${NC}"; exit 1 ;;
  esac
done

[ -z "$NODE" ] && { echo -e "${RED}--node required${NC}"; exit 1; }
[ -z "$ACTION" ] && { echo -e "${RED}--action required (shutdown|isolate|restore)${NC}"; exit 1; }

INVENTORY="ansible/inventory.ini"
NODE_IP=$(grep "$NODE" "$INVENTORY" | grep -oP 'ansible_host=\K[^ ]+' || true)

if [ -z "$NODE_IP" ]; then
  echo -e "${RED}Node $NODE not found in inventory${NC}"
  exit 1
fi

export KUBECONFIG

# ── Helper Functions ──────────────────────────────────────────

snapshot_pods() {
  echo -e "${BLUE}Current pod distribution across nodes:${NC}"
  kubectl get pods --all-namespaces -o wide --sort-by=.spec.nodeName \
    | awk '{printf "  %-50s %-20s %-15s\n", $2, $8, $4}'
}

wait_for_rescheduling() {
  local node=$1
  local elapsed=0
  echo -e "${YELLOW}Waiting for pods to reschedule off $node...${NC}"
  while [ $elapsed -lt $TIMEOUT ]; do
    local pods_on_node
    pods_on_node=$(kubectl get pods --all-namespaces -o wide 2>/dev/null \
      | grep "$node" | grep -v "Terminating\|Completed" | wc -l || echo 0)
    if [ "$pods_on_node" -eq 0 ]; then
      echo -e "${GREEN}All pods rescheduled away from $node!${NC}"
      return 0
    fi
    echo "  Still $pods_on_node pods on $node... ($elapsed/${TIMEOUT}s)"
    sleep 10
    elapsed=$((elapsed + 10))
  done
  echo -e "${RED}Timeout: pods did not reschedule within ${TIMEOUT}s${NC}"
  return 1
}

# ── Actions ───────────────────────────────────────────────────

case $ACTION in

  shutdown)
    echo -e "${YELLOW}==== FAULT TEST: Shutting down $NODE ($NODE_IP) ====${NC}"
    echo ""
    echo -e "${BLUE}[Before] Pod snapshot:${NC}"
    snapshot_pods
    echo ""

    echo -e "${RED}Simulating node failure: $NODE going offline...${NC}"
    # Cordon + drain first for controlled test, then simulate hard shutdown via SSH
    kubectl cordon "$NODE" 2>/dev/null || true
    ssh -o StrictHostKeyChecking=no -i ~/.ssh/cluster_key ubuntu@"$NODE_IP" \
      "sudo systemctl stop k3s-agent" 2>/dev/null || true

    echo ""
    echo -e "${YELLOW}Waiting for Kubernetes to detect the failure (node-monitor-grace-period: ~40s)...${NC}"
    sleep 45

    kubectl get nodes
    echo ""

    wait_for_rescheduling "$NODE"

    echo ""
    echo -e "${BLUE}[After] Pod snapshot:${NC}"
    snapshot_pods
    echo ""
    echo -e "${GREEN}Fault test complete. Run with --action restore to bring $NODE back.${NC}"
    ;;

  isolate)
    echo -e "${YELLOW}==== NETWORK PARTITION: Isolating $NODE ====${NC}"
    # Block all cluster traffic using iptables (simulates network split-brain)
    ssh -o StrictHostKeyChecking=no -i ~/.ssh/cluster_key ubuntu@"$NODE_IP" \
      "sudo iptables -I INPUT -s 192.168.1.0/24 -j DROP && sudo iptables -I OUTPUT -d 192.168.1.0/24 -j DROP"
    echo -e "${RED}$NODE is now network-isolated (split-brain scenario)${NC}"
    echo "Run --action restore to remove the isolation."
    ;;

  restore)
    echo -e "${YELLOW}==== RESTORE: Bringing $NODE back online ====${NC}"
    # Remove iptables blocks
    ssh -o StrictHostKeyChecking=no -i ~/.ssh/cluster_key ubuntu@"$NODE_IP" \
      "sudo iptables -D INPUT -s 192.168.1.0/24 -j DROP 2>/dev/null; \
       sudo iptables -D OUTPUT -d 192.168.1.0/24 -j DROP 2>/dev/null; \
       sudo systemctl start k3s-agent" 2>/dev/null || true

    kubectl uncordon "$NODE" 2>/dev/null || true

    echo -e "${YELLOW}Waiting for $NODE to rejoin cluster...${NC}"
    local elapsed=0
    while [ $elapsed -lt 60 ]; do
      local status
      status=$(kubectl get node "$NODE" --no-headers 2>/dev/null | awk '{print $2}' || echo "Unknown")
      if [ "$status" = "Ready" ]; then
        echo -e "${GREEN}$NODE is back online and Ready!${NC}"
        kubectl get nodes
        exit 0
      fi
      echo "  Node status: $status... ($elapsed/60s)"
      sleep 10
      elapsed=$((elapsed + 10))
    done
    echo -e "${RED}Node did not return to Ready within 60s. Check manually.${NC}"
    ;;

  *)
    echo -e "${RED}Unknown action: $ACTION. Use: shutdown | isolate | restore${NC}"
    exit 1
    ;;
esac
