#!/usr/bin/env bash
# =============================================================
# health-check.sh — Comprehensive Cluster Health Check
# Usage: ./scripts/health-check.sh
# =============================================================

set -euo pipefail

KUBECONFIG="${KUBECONFIG:-./kubeconfig.yml}"
export KUBECONFIG

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
PASS="${GREEN}✓${NC}"
FAIL="${RED}✗${NC}"

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║    Cluster Health Check                  ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

ERRORS=0

check() {
  local label=$1
  local cmd=$2
  if eval "$cmd" > /dev/null 2>&1; then
    echo -e "  $PASS $label"
  else
    echo -e "  $FAIL $label"
    ERRORS=$((ERRORS + 1))
  fi
}

# ── 1. Nodes ──────────────────────────────────────────────────
echo -e "${BLUE}[1] Node Status${NC}"
kubectl get nodes --no-headers | while read -r name status roles age version; do
  if [ "$status" = "Ready" ]; then
    echo -e "  $PASS $name [$roles] — $status ($version)"
  else
    echo -e "  $FAIL $name [$roles] — $status ($version)"
    ERRORS=$((ERRORS + 1))
  fi
done
echo ""

# ── 2. System Pods ────────────────────────────────────────────
echo -e "${BLUE}[2] System Pods (kube-system)${NC}"
NOT_RUNNING=$(kubectl get pods -n kube-system --no-headers 2>/dev/null \
  | awk '$4 != "Running" && $4 != "Completed"' | wc -l)
if [ "$NOT_RUNNING" -eq 0 ]; then
  echo -e "  $PASS All kube-system pods are Running"
else
  echo -e "  $FAIL $NOT_RUNNING kube-system pod(s) are NOT running:"
  kubectl get pods -n kube-system --no-headers | awk '$4 != "Running" && $4 != "Completed"' \
    | awk '{print "      " $1 " — " $4}'
  ERRORS=$((ERRORS + 1))
fi
echo ""

# ── 3. Monitoring Stack ───────────────────────────────────────
echo -e "${BLUE}[3] Monitoring Stack (monitoring namespace)${NC}"
check "Prometheus running" \
  "kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers | grep Running"
check "Grafana running" \
  "kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --no-headers | grep Running"
check "Alertmanager running" \
  "kubectl get pods -n monitoring -l app.kubernetes.io/name=alertmanager --no-headers | grep Running"
echo ""

# ── 4. Storage ────────────────────────────────────────────────
echo -e "${BLUE}[4] Storage${NC}"
check "rook-ceph operator running" \
  "kubectl get pods -n rook-ceph -l app=rook-ceph-operator --no-headers | grep Running"
check "StorageClass rook-ceph-block exists" \
  "kubectl get storageclass rook-ceph-block"
check "NFS mount available on master" \
  "ssh -o StrictHostKeyChecking=no ubuntu@192.168.1.10 'showmount -e localhost' 2>/dev/null"
echo ""

# ── 5. Resource Usage ─────────────────────────────────────────
echo -e "${BLUE}[5] Resource Usage${NC}"
echo "  Node resource summary:"
kubectl top nodes 2>/dev/null | awk 'NR==1{print "    " $0} NR>1{print "    " $0}' || \
  echo "    (metrics-server not available)"
echo ""

# ── 6. PersistentVolumeClaims ────────────────────────────────
echo -e "${BLUE}[6] PersistentVolumeClaims${NC}"
UNBOUND=$(kubectl get pvc --all-namespaces --no-headers 2>/dev/null \
  | awk '$4 != "Bound"' | wc -l)
if [ "$UNBOUND" -eq 0 ]; then
  echo -e "  $PASS All PVCs are Bound"
else
  echo -e "  $FAIL $UNBOUND PVC(s) not Bound:"
  kubectl get pvc --all-namespaces --no-headers | awk '$4 != "Bound"' \
    | awk '{print "      " $1 "/" $2 " — " $4}'
  ERRORS=$((ERRORS + 1))
fi
echo ""

# ── Summary ───────────────────────────────────────────────────
echo -e "${CYAN}══════════════════════════════════════════════${NC}"
if [ "$ERRORS" -eq 0 ]; then
  echo -e "  ${GREEN}All checks passed! Cluster is healthy.${NC}"
else
  echo -e "  ${RED}$ERRORS check(s) failed. Review the output above.${NC}"
fi
echo -e "${CYAN}══════════════════════════════════════════════${NC}"
echo ""

exit $ERRORS
