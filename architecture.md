# Architecture — Distributed Bare-Metal Compute Cluster

## Overview

This document details the full technical architecture of our distributed bare-metal compute cluster. The system is designed for **high availability**, **fault tolerance**, and **full observability** using 100% open-source tooling.

---

## System Topology

```
                          ┌────────────────────────────┐
                          │        Control Machine      │
                          │  (Ansible, kubectl, Helm)   │
                          └──────────────┬─────────────┘
                                         │ SSH / API
                         ════════════════╪════════════════
                         │    Internal Network 192.168.1.0/24    │
                         │                                        │
          ┌──────────────▼───────────────┐                        │
          │         master-1             │                        │
          │     (192.168.1.10)           │                        │
          │  ┌─────────────────────────┐ │                        │
          │  │  K3s API Server         │ │                        │
          │  │  etcd (embedded)        │ │                        │
          │  │  Kube Scheduler         │ │                        │
          │  │  Controller Manager     │ │                        │
          │  │  NFS Server             │ │                        │
          │  └─────────────────────────┘ │                        │
          └──────────────────────────────┘                        │
                         │                                        │
          ┌──────────────┼──────────────────────────────┐         │
          │              │                              │         │
┌─────────▼──────┐ ┌─────▼──────────┐ ┌───────────────▼──┐      │
│   worker-1     │ │   worker-2     │ │    worker-3       │      │
│ 192.168.1.11   │ │ 192.168.1.12   │ │  192.168.1.13     │      │
│ ┌────────────┐ │ │ ┌────────────┐ │ │ ┌───────────────┐ │      │
│ │ K3s Agent  │ │ │ │ K3s Agent  │ │ │ │  K3s Agent    │ │      │
│ │ Ceph OSD   │ │ │ │ Ceph OSD   │ │ │ │  Ceph OSD     │ │      │
│ │ NFS Client │ │ │ │ NFS Client │ │ │ │  NFS Client   │ │      │
│ │ Workloads  │ │ │ │ Workloads  │ │ │ │  Workloads    │ │      │
│ └────────────┘ │ │ └────────────┘ │ │ └───────────────┘ │      │
└────────────────┘ └────────────────┘ └──────────────────┘       │
                         │                                        │
                ┌────────▼────────┐                               │
                │  Storage Layer  │                               │
                │  NFS + Ceph     │                               │
                └─────────────────┘                               │
                                                                  │
         ═══════════════════════════════════════════════════════
```

---

## Component Deep-Dive

### 1. Container Orchestration: K3s

K3s is a certified, lightweight Kubernetes distribution. We chose K3s over full K8s because:

- **Low resource overhead** — single binary < 100MB, ideal for bare-metal nodes with limited RAM
- **Embedded etcd** — no need for an external etcd cluster for small deployments
- **Fast bootstrap** — cluster up in < 5 minutes via the install script
- **Full Kubernetes API compatibility** — all standard `kubectl` commands work

**K3s Components Deployed:**
- API Server on `master-1:6443`
- Embedded etcd (SQLite for single-master, etcd for HA mode)
- Flannel VXLAN CNI for pod networking
- CoreDNS for in-cluster DNS
- Local-path provisioner (supplemented by Ceph for persistent storage)

---

### 2. Automation: Ansible

All cluster operations are automated via Ansible playbooks. No manual SSH commands are needed after initial SSH key setup.

**Playbook Execution Order:**
```
site.yml
  ├── provision.yml      → OS packages, sysctl, firewall, swap disable
  ├── k3s-install.yml    → K3s server (master) + agents (workers)
  ├── storage.yml        → NFS server, Ceph via Rook operator
  └── monitoring.yml     → Prometheus + Grafana via Helm
```

**Idempotency:** All plays are idempotent — running the playbook multiple times produces the same result without duplicate configuration.

---

### 3. Storage Architecture

We use a **hybrid storage model** to cover different workload requirements:

#### NFS (Network File System)
- **Purpose**: `ReadWriteMany` shared volumes — multiple pods can mount the same volume simultaneously
- **Use Cases**: Shared config files, shared datasets, log aggregation volumes
- **Setup**: NFS server on `master-1`, exported to all worker nodes
- **Kubernetes Integration**: Via `nfs-subdir-external-provisioner` or manual PV/PVC definitions

#### Ceph (via Rook-Ceph Operator)
- **Purpose**: `ReadWriteOnce` block storage — high-performance, replicated, distributed
- **Use Cases**: Database persistent volumes (Prometheus TSDB, Grafana state, app databases)
- **Replication**: 3x replication across worker OSDs — data survives 1 OSD/node failure
- **StorageClass**: `rook-ceph-block` (set as default)

```
Storage Decision Matrix:
┌─────────────────┬──────────────┬─────────────────┐
│ Requirement     │ Use NFS      │ Use Ceph        │
├─────────────────┼──────────────┼─────────────────┤
│ Multiple writers│ ✓            │ ✗               │
│ High IOPS       │ ✗            │ ✓               │
│ Fault tolerance │ Limited      │ ✓ (3x repl.)    │
│ Dynamic prov.   │ ✓            │ ✓               │
│ Snapshots       │ ✗            │ ✓               │
└─────────────────┴──────────────┴─────────────────┘
```

---

### 4. Observability Stack

```
Metrics Pipeline:
node_exporter ──┐
kube-state-metrics ──┤──▶ Prometheus ──▶ Alertmanager ──▶ (email/webhook)
ceph-mgr (metrics) ──┘          │
                                 └──▶ Grafana Dashboards
```

**Prometheus** scrapes metrics every 15 seconds from:
- `node_exporter` on each node (CPU, RAM, disk, network)
- `kube-state-metrics` (pod states, deployment health)
- Ceph MGR metrics endpoint (storage cluster health)
- K3s/Kubernetes API server metrics

**Grafana** provides dashboards for:
- Node resource overview (dashboard ID: 1860)
- Kubernetes cluster overview (dashboard ID: 7249)
- Ceph cluster health (dashboard ID: 2842)

---

### 5. Networking

| Network Range     | Purpose                        |
|-------------------|--------------------------------|
| `192.168.1.0/24`  | Physical node network          |
| `10.42.0.0/16`    | Kubernetes pod CIDR (Flannel)  |
| `10.43.0.0/16`    | Kubernetes service CIDR        |

**CNI Plugin**: Flannel with VXLAN backend — creates an overlay network so pods on different physical nodes can communicate directly using pod IPs.

**Service Exposure**: NodePort services are used for Grafana (`:30300`) and other dashboards. A LoadBalancer (MetalLB) can be added for production use.

---

## Fault Tolerance Design

### Failure Modes & Responses

| Failure Type         | Detection Time  | Recovery Mechanism              |
|----------------------|-----------------|----------------------------------|
| Pod crash            | ~0s             | Restart policy (Always)          |
| Node unreachable     | ~40s            | Pod eviction + rescheduling      |
| NFS server down      | Immediate error | Pods use Ceph or local fallback  |
| Ceph OSD down        | ~30s            | Ceph re-replicates automatically |
| Network partition    | ~40s            | Isolation detected, pods evicted |

### Kubernetes Node Lifecycle

```
Node fails
   │
   ▼ (node-monitor-grace-period: 40s)
Node marked NotReady
   │
   ▼ (pod-eviction-timeout: 5m default / tuned to 30s)
Pods marked for eviction
   │
   ▼
Pods rescheduled to healthy nodes
   │
   ▼ (pod-eviction-timeout elapsed)
Pods Running on surviving nodes
```

---

## Security Considerations

- **SSH**: Key-based auth only; password auth disabled on all nodes
- **Firewall (UFW)**: Only required ports open (6443, 8472, 10250)
- **K3s API**: TLS-secured; kubeconfig stored locally, not committed to Git
- **RBAC**: Kubernetes Role-Based Access Control enabled by default
- **Secrets**: Sensitive values should use Kubernetes Secrets or an external secrets manager (e.g., Vault)

> ⚠️ **Note:** The kubeconfig file and any SSH private keys must NOT be committed to Git. They are listed in `.gitignore`.

---

## Future Enhancements

- [ ] High Availability Control Plane (3 master nodes with etcd cluster)
- [ ] MetalLB for LoadBalancer IP assignment
- [ ] cert-manager for TLS certificate automation
- [ ] Vault integration for secret management
- [ ] Multi-cluster federation
- [ ] GitOps with Flux or ArgoCD
