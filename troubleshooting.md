# Troubleshooting Guide

Common issues encountered during setup and operation, with step-by-step fixes.

---

## K3s Issues

### Issue: Worker node won't join the cluster

**Symptoms:** `kubectl get nodes` doesn't show the worker after running the k3s-install playbook.

**Diagnose:**
```bash
# Check k3s-agent service on the worker
ssh ubuntu@<WORKER_IP> "sudo systemctl status k3s-agent"
sudo journalctl -u k3s-agent -n 50
```

**Common Causes:**
1. **Wrong node token** — The token from master may not have propagated correctly.
   ```bash
   # Get fresh token from master
   ssh ubuntu@<MASTER_IP> "sudo cat /var/lib/rancher/k3s/server/node-token"
   # Re-run k3s-install playbook
   ansible-playbook -i ansible/inventory.ini ansible/playbooks/k3s-install.yml
   ```

2. **Firewall blocking port 6443**
   ```bash
   # From worker, test connectivity to master API
   nc -zv 192.168.1.10 6443
   # If it fails, open the port
   ssh ubuntu@<MASTER_IP> "sudo ufw allow 6443/tcp"
   ```

3. **Time skew** — Nodes must have synchronized clocks.
   ```bash
   ansible all -i ansible/inventory.ini -m shell -a "date" --become
   # If times differ, install and sync NTP
   ansible all -i ansible/inventory.ini -m apt -a "name=chrony state=present" --become
   ansible all -i ansible/inventory.ini -m shell -a "systemctl restart chrony" --become
   ```

---

### Issue: Pods stuck in `Pending` state

**Diagnose:**
```bash
kubectl describe pod <pod-name> -n <namespace>
# Look at the Events section at the bottom
```

**Common Causes:**

1. **Insufficient resources** — All nodes are at capacity.
   ```bash
   kubectl top nodes
   kubectl describe nodes | grep -A5 "Allocated resources"
   ```

2. **No matching nodes for pod's affinity/tolerations**
   ```bash
   kubectl get pod <pod-name> -o yaml | grep -A10 affinity
   # Check if the node labels match
   kubectl get nodes --show-labels
   ```

3. **PVC not bound** (pod waiting for storage)
   ```bash
   kubectl get pvc --all-namespaces
   # If Pending, check StorageClass
   kubectl get storageclass
   kubectl describe pvc <pvc-name>
   ```

---

## Storage Issues

### Issue: Ceph cluster stuck in `HEALTH_WARN`

**Diagnose:**
```bash
# Get a shell in the Rook toolbox
kubectl exec -n rook-ceph -it deploy/rook-ceph-tools -- bash

# Inside toolbox:
ceph status
ceph health detail
ceph osd tree
```

**Common Causes:**

1. **OSD down (worker node offline)** — Expected when a node is off. Recover by bringing the node back.

2. **Insufficient OSDs for replication** — If you have fewer than 3 OSDs and `replicated.size=3`.
   ```bash
   # Temporarily lower replication (development only)
   ceph osd pool set replicapool size 2
   ceph osd pool set replicapool min_size 1
   ```

3. **Ceph operator not running**
   ```bash
   kubectl get pods -n rook-ceph -l app=rook-ceph-operator
   kubectl logs -n rook-ceph deploy/rook-ceph-operator | tail -30
   ```

---

### Issue: NFS mount fails on workers

**Diagnose:**
```bash
# On worker, try manual mount
sudo mount -t nfs 192.168.1.10:/srv/nfs/cluster-data /mnt/test -v

# On master, check NFS is exporting
sudo exportfs -v
sudo systemctl status nfs-kernel-server
```

**Fixes:**
```bash
# Restart NFS server on master
ansible masters -i ansible/inventory.ini -m shell \
  -a "systemctl restart nfs-kernel-server" --become

# Re-run storage playbook
ansible-playbook -i ansible/inventory.ini ansible/playbooks/storage.yml
```

---

## Monitoring Issues

### Issue: Grafana shows "No data" for dashboards

**Check Prometheus is actually scraping:**
1. Go to `http://<MASTER_IP>:9090/targets`
2. Look for targets in `DOWN` state

**Common causes:**

1. **node_exporter not running** on a node:
   ```bash
   kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus-node-exporter
   ```

2. **Prometheus can't reach node IPs** — Check Flannel is running:
   ```bash
   kubectl get pods -n kube-system -l app=flannel
   ```

3. **Grafana datasource misconfigured:**
   - Open Grafana → Configuration → Data Sources
   - Verify Prometheus URL is `http://kube-prometheus-stack-prometheus.monitoring.svc:9090`
   - Click "Save & Test"

---

### Issue: Helm install fails — "cannot re-use a name that is still in use"

```bash
# List existing Helm releases
helm list -A

# Uninstall the stuck release
helm uninstall kube-prometheus-stack -n monitoring

# Reinstall
helm upgrade --install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values kubernetes/helm-values/kube-prometheus-values.yml
```

---

## Ansible Issues

### Issue: "Permission denied" during playbook run

```bash
# Test SSH manually
ssh -i ~/.ssh/cluster_key ubuntu@192.168.1.10 "sudo ls /"

# If sudo asks for password, add NOPASSWD to sudoers
echo "ubuntu ALL=(ALL) NOPASSWD:ALL" | \
  ssh ubuntu@192.168.1.10 "sudo tee /etc/sudoers.d/ansible"
```

### Issue: Playbook hangs on reboot task

The reboot task waits for the node to come back. If it's taking too long:

```bash
# Check the node manually
ping 192.168.1.10

# If the node is back but Ansible is still waiting, press Ctrl+C
# and re-run the playbook — it's idempotent
ansible-playbook -i ansible/inventory.ini ansible/playbooks/site.yml
```

---

## Getting Help

1. Check Kubernetes events: `kubectl get events --all-namespaces --sort-by='.lastTimestamp'`
2. Check component logs: `kubectl logs -n <namespace> <pod-name>`
3. Run the health check: `./scripts/health-check.sh`
4. Open an issue on the project's GitHub repository
