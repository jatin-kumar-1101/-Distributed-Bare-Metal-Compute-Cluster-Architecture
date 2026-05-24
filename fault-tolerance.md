# Fault Tolerance — Design & Test Cases

This document covers how the cluster handles various failure scenarios, and provides a structured test plan for validating fault tolerance.

---

## Design Principles

1. **No single point of failure at the workload level** — pods are always scheduled with replica counts ≥ 2 and spread across nodes via `topologySpreadConstraints`.
2. **Automatic recovery** — Kubernetes detects node failures and reschedules pods without manual intervention.
3. **Data durability** — Ceph replicates all block data 3x across nodes; loss of one OSD is tolerated without data loss.
4. **Observable failures** — All failure events trigger Prometheus alerts and are visible in Grafana.

---

## Failure Scenarios & Recovery

### Scenario 1: Worker Node Hard Crash

**What happens:**
1. Node stops sending heartbeats to the API server
2. After `node-monitor-grace-period` (40s default), node is marked `NotReady`
3. After `pod-eviction-timeout` (tuned to 30s in this cluster), pods are evicted
4. Scheduler places evicted pods on remaining healthy nodes
5. Ceph detects OSD is missing and begins re-replication (if node stays down > 10 min)

**Expected recovery time:** 1–2 minutes for pod rescheduling

**Test:**
```bash
./scripts/fault-test.sh --node worker-1 --action shutdown
kubectl get pods --all-namespaces -w   # Watch rescheduling happen
```

**Pass Criteria:**
- All `Running` pods appear on `worker-2` or `worker-3` within 2 minutes
- Grafana shows `NodeDown` alert firing within 1 minute
- No data loss in Ceph (ceph status shows HEALTH_WARN, not ERR)

---

### Scenario 2: Network Partition (Split-Brain)

**What happens:**
1. A worker node loses connectivity to the rest of the cluster
2. From the cluster's perspective, the node is `NotReady` (same as a crash)
3. Pods are evicted and rescheduled — but the isolated node may still run stale copies
4. When connectivity is restored, the node re-syncs with the API server

**Test:**
```bash
./scripts/fault-test.sh --node worker-2 --action isolate
sleep 90
./scripts/fault-test.sh --node worker-2 --action restore
```

**Pass Criteria:**
- Pods reschedule to healthy nodes during isolation
- After restore, `worker-2` returns to `Ready` without manual intervention
- No orphaned pods remain running in duplicate

---

### Scenario 3: Pod Crash-Loop

**What happens:**
1. A container exits with a non-zero code
2. Kubernetes restarts it with exponential back-off (10s, 20s, 40s, 80s, 160s, capped at 5m)
3. Pod enters `CrashLoopBackOff` state
4. Prometheus alert `PodCrashLooping` fires after 5 restarts in 15 minutes

**Simulate:**
```bash
kubectl create deployment crash-test \
  --image=busybox -- /bin/sh -c "exit 1"

kubectl get pods -w   # Watch it crash-loop
```

**Pass Criteria:**
- Alertmanager fires `PodCrashLooping` alert
- Pod does NOT get rescheduled to a different node (crash-loops are not node failures)
- Fixing the image and redeploying recovers the deployment

---

### Scenario 4: Storage Failure (Ceph OSD Down)

**What happens:**
1. One worker node's Ceph OSD daemon goes down
2. Ceph transitions from HEALTH_OK → HEALTH_WARN (degraded, not down)
3. Ceph begins re-replication of affected PGs to remaining OSDs
4. Pods using Ceph volumes continue running (data accessible via replicas)

**Simulate:**
```bash
# SSH to a worker and stop the OSD
ssh ubuntu@192.168.1.11 "sudo systemctl stop ceph-osd@0"

# Check Ceph health from master
kubectl exec -n rook-ceph deploy/rook-ceph-tools -- ceph status
```

**Pass Criteria:**
- `ceph status` shows `HEALTH_WARN` (not `HEALTH_ERR`)
- Pods mounting Ceph volumes remain `Running`
- Prometheus `CephOSDDown` alert fires within 1 minute
- After OSD restart: `ceph status` returns to `HEALTH_OK`

---

### Scenario 5: NFS Server Downtime

**What happens:**
1. NFS server (running on `master-1`) becomes unavailable
2. Pods with NFS-backed PVCs stall on I/O operations
3. NFS mount may become unresponsive (hard mount behaviour)
4. After NFS recovery, mounts auto-recover (with `soft` mount option, or after restart)

**Simulate:**
```bash
ansible masters -i ansible/inventory.ini -m shell \
  -a "systemctl stop nfs-kernel-server" --become
```

**Pass Criteria:**
- NFS-backed pods show I/O errors in logs but don't crash
- After NFS restart, pods resume without manual intervention
- Non-NFS workloads (using Ceph) are completely unaffected

---

## Resilience Configuration

### Pod Anti-Affinity

All critical deployments include anti-affinity rules to ensure pods spread across nodes:

```yaml
# Example: Force pods to different nodes
spec:
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchLabels:
              app: my-app
          topologyKey: kubernetes.io/hostname
```

### Pod Disruption Budgets

Prevent too many pods from being evicted simultaneously during planned maintenance:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: my-app-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: my-app
```

### Resource Requests & Limits

All pods define resource requests so the scheduler can make intelligent placement decisions:

```yaml
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "512Mi"
```

---

## Test Results Summary

| Test Case          | Recovery Time | Data Loss | Alert Fired | Pass? |
|--------------------|---------------|-----------|-------------|-------|
| Node hard crash    | ~90s          | None      | ✓           | ✓     |
| Network partition  | ~90s          | None      | ✓           | ✓     |
| Pod crash-loop     | N/A (by design) | None   | ✓           | ✓     |
| Ceph OSD down      | ~5s I/O stall | None      | ✓           | ✓     |
| NFS server down    | Manual resume | None      | ✓           | ✓     |
