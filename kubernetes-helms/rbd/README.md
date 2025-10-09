# Ceph RBD Storage Setup for Kubernetes

Complete guide to configure Ceph RBD storage provisioning in Kubernetes using ceph-csi driver.

## Prerequisites

- Kubernetes cluster (v1.30+)
- Ceph cluster (Squid/v19+) with:
  - 3 monitors running
  - At least 1 OSD
  - RBD pool created (e.g., `kube`)
- Network connectivity between Kubernetes nodes and Ceph monitors
- Ubuntu 24.04 worker nodes with kernel 6.8+

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Kubernetes Cluster                      │
│                                                          │
│  ┌──────────────┐    ┌──────────────┐                  │
│  │ PVC Request  │───▶│ CSI Provider │                  │
│  └──────────────┘    └──────┬───────┘                  │
│                              │                           │
│                              ▼                           │
│                     ┌────────────────┐                  │
│                     │  CSI NodePlugin│                  │
│                     └────────┬───────┘                  │
│                              │                           │
└──────────────────────────────┼───────────────────────────┘
                               │
                               ▼
                    ┌──────────────────┐
                    │  Ceph Cluster    │
                    │  (RBD Pool)      │
                    └──────────────────┘
```

## Step 1: Prepare Ceph Cluster

### 1.1 Create RBD Pool

```bash
# On Ceph monitor node
ceph osd pool create kube 32 32
ceph osd pool application enable kube rbd
```

### 1.2 Initialize RBD Pool

```bash
rbd pool init kube
```

### 1.3 Get Ceph Cluster Information

```bash
# Get cluster FSID
ceph fsid
# Example output: 8a8c14c8-f022-48bd-96f8-892cddb2dc43

# Get monitor addresses
ceph mon dump | grep addr
# Example: 10.0.0.4:6789, 10.0.0.5:6789, 10.0.0.6:6789

# Get admin key
ceph auth get client.admin
```

### 1.4 Fix Ceph Monitor Authentication (If Needed)

If you encounter `handle_auth_bad_method` errors, rebuild monitor auth databases:

```bash
# On EACH monitor node, one at a time (wait 30 seconds between each)
systemctl stop ceph-mon@$(hostname -s)
rm -f /var/lib/ceph/mon/ceph-$(hostname -s)/store.db/auth*
systemctl start ceph-mon@$(hostname -s)
sleep 30
```

### 1.5 Create Kubernetes Client User

**Option 1: For Production (Recommended)**

Create a dedicated user with limited permissions:

```bash
# Create client.k8s user
ceph auth get-or-create client.k8s \
  mon 'profile rbd' \
  osd 'profile rbd pool=kube' \
  mgr 'profile rbd pool=kube' \
  -o /tmp/ceph.client.k8s.keyring

# View the credentials
cat /tmp/ceph.client.k8s.keyring

# Test authentication (IMPORTANT: Use file-based keyring)
ceph -s --keyring=/tmp/ceph.client.k8s.keyring --id=k8s
rbd ls kube --keyring=/tmp/ceph.client.k8s.keyring --id=k8s
```

**Option 2: For Testing/Troubleshooting**

Use admin credentials temporarily:

```bash
# Get admin key
grep key /etc/ceph/ceph.client.admin.keyring
# Example: AQCKiNloCtRhNRAArqvVfeOSW+4OvFmennHtzg==
```

**Important Note**: Due to a known go-ceph library incompatibility with Ceph Squid in ceph-csi v3.7.2, you may need to use admin credentials. The client.k8s user works with CLI tools but may fail with the CSI driver. This is acceptable for internal/test environments.

## Step 2: Install RBD Kernel Module on Kubernetes Nodes

The RBD kernel module must be loaded on all Kubernetes worker nodes.

### 2.1 Create RBD Module Installer DaemonSet

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: rbd-module-installer
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: rbd-module-installer
  template:
    metadata:
      labels:
        app: rbd-module-installer
    spec:
      hostNetwork: true
      hostPID: true
      nodeSelector:
        kubernetes.io/os: linux
      tolerations:
      - effect: NoSchedule
        operator: Exists
      containers:
      - name: installer
        image: ubuntu:24.04
        command: ["/bin/bash", "-c"]
        args:
          - |
            apt-get update -qq && apt-get install -y -qq kmod linux-modules-extra-$(uname -r) > /dev/null 2>&1
            modprobe rbd
            if lsmod | grep -q rbd; then
              echo "$(date) - RBD module loaded on $(hostname)"
            else
              echo "$(date) - ERROR: Failed to load RBD module on $(hostname)"
              exit 1
            fi
            # Keep container running
            while true; do sleep 3600; done
        securityContext:
          privileged: true
      restartPolicy: Always
EOF
```

### 2.2 Verify Module Installation

```bash
# Check DaemonSet status
kubectl get ds rbd-module-installer -n kube-system

# Verify all pods are running
kubectl get pods -n kube-system -l app=rbd-module-installer

# Check logs
kubectl logs -n kube-system -l app=rbd-module-installer --tail=5
```

## Step 3: Configure Kubernetes Storage Components

### 3.1 Create Namespace

```bash
kubectl create namespace ceph-csi-rbd
```

### 3.2 Update Configuration Files

**Update `ceph-csi-configmap.yml`** with your Ceph cluster information:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ceph-csi-config
  namespace: ceph-csi-rbd
data:
  config.json: |
    [
      {
        "clusterID": "8a8c14c8-f022-48bd-96f8-892cddb2dc43",  # Replace with your ceph fsid
        "monitors": [
          "10.0.0.4:6789",  # Replace with your monitor IPs
          "10.0.0.5:6789",
          "10.0.0.6:6789"
        ]
      }
    ]
```

**Update `rbd-secret.yml`** with your Ceph credentials:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: csi-rbd-secret
  namespace: ceph-csi-rbd
type: Opaque
stringData:
  userID: "admin"  # Or "client.k8s" if using dedicated user
  userKey: "AQCiQ+doxy+ULRAAeeYt1xllpQ9JZVNAd/pv8A=="  # Replace with your key
```

**Update `rbd-sc.yml`** with your cluster ID and pool name:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: csi-rbd-sc
provisioner: rbd.csi.ceph.com
parameters:
  clusterID: "8a8c14c8-f022-48bd-96f8-892cddb2dc43"  # Replace with your ceph fsid
  pool: kube  # Replace with your RBD pool name
  imageFormat: "2"
  imageFeatures: layering
  csi.storage.k8s.io/provisioner-secret-name: csi-rbd-secret
  csi.storage.k8s.io/provisioner-secret-namespace: ceph-csi-rbd
  csi.storage.k8s.io/controller-delete-secret-name: csi-rbd-secret
  csi.storage.k8s.io/controller-delete-secret-namespace: ceph-csi-rbd
  csi.storage.k8s.io/controller-expand-secret-name: csi-rbd-secret
  csi.storage.k8s.io/controller-expand-secret-namespace: ceph-csi-rbd
  csi.storage.k8s.io/node-stage-secret-name: csi-rbd-secret
  csi.storage.k8s.io/node-stage-secret-namespace: ceph-csi-rbd
reclaimPolicy: Delete
volumeBindingMode: Immediate
```

### 3.3 Apply Configuration

```bash
# Apply ConfigMap and Secret
kubectl apply -f ceph-csi-configmap.yml
kubectl apply -f rbd-secret.yml

# Apply StorageClass
kubectl apply -f rbd-sc.yml
```

### 3.4 Create Ceph Config (for CSI driver)

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ceph-config
  namespace: ceph-csi-rbd
data:
  ceph.conf: |
    [global]
      auth_cluster_required = cephx
      auth_service_required = cephx
      auth_client_required = cephx
      mon_host = 10.0.0.4:6789,10.0.0.5:6789,10.0.0.6:6789
      fsid = 8a8c14c8-f022-48bd-96f8-892cddb2dc43
  keyring: |
    [admin]
      key = AQCiQ+doxy+ULRAAeeYt1xllpQ9JZVNAd/pv8A==
EOF
```

**Note**: Replace the values with your actual Ceph cluster information.

## Step 4: Install Ceph CSI Driver

### 4.1 Add Ceph CSI Helm Repository

```bash
helm repo add ceph-csi https://ceph.github.io/csi-charts
helm repo update
```

### 4.2 Install RBD CSI Driver

```bash
helm install ceph-csi-rbd ceph-csi/ceph-csi-rbd \
  --namespace ceph-csi-rbd \
  --version 3.7.2 \
  --values values-rbd.yml
```

### 4.3 Verify Installation

```bash
# Check provisioner pods (should be 3 replicas, all Running)
kubectl get pods -n ceph-csi-rbd -l app=ceph-csi-rbd,component=provisioner

# Check nodeplugin pods (should be 1 per worker node, all Running 3/3)
kubectl get pods -n ceph-csi-rbd -l app=ceph-csi-rbd,component=nodeplugin

# Check StorageClass
kubectl get storageclass csi-rbd-sc
```

Expected output:
```
NAME         PROVISIONER           RECLAIMPOLICY   VOLUMEBINDINGMODE   AGE
csi-rbd-sc   rbd.csi.ceph.com      Delete          Immediate           5m
```

## Step 5: Test Storage Provisioning

### 5.1 Create Test PVC and Pod

```bash
kubectl apply -f test-pvc-and-pod.yaml
```

### 5.2 Verify Provisioning

```bash
# Check PVC status (should show "Bound")
kubectl get pvc rbd-pvc -n default

# Check PV was created
kubectl get pv

# Check pod status (should show "Running")
kubectl get pod app-using-pvc -n default

# Verify volume is mounted
kubectl exec -n default app-using-pvc -- df -h /mnt/data

# Check data was written
kubectl exec -n default app-using-pvc -- cat /mnt/data/hello.txt
```

Expected output:
```
# PVC should be Bound
NAME      STATUS   VOLUME                                     CAPACITY   ACCESS MODES
rbd-pvc   Bound    pvc-xxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx     1Gi        RWO

# Pod should be Running
NAME            READY   STATUS    RESTARTS   AGE
app-using-pvc   1/1     Running   0          2m

# Volume should be mounted as /dev/rbd0
Filesystem      Size  Used Avail Use% Mounted on
/dev/rbd0       973M   28K  957M   0% /mnt/data

# File should contain "Hello"
Hello
```

## Troubleshooting

### Problem 1: Permission Denied Errors

**Symptom**: PVC stuck in "Pending" with error:
```
failed to provision volume: rpc error: code = Internal desc = failed to get connection: connecting failed: rados: ret=-13, Permission denied
```

**Solution**:

1. **Test Ceph authentication from server:**
   ```bash
   # On Ceph monitor node
   ceph -s --keyring=/tmp/ceph.client.k8s.keyring --id=k8s
   ```

2. **If authentication fails, rebuild monitor auth databases:**
   ```bash
   # On each monitor, one at a time
   systemctl stop ceph-mon@$(hostname -s)
   rm -f /var/lib/ceph/mon/ceph-$(hostname -s)/store.db/auth*
   systemctl start ceph-mon@$(hostname -s)
   sleep 30
   ```

3. **Recreate the k8s user:**
   ```bash
   ceph auth del client.k8s
   ceph auth get-or-create client.k8s \
     mon 'profile rbd' \
     osd 'profile rbd pool=kube' \
     mgr 'profile rbd pool=kube'
   ```

4. **Update Kubernetes secret with new key:**
   ```bash
   NEW_KEY=$(ceph auth get client.k8s | grep key | awk '{print $3}')
   kubectl delete secret csi-rbd-secret -n ceph-csi-rbd
   kubectl create secret generic csi-rbd-secret -n ceph-csi-rbd \
     --from-literal=userID=client.k8s \
     --from-literal=userKey=$NEW_KEY
   ```

5. **Restart CSI provisioner:**
   ```bash
   kubectl rollout restart deployment/ceph-csi-rbd-provisioner -n ceph-csi-rbd
   ```

### Problem 2: RBD Kernel Module Not Loaded

**Symptom**: Nodeplugin pods crash with error:
```
modprobe: ERROR: could not insert 'rbd': Exec format error
```

**Solution**:

1. **Install RBD module using DaemonSet (see Step 2.1)**

2. **Verify module is loaded:**
   ```bash
   kubectl get pods -n kube-system -l app=rbd-module-installer
   ```

3. **Restart nodeplugins:**
   ```bash
   kubectl rollout restart daemonset/ceph-csi-rbd-nodeplugin -n ceph-csi-rbd
   ```

### Problem 3: CSI Driver Not Found

**Symptom**: Pod stuck in "ContainerCreating" with error:
```
driver name rbd.csi.ceph.com not found in the list of registered CSI drivers
```

**Solution**:

1. **Check nodeplugin pods are running on the same node:**
   ```bash
   kubectl get pods -n ceph-csi-rbd -o wide | grep nodeplugin
   ```

2. **Check nodeplugin logs:**
   ```bash
   kubectl logs -n ceph-csi-rbd -l app=ceph-csi-rbd,component=nodeplugin -c csi-rbdplugin
   ```

3. **Restart nodeplugins:**
   ```bash
   kubectl rollout restart daemonset/ceph-csi-rbd-nodeplugin -n ceph-csi-rbd
   ```

### Problem 4: go-ceph Library Incompatibility

**Symptom**: Authentication works with CLI tools but fails with CSI driver.

**Workaround**: Use admin credentials temporarily:

```bash
kubectl patch secret csi-rbd-secret -n ceph-csi-rbd -p '{"stringData":{"userID":"admin","userKey":"YOUR_ADMIN_KEY"}}'
kubectl rollout restart deployment/ceph-csi-rbd-provisioner -n ceph-csi-rbd
```

**Permanent Fix**: Upgrade to ceph-csi v3.8+ when available, which has better Ceph Squid support.

## Verification Checklist

- [ ] Ceph cluster is healthy: `ceph -s`
- [ ] RBD pool exists and is initialized: `rbd ls kube`
- [ ] Ceph authentication works: `ceph -s --keyring=/tmp/ceph.client.k8s.keyring --id=k8s`
- [ ] RBD module loaded on all nodes: `kubectl get pods -n kube-system -l app=rbd-module-installer`
- [ ] CSI provisioner pods running: `kubectl get pods -n ceph-csi-rbd -l component=provisioner`
- [ ] CSI nodeplugin pods running: `kubectl get pods -n ceph-csi-rbd -l component=nodeplugin`
- [ ] StorageClass exists: `kubectl get storageclass csi-rbd-sc`
- [ ] Test PVC provisions successfully: `kubectl get pvc rbd-pvc`
- [ ] Test pod can mount and write to volume: `kubectl exec app-using-pvc -- cat /mnt/data/hello.txt`

## Maintenance

### Update Ceph Credentials

```bash
# Get new key from Ceph
NEW_KEY=$(ceph auth get client.k8s | grep key | awk '{print $3}')

# Update Kubernetes secret
kubectl delete secret csi-rbd-secret -n ceph-csi-rbd
kubectl create secret generic csi-rbd-secret -n ceph-csi-rbd \
  --from-literal=userID=client.k8s \
  --from-literal=userKey=$NEW_KEY

# Update ConfigMap keyring
kubectl patch configmap ceph-config -n ceph-csi-rbd --type merge -p "{\"data\":{\"keyring\":\"[client.k8s]\n  key = $NEW_KEY\n\"}}"

# Restart CSI components
kubectl rollout restart deployment/ceph-csi-rbd-provisioner -n ceph-csi-rbd
kubectl rollout restart daemonset/ceph-csi-rbd-nodeplugin -n ceph-csi-rbd
```

### Scale Provisioner Replicas

```bash
kubectl scale deployment ceph-csi-rbd-provisioner -n ceph-csi-rbd --replicas=5
```

### View CSI Driver Logs

```bash
# Provisioner logs
kubectl logs -n ceph-csi-rbd -l component=provisioner -c csi-rbdplugin --tail=50

# Nodeplugin logs
kubectl logs -n ceph-csi-rbd -l component=nodeplugin -c csi-rbdplugin --tail=50
```

## Important Notes

1. **Credentials**: This setup currently uses admin credentials due to go-ceph compatibility issues with Ceph Squid. For production, consider upgrading to ceph-csi v3.8+ or using Ceph Pacific/Quincy.

2. **RBD Module Persistence**: The RBD module installer DaemonSet ensures the module is loaded after node reboots. Do not delete this DaemonSet.

3. **Backup**: Always backup your Ceph credentials and cluster configuration before making changes.

4. **Monitoring**: Set up monitoring for:
   - CSI provisioner pod health
   - CSI nodeplugin pod health
   - Ceph cluster health
   - PV provisioning metrics

## References

- [Ceph CSI Documentation](https://github.com/ceph/ceph-csi)
- [Ceph RBD Documentation](https://docs.ceph.com/en/latest/rbd/)
- [Kubernetes CSI Documentation](https://kubernetes-csi.github.io/docs/)

## Support

For issues specific to this setup, check the troubleshooting section above. For general Ceph or Kubernetes issues, refer to their official documentation.

---

**Last Updated**: 2025-10-09
**Tested With**:
- Kubernetes: v1.30.14
- Ceph: Squid (v19)
- ceph-csi: v3.7.2
- Ubuntu: 24.04 LTS (Kernel 6.8.0-85)
