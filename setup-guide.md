# Step-by-Step Setup Guide

This guide walks you through setting up the distributed bare-metal compute cluster from scratch.

---

## Prerequisites

### Hardware Requirements

| Role    | Min CPU | Min RAM | Min Disk | Count |
|---------|---------|---------|----------|-------|
| Master  | 2 cores | 4 GB    | 30 GB    | 1     |
| Worker  | 2 cores | 4 GB    | 40 GB    | 3+    |

> For Ceph, workers need an **additional raw/unformatted disk** (e.g., `/dev/sdb`) for OSD storage.

### Software Requirements (Control Machine)

```bash
# Install Ansible
pip install ansible

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### OS on Nodes

All nodes must run **Ubuntu 22.04 LTS** (Ubuntu Server recommended). The provisioning playbook handles everything else.

---

## Step 1: SSH Key Setup

Generate an SSH key for Ansible to use:

```bash
ssh-keygen -t ed25519 -C "cluster-key" -f ~/.ssh/cluster_key
```

Copy the key to all nodes:

```bash
# Replace IPs with your actual node IPs
for IP in 192.168.1.10 192.168.1.11 192.168.1.12 192.168.1.13; do
  ssh-copy-id -i ~/.ssh/cluster_key.pub ubuntu@$IP
done
```

Verify connectivity:

```bash
ssh -i ~/.ssh/cluster_key ubuntu@192.168.1.10 "hostname && uname -r"
```

---

## Step 2: Configure Inventory

Edit `ansible/inventory.ini`:

```ini
[masters]
master-1 ansible_host=<MASTER_IP> ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/cluster_key

[workers]
worker-1 ansible_host=<WORKER1_IP> ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/cluster_key
worker-2 ansible_host=<WORKER2_IP> ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/cluster_key
worker-3 ansible_host=<WORKER3_IP> ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/cluster_key
```

Test Ansible can reach all nodes:

```bash
ansible all -i ansible/inventory.ini -m ping
```

Expected output:
```
master-1 | SUCCESS => {"ping": "pong"}
worker-1 | SUCCESS => {"ping": "pong"}
worker-2 | SUCCESS => {"ping": "pong"}
worker-3 | SUCCESS => {"ping": "pong"}
```

---

## Step 3: Run the Bootstrap

```bash
chmod +x scripts/bootstrap.sh
./scripts/bootstrap.sh
```

This runs all four Ansible playbooks in sequence:

1. **provision.yml** (~5 min) — OS hardening, packages, kernel modules
2. **k3s-install.yml** (~3 min) — K3s cluster bootstrap
3. **storage.yml** (~8 min) — NFS + Rook-Ceph deployment
4. **monitoring.yml** (~5 min) — Prometheus + Grafana via Helm

Total time: approximately **20–25 minutes** on a fresh cluster.

---

## Step 4: Verify the Cluster

Set your kubeconfig:

```bash
export KUBECONFIG=$(pwd)/kubeconfig.yml
```

Check nodes:

```bash
kubectl get nodes -o wide
```

Expected output:
```
NAME       STATUS   ROLES                  AGE   VERSION        INTERNAL-IP
master-1   Ready    control-plane,master   5m    v1.29.4+k3s1   192.168.1.10
worker-1   Ready    <none>                 4m    v1.29.4+k3s1   192.168.1.11
worker-2   Ready    <none>                 4m    v1.29.4+k3s1   192.168.1.12
worker-3   Ready    <none>                 4m    v1.29.4+k3s1   192.168.1.13
```

Check all system pods:

```bash
kubectl get pods --all-namespaces
```

---

## Step 5: Access Monitoring Dashboards

### Grafana

Open in your browser: `http://<MASTER_IP>:30300`

- Username: `admin`
- Password: `admin` (you'll be prompted to change it)

Pre-loaded dashboards:
- **Node Exporter Full** — per-node CPU, RAM, disk, network
- **Kubernetes Cluster** — pod counts, resource usage
- **Ceph Storage** — OSD health, IOPS, capacity

### Prometheus

Open in your browser: `http://<MASTER_IP>:9090`

Try a sample query in the Prometheus UI:
```
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100
```

---

## Step 6: Run Health Check

```bash
./scripts/health-check.sh
```

All checks should show ✓ (green).

---

## Deploying a Test Workload

Deploy an Nginx pod across the cluster:

```bash
kubectl create deployment nginx-test --image=nginx --replicas=3
kubectl expose deployment nginx-test --type=NodePort --port=80
kubectl get pods -o wide   # Should spread across workers
```

---

## Troubleshooting

See [`docs/troubleshooting.md`](troubleshooting.md) for common issues.
