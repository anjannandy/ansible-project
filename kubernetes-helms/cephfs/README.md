# CephFS Storage Setup for Kubernetes (ReadWriteMany)

Complete guide to configure CephFS storage provisioning in Kubernetes using ceph-csi driver for **ReadWriteMany (RWX)** volumes that can be shared across multiple pods.

## Prerequisites

- Kubernetes cluster (v1.30+)
- Ceph cluster (Squid/v19+) with:
  - 3 monitors running
  - At least 1 MDS (Metadata Server) for CephFS
  - At least 1 OSD
  - CephFS filesystem created
- Network connectivity between Kubernetes nodes and Ceph monitors
- Ubuntu 24.04 worker nodes with kernel 6.8+
- RBD CSI driver already working (see `../rbd/README.md`)

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  Kubernetes Cluster                          │
│                                                              │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐                │
│  │  Pod 1   │   │  Pod 2   │   │  Pod 3   │                │
│  │  (RWX)   │   │  (RWX)   │   │  (RWX)   │                │
│  └────┬─────┘   └────┬─────┘   └────┬─────┘                │
│       │              │              │                        │
│       └──────────────┼──────────────┘                        │
│                      │                                       │
│                      ▼                                       │
│            ┌─────────────────┐                              │
│            │  CephFS Volume  │  (Shared Filesystem)         │
│            │   CSI Driver    │                              │
│            └────────┬────────┘                              │
│                     │                                       │
└─────────────────────┼───────────────────────────────────────┘
                      │
                      ▼
           ┌──────────────────────┐
           │   Ceph Cluster       │
           │   CephFS Filesystem  │
           │   MDS + OSDs         │
           └──────────────────────┘
```

## Key Differences: CephFS vs RBD

| Feature | RBD (Block) | CephFS (Filesystem) |
|---------|-------------|---------------------|
| Access Mode | ReadWriteOnce (RWO) | ReadWriteMany (RWX) |
| Use Case | Single pod access | Multiple pods sharing data |
| Technology | Block device | POSIX filesystem |
| Performance | Higher IOPS | Better for shared files |
| Examples | Databases, single app | Shared configs, logs, media |

## Step 1: Prepare Ceph Cluster for CephFS

### 1.1 Check Existing CephFS

```bash
# On Ceph monitor node
ceph fs ls
```

If you see output like `name: cephfs, metadata pool: cephfs_metadata, data pools: [cephfs_data]`, you already have CephFS. Skip to step 1.3.

### 1.2 Create CephFS (If Doesn't Exist)

```bash
# Create data and metadata pools
ceph osd pool create cephfs_data 32 32
ceph osd pool create cephfs_metadata 16 16

# Create the filesystem
ceph fs new cephfs cephfs_metadata cephfs_data

# Verify filesystem was created
ceph fs ls

# Check MDS (Metadata Server) status
ceph mds stat
```

Expected output:
```
cephfs:1 {0=mds.server01=up:active} 2 up:standby
```

### 1.3 Create Kubernetes Client User

**Important**: Based on the RBD experience, we'll use admin credentials due to go-ceph compatibility issues with Ceph Squid.

**Option 1: Use Admin Credentials (Recommended for Compatibility)**

```bash
# Get admin key
grep key /etc/ceph/ceph.client.admin.keyring
# Output: key = AQCKiNloCtRhNRAArqvVfeOSW+4OvFmennHtzg==
```

**Option 2: Create Dedicated User (For Production - May Have Compatibility Issues)**

```bash
# Create client.k8sfs user
ceph auth get-or-create client.k8sfs \
  mon 'allow r' \
  osd 'allow rw pool=cephfs_data' \
  mds 'allow rw' \
  -o /tmp/ceph.client.k8sfs.keyring

# View the credentials
cat /tmp/ceph.client.k8sfs.keyring

# Test authentication (IMPORTANT: Use file-based keyring)
ceph fs ls --keyring=/tmp/ceph.client.k8sfs.keyring --id=k8sfs
```

### 1.4 Get Ceph Cluster Information

```bash
# Get cluster FSID
ceph fsid
# Example: 8a8c14c8-f022-48bd-96f8-892cddb2dc43

# Get monitor addresses
ceph mon dump | grep addr
# Example: 10.0.0.4:6789, 10.0.0.5:6789, 10.0.0.6:6789

# Get CephFS name
ceph fs ls
# Example: name: cephfs

# Get data pool name
ceph fs ls | grep "data pools"
# Example: data pools: [cephfs_data]
```

## Step 2: Configure Kubernetes Storage Components

### 2.1 Update Configuration Files

**Update `cephfs-secret.yml`** with your Ceph credentials:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: csi-cephfs-secret
  namespace: ceph-csi-cephfs
type: Opaque
stringData:
  # Use admin credentials for compatibility
  adminID: "admin"
  adminKey: "AQCKiNloCtRhNRAArqvVfeOSW+4OvFmennHtzg=="  # Replace with your admin key

  # OR use dedicated user (may have go-ceph compatibility issues)
  # userID: "k8sfs"
  # userKey: "YOUR_K8SFS_KEY_HERE"
```

**Update `ceph-csi-configmap.yml`** (should already be correct):

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ceph-csi-config
  namespace: ceph-csi-cephfs
data:
  config.json: |
    [
      {
        "clusterID": "8a8c14c8-f022-48bd-96f8-892cddb2dc43",  # Your Ceph fsid
        "monitors": [
          "10.0.0.4:6789",  # Your monitor IPs
          "10.0.0.5:6789",
          "10.0.0.6:6789"
        ]
      }
    ]
```

**Update `cephfs-config.yml`** with your credentials:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ceph-config
  namespace: ceph-csi-cephfs
data:
  ceph.conf: |
    [global]
      auth_cluster_required = cephx
      auth_service_required = cephx
      auth_client_required = cephx
      mon_host = 10.0.0.4:6789,10.0.0.5:6789,10.0.0.6:6789
      fsid = 8a8c14c8-f022-48bd-96f8-892cddb2dc43
  keyring: |
    [client.admin]
      key = AQCKiNloCtRhNRAArqvVfeOSW+4OvFmennHtzg==
```

**Update `cephfs-storageclass.yml`** if needed:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: csi-cephfs-sc
provisioner: cephfs.csi.ceph.com
parameters:
  clusterID: "8a8c14c8-f022-48bd-96f8-892cddb2dc43"  # Your Ceph fsid
  fsName: cephfs  # Your CephFS name
  pool: cephfs_data  # Your data pool name
  # ... rest of parameters
```

### 2.2 Manual Installation Steps

```bash
# 1. Create namespace
kubectl create namespace ceph-csi-cephfs

# 2. Apply ConfigMaps
kubectl apply -f ceph-csi-configmap.yml
kubectl apply -f cephfs-config.yml

# 3. Apply Secret (after updating with your credentials)
kubectl apply -f cephfs-secret.yml

# 4. Add Ceph CSI Helm repository
helm repo add ceph-csi https://ceph.github.io/csi-charts
helm repo update

# 5. Install CephFS CSI Driver
helm install ceph-csi-cephfs ceph-csi/ceph-csi-cephfs \
  --namespace ceph-csi-cephfs \
  --version 3.7.2 \
  --values values-cephfs.yml

# 6. Apply StorageClass
kubectl apply -f cephfs-storageclass.yml
```

### 2.3 Automated Installation

```bash
# Make the script executable
chmod +x install-cephfs.sh

# Run the installation script
./install-cephfs.sh
```

## Step 3: Verify Installation

### 3.1 Check CSI Driver Pods

```bash
# Check provisioner pods (should be 3 replicas, all Running)
kubectl get pods -n ceph-csi-cephfs -l component=provisioner

# Check nodeplugin pods (should be 1 per worker node, all Running)
kubectl get pods -n ceph-csi-cephfs -l component=nodeplugin

# Check all pods
kubectl get pods -n ceph-csi-cephfs
```

Expected output:
```
NAME                                        READY   STATUS    RESTARTS   AGE
ceph-csi-cephfs-nodeplugin-xxxxx            3/3     Running   0          5m
ceph-csi-cephfs-nodeplugin-xxxxx            3/3     Running   0          5m
ceph-csi-cephfs-provisioner-xxxxxxx-xxxxx   7/7     Running   0          5m
ceph-csi-cephfs-provisioner-xxxxxxx-xxxxx   7/7     Running   0          5m
ceph-csi-cephfs-provisioner-xxxxxxx-xxxxx   7/7     Running   0          5m
```

### 3.2 Check StorageClass

```bash
kubectl get storageclass csi-cephfs-sc
```

Expected output:
```
NAME             PROVISIONER              RECLAIMPOLICY   VOLUMEBINDINGMODE   AGE
csi-cephfs-sc    cephfs.csi.ceph.com      Delete          Immediate           5m
```

### 3.3 Check Logs

```bash
# Provisioner logs
kubectl logs -n ceph-csi-cephfs -l component=provisioner -c csi-cephfsplugin --tail=50

# NodePlugin logs
kubectl logs -n ceph-csi-cephfs -l component=nodeplugin -c csi-cephfsplugin --tail=50
```

## Step 4: Test ReadWriteMany (RWX) Storage

### 4.1 Deploy Test Application

This test deploys:
- 1 PVC with ReadWriteMany access
- 1 Writer pod (writes to shared log)
- 2 Reader pods (read from same volume simultaneously)

```bash
kubectl apply -f test-rwx-pvc-and-pods.yaml
```

### 4.2 Verify PVC and Pods

```bash
# Check PVC status (should show "Bound")
kubectl get pvc cephfs-pvc

# Check pods (all should be "Running")
kubectl get pods -l app=cephfs-test

# Check PV was created
kubectl get pv
```

Expected output:
```
# PVC
NAME          STATUS   VOLUME                                     CAPACITY   ACCESS MODES
cephfs-pvc    Bound    pvc-xxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx     2Gi        RWX

# Pods
NAME               READY   STATUS    RESTARTS   AGE
cephfs-writer      1/1     Running   0          2m
cephfs-reader-1    1/1     Running   0          2m
cephfs-reader-2    1/1     Running   0          2m
```

### 4.3 Verify Shared Filesystem Works

```bash
# View writer logs (should be writing timestamps)
kubectl logs cephfs-writer

# View reader-1 logs (should be reading the shared log)
kubectl logs cephfs-reader-1

# View reader-2 logs (should be reading writer.txt)
kubectl logs cephfs-reader-2

# Exec into writer and check files
kubectl exec -it cephfs-writer -- ls -lh /mnt/cephfs/

# Exec into reader-1 and verify it can see files created by writer
kubectl exec -it cephfs-reader-1 -- cat /mnt/cephfs/writer.txt

# Verify all pods can access the same data
kubectl exec cephfs-writer -- sh -c "echo 'Test from writer' > /mnt/cephfs/test.txt"
kubectl exec cephfs-reader-1 -- cat /mnt/cephfs/test.txt
kubectl exec cephfs-reader-2 -- cat /mnt/cephfs/test.txt
```

All three pods should see the same file content, proving RWX works!

### 4.4 Test Concurrent Writes

```bash
# Write from multiple pods simultaneously
kubectl exec cephfs-writer -- sh -c "echo 'Writer: $(date)' >> /mnt/cephfs/concurrent.txt" &
kubectl exec cephfs-reader-1 -- sh -c "echo 'Reader-1: $(date)' >> /mnt/cephfs/concurrent.txt" &
kubectl exec cephfs-reader-2 -- sh -c "echo 'Reader-2: $(date)' >> /mnt/cephfs/concurrent.txt" &
wait

# Check the file
kubectl exec cephfs-writer -- cat /mnt/cephfs/concurrent.txt
```

You should see entries from all three pods!

## Step 5: Production Usage Examples

### Example 1: Shared Configuration Files

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: shared-config-pvc
  namespace: production
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 5Gi
  storageClassName: csi-cephfs-sc
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  namespace: production
spec:
  replicas: 5
  selector:
    matchLabels:
      app: web-app
  template:
    metadata:
      labels:
        app: web-app
    spec:
      containers:
      - name: app
        image: nginx:latest
        volumeMounts:
        - name: config
          mountPath: /etc/app/config
      volumes:
      - name: config
        persistentVolumeClaim:
          claimName: shared-config-pvc
```

### Example 2: Shared Media Storage

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: media-storage-pvc
  namespace: media
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 100Gi
  storageClassName: csi-cephfs-sc
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: media-processor
  namespace: media
spec:
  replicas: 3
  selector:
    matchLabels:
      app: media-processor
  template:
    metadata:
      labels:
        app: media-processor
    spec:
      containers:
      - name: processor
        image: media-processor:latest
        volumeMounts:
        - name: media
          mountPath: /media
      volumes:
      - name: media
        persistentVolumeClaim:
          claimName: media-storage-pvc
```

### Example 3: Shared Logs

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: shared-logs-pvc
  namespace: logging
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 50Gi
  storageClassName: csi-cephfs-sc
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: log-collector
  namespace: logging
spec:
  selector:
    matchLabels:
      app: log-collector
  template:
    metadata:
      labels:
        app: log-collector
    spec:
      containers:
      - name: collector
        image: fluentd:latest
        volumeMounts:
        - name: logs
          mountPath: /var/log/collected
      volumes:
      - name: logs
        persistentVolumeClaim:
          claimName: shared-logs-pvc
```

## Troubleshooting

### Problem 1: Provisioner Can't Connect to Ceph

**Symptom**: PVC stuck in "Pending" with error:
```
failed to provision volume: rpc error: code = Internal desc = failed to get connection
```

**Solution**:

1. **Check Ceph cluster health:**
   ```bash
   # On Ceph server
   ceph -s
   ceph fs status
   ceph mds stat
   ```

2. **Verify MDS is running:**
   ```bash
   ceph mds stat
   # Should show: cephfs:1 {0=mds.server01=up:active}
   ```

3. **Test credentials from Kubernetes:**
   ```bash
   kubectl exec -n ceph-csi-cephfs -it ceph-csi-cephfs-provisioner-xxxxx -c csi-cephfsplugin -- bash
   ceph fs ls --id=admin --keyring=/etc/ceph/keyring
   ```

4. **Update secret if needed:**
   ```bash
   kubectl delete secret csi-cephfs-secret -n ceph-csi-cephfs
   kubectl apply -f cephfs-secret.yml
   kubectl rollout restart deployment/ceph-csi-cephfs-provisioner -n ceph-csi-cephfs
   ```

### Problem 2: Pods Can't Mount CephFS Volume

**Symptom**: Pods stuck in "ContainerCreating" with mount errors.

**Solution**:

1. **Check nodeplugin pods:**
   ```bash
   kubectl get pods -n ceph-csi-cephfs -l component=nodeplugin
   kubectl logs -n ceph-csi-cephfs -l component=nodeplugin -c csi-cephfsplugin
   ```

2. **Check if ceph-fuse or kernel mount is available:**
   ```bash
   kubectl exec -n ceph-csi-cephfs ceph-csi-cephfs-nodeplugin-xxxxx -c csi-cephfsplugin -- which ceph-fuse
   ```

3. **Restart nodeplugins:**
   ```bash
   kubectl rollout restart daemonset/ceph-csi-cephfs-nodeplugin -n ceph-csi-cephfs
   ```

### Problem 3: Permission Denied on CephFS

**Symptom**: Pods can mount but can't write files.

**Solution**:

1. **Check CephFS permissions:**
   ```bash
   # On Ceph server
   ceph fs authorize cephfs client.k8sfs / rw
   ```

2. **Check pod security context:**
   ```yaml
   securityContext:
     fsGroup: 1000
     runAsUser: 1000
   ```

3. **Check CephFS user permissions:**
   ```bash
   ceph auth get client.k8sfs
   # Should have: mds 'allow rw'
   ```

### Problem 4: MDS Unavailable

**Symptom**: Error: `no mds server available`

**Solution**:

1. **Check MDS status:**
   ```bash
   ceph mds stat
   ceph fs status
   ```

2. **Restart MDS if needed:**
   ```bash
   # On Ceph server
   systemctl restart ceph-mds@$(hostname -s)
   ```

3. **Check MDS logs:**
   ```bash
   journalctl -u ceph-mds@$(hostname -s) -f
   ```

## Performance Tuning

### For Better Performance

```yaml
# In cephfs-storageclass.yml, add mount options:
mountOptions:
  - debug  # Remove in production
  - readdir_max_entries=8192
  - readdir_max_bytes=1048576
```

### Monitoring CephFS Performance

```bash
# On Ceph server
ceph fs perf stats

# Check client connections
ceph tell mds.* client ls

# Monitor MDS performance
ceph daemon mds.$(hostname -s) perf dump
```

## Cleanup

### Remove Test Resources

```bash
kubectl delete -f test-rwx-pvc-and-pods.yaml
```

### Uninstall CephFS CSI Driver

```bash
# Delete StorageClass
kubectl delete -f cephfs-storageclass.yml

# Uninstall Helm release
helm uninstall ceph-csi-cephfs -n ceph-csi-cephfs

# Delete namespace (optional)
kubectl delete namespace ceph-csi-cephfs
```

## Important Notes

1. **ReadWriteMany (RWX)**: CephFS supports multiple pods reading and writing simultaneously. This is the key advantage over RBD.

2. **Performance**: CephFS has slightly lower performance than RBD for single-client workloads, but excels when multiple clients need shared access.

3. **Use Cases**:
   - ✅ Shared configuration files
   - ✅ Media storage accessed by multiple services
   - ✅ Shared logs or cache
   - ❌ High-IOPS databases (use RBD instead)

4. **MDS Requirement**: CephFS requires at least one active MDS (Metadata Server). For high availability, run multiple MDS instances.

5. **Credentials**: Like RBD, we use admin credentials due to go-ceph compatibility issues with Ceph Squid.

## Verification Checklist

- [ ] Ceph cluster is healthy: `ceph -s`
- [ ] CephFS filesystem exists: `ceph fs ls`
- [ ] MDS is active: `ceph mds stat`
- [ ] Data pool exists: `ceph osd pool ls | grep cephfs_data`
- [ ] Ceph authentication works: `ceph fs ls --id=admin`
- [ ] CSI provisioner pods running: `kubectl get pods -n ceph-csi-cephfs -l component=provisioner`
- [ ] CSI nodeplugin pods running: `kubectl get pods -n ceph-csi-cephfs -l component=nodeplugin`
- [ ] StorageClass exists: `kubectl get storageclass csi-cephfs-sc`
- [ ] Test PVC provisions successfully: `kubectl get pvc cephfs-pvc`
- [ ] Multiple pods can mount same volume: `kubectl get pods -l app=cephfs-test`
- [ ] Pods can read/write shared data: Verify test logs

## References

- [Ceph CSI CephFS Documentation](https://github.com/ceph/ceph-csi/blob/devel/docs/deploy-cephfs.md)
- [CephFS Documentation](https://docs.ceph.com/en/latest/cephfs/)
- [Kubernetes Volume Types](https://kubernetes.io/docs/concepts/storage/volumes/)

---

**Last Updated**: 2025-10-09
**Tested With**:
- Kubernetes: v1.30.14
- Ceph: Squid (v19)
- ceph-csi: v3.7.2
- Ubuntu: 24.04 LTS (Kernel 6.8.0-85)
