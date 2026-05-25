# ⚡ Distributed Bare-Metal Compute Cluster

> A production-grade, self-hosted Kubernetes cluster on bare-metal hardware — featuring automated provisioning, distributed storage, full observability, and fault tolerance.

<p align="center">
  <img src="https://img.shields.io/badge/Kubernetes-K3s-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white"/>
  <img src="https://img.shields.io/badge/Ansible-Automation-EE0000?style=for-the-badge&logo=ansible&logoColor=white"/>
  <img src="https://img.shields.io/badge/Prometheus-Monitoring-E6522C?style=for-the-badge&logo=prometheus&logoColor=white"/>
  <img src="https://img.shields.io/badge/Grafana-Dashboards-F46800?style=for-the-badge&logo=grafana&logoColor=white"/>
  <img src="https://img.shields.io/badge/Ceph-Storage-EF5C55?style=for-the-badge&logo=ceph&logoColor=white"/>
  <img src="https://img.shields.io/badge/NFS-Shared%20Storage-003399?style=for-the-badge"/>
</p>

---

## 📌 Project Overview

This project implements a **distributed compute cluster on bare-metal nodes** using lightweight Kubernetes (K3s), fully automated with Ansible. It includes:

- **K3s** — Lightweight Kubernetes for resource-constrained bare-metal nodes  
- **Ansible** — Zero-touch node provisioning and cluster lifecycle management  
- **Prometheus + Grafana** — Full observability stack with alerting  
- **NFS + Ceph** — Hybrid storage: NFS for shared volumes, Ceph for distributed block storage  
- **Fault Tolerance** — Node failure simulation, pod rescheduling, and health checks  

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        CLUSTER TOPOLOGY                         │
│                                                                 │
│   ┌──────────────┐     ┌──────────────┐    ┌──────────────┐    │
│   │  Master Node  │────▶│ Worker Node 1│    │ Worker Node 2│    │
│   │  (Control    │     │  (Compute)   │    │  (Compute)   │    │
│   │   Plane)     │     │              │    │              │    │
│   └──────┬───────┘     └──────┬───────┘    └──────┬───────┘    │
│          │                   │                    │             │
│          └───────────────────┼────────────────────┘             │
│                              │                                   │
│                    ┌─────────▼──────────┐                       │
│                    │   Storage Layer     │                       │
│                    │  NFS  │  Ceph OSD  │                       │
│                    └────────────────────┘                       │
│                                                                 │
│   ┌──────────────────────────────────────────────────────┐      │
│   │               Observability Stack                    │      │
│   │    Prometheus  ──▶  Alertmanager  ──▶  Grafana       │      │
│   └──────────────────────────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────────┘
```

### Node Roles

| Node       | Role          | Components                        |
|------------|---------------|-----------------------------------|
| `master-1` | Control Plane | K3s server, etcd, API server      |
| `worker-1` | Compute       | K3s agent, Ceph OSD, NFS client   |
| `worker-2` | Compute       | K3s agent, Ceph OSD, NFS client   |
| `worker-3` | Compute       | K3s agent, Ceph OSD, NFS client   |

---

## 🧱 Tech Stack

| Layer          | Technology             | Purpose                              |
|----------------|------------------------|--------------------------------------|
| Orchestration  | K3s (Kubernetes)       | Container scheduling & management    |
| Automation     | Ansible                | Node provisioning & config mgmt      |
| Monitoring     | Prometheus             | Metrics collection & alerting        |
| Visualization  | Grafana                | Dashboards & time-series graphs      |
| Shared Storage | NFS                    | ReadWriteMany volumes                |
| Block Storage  | Ceph / Rook-Ceph       | Distributed, replicated block store  |
| Networking     | Flannel (via K3s)      | Pod networking & CNI                 |
| CI/CD          | GitHub Actions         | Lint, validate, and deploy pipelines |

---

## 📁 Repository Structure

```
distributed-bare-metal-cluster/
├── ansible/
│   ├── inventory.ini              # Node inventory (IPs & roles)
│   ├── playbooks/
│   │   ├── site.yml               # Master playbook — runs everything
│   │   ├── provision.yml          # Base OS setup
│   │   ├── k3s-install.yml        # K3s cluster bootstrap
│   │   ├── monitoring.yml         # Deploy Prometheus + Grafana
│   │   └── storage.yml            # NFS + Ceph setup
│   └── roles/
│       ├── common/                # Base packages, SSH hardening
│       ├── k3s/                   # K3s server & agent roles
│       ├── monitoring/            # Prometheus + Grafana roles
│       ├── storage/               # Ceph role
│       └── nfs/                   # NFS server/client role
├── kubernetes/
│   ├── manifests/
│   │   ├── monitoring/            # Prometheus + Grafana K8s manifests
│   │   ├── storage/               # StorageClass, PVC definitions
│   │   └── apps/                  # Sample workloads
│   └── helm-values/               # Helm chart value overrides
├── monitoring/
│   ├── prometheus/
│   │   └── prometheus.yml         # Scrape configs & alerting rules
│   └── grafana/
│       └── dashboards/            # Exported Grafana dashboard JSONs
├── scripts/
│   ├── bootstrap.sh               # One-shot cluster bootstrap
│   ├── fault-test.sh              # Fault tolerance simulation
│   ├── health-check.sh            # Cluster health check script
│   └── teardown.sh                # Clean cluster teardown
├── docs/
│   ├── setup-guide.md             # Step-by-step setup guide
│   ├── architecture.md            # Detailed architecture doc
│   ├── fault-tolerance.md         # Fault tolerance design & tests
│   └── troubleshooting.md         # Common issues & fixes
├── .github/
│   └── workflows/
│       ├── lint.yml               # Ansible lint + YAML validation
│       └── validate.yml           # K8s manifest validation
├── .gitignore
└── README.md
```

---

## 🚀 Quick Start

### Prerequisites

- 3+ bare-metal machines (or VMs) running **Ubuntu 22.04 LTS**
- Ansible installed on your control machine (`pip install ansible`)
- SSH key-based access to all nodes
- Minimum specs per node: 2 vCPU, 4GB RAM, 20GB disk

### 1. Clone the Repository

```bash
git clone https://github.com/<your-username>/distributed-bare-metal-cluster.git
cd distributed-bare-metal-cluster
```

### 2. Configure Inventory

Edit `ansible/inventory.ini` with your node IPs:

```ini
[masters]
master-1 ansible_host=192.168.1.10 ansible_user=ubuntu

[workers]
worker-1 ansible_host=192.168.1.11 ansible_user=ubuntu
worker-2 ansible_host=192.168.1.12 ansible_user=ubuntu
worker-3 ansible_host=192.168.1.13 ansible_user=ubuntu
```

### 3. Bootstrap the Cluster

```bash
chmod +x scripts/bootstrap.sh
./scripts/bootstrap.sh
```

Or run Ansible directly:

```bash
ansible-playbook -i ansible/inventory.ini ansible/playbooks/site.yml
```

### 4. Verify the Cluster

```bash
# SSH into master node
ssh ubuntu@192.168.1.10

# Check node status
kubectl get nodes -o wide

# Check all pods
kubectl get pods --all-namespaces
```

### 5. Access Dashboards

| Service    | URL                            | Default Credentials   |
|------------|--------------------------------|-----------------------|
| Grafana    | `http://<master-ip>:3000`      | `admin / admin`       |
| Prometheus | `http://<master-ip>:9090`      | No auth (internal)    |

---

## 🔥 Fault Tolerance Testing

Simulate a node failure and observe automatic pod rescheduling:

```bash
./scripts/fault-test.sh --node worker-1 --action shutdown
```

Watch pods reschedule in real time:

```bash
kubectl get pods --all-namespaces -w
```

See [`docs/fault-tolerance.md`](docs/fault-tolerance.md) for the full test suite.

---

## 📊 Observability

### Metrics Collected

- **Node-level**: CPU, RAM, disk I/O, network throughput (via `node_exporter`)
- **Pod-level**: Container CPU/memory limits vs. usage (via `kube-state-metrics`)
- **Storage**: Ceph cluster health, OSD usage, IOPS
- **Custom alerts**: Node down, disk > 80%, pod crash-looping

### Sample Alert Rule

```yaml
# monitoring/prometheus/prometheus.yml
groups:
  - name: cluster.rules
    rules:
      - alert: NodeDown
        expr: up{job="node"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Node {{ $labels.instance }} is down"
```

---

## 📄 License

This project is licensed under the **MIT License** — see [`LICENSE`](LICENSE) for details.

---

<p align="center">Made with ☕ and late nights at <strong>GLA University, Mathura</strong></p>
