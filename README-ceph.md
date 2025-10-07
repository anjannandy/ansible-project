# Kubernetes + Ceph CSI Integration (Step-by-Step)

This guide will help you set up dynamic PVC provisioning in Kubernetes using Ceph CSI, starting from a clean slate. All changes and files will be created inside the `kubernetes-helms` directory.

---

## 1. Prerequisites
- Healthy Ceph cluster (FSID, pool, user/key ready)
- Kubernetes cluster (v1.30 or compatible)
- All Kubernetes nodes can reach Ceph monitors

---

## 2. Clean Up Old CSI Resources
All previous Ceph CSI resources have been removed from your cluster.

---

## 3. Deploy Ceph CSI Driver
- Download the latest Ceph CSI manifests (recommended v3.10.0):
  ```sh
  curl -O https://raw.githubusercontent.com/ceph/ceph-csi/v3.10.0/deploy/rbd/kubernetes/csi-rbdplugin.yaml
  curl -O https://raw.githubusercontent.com/ceph/ceph-csi/v3.10.0/deploy/rbd/kubernetes/csi-rbdplugin-provisioner.yaml
  ```
- Edit both files to set all resources to the `kube-system` namespace.
- Apply the manifests:
  ```sh
  kubectl apply -f csi-rbdplugin.yaml -n kube-system
  kubectl apply -f csi-rbdplugin-provisioner.yaml -n kube-system
  ```

---

## 4. Create Ceph CSI Secret
You can apply the provided Secret manifest (edit it to put your real credentials):

```sh
# Edit the file to set stringData.userID and stringData.userKey appropriately
$EDITOR kubernetes-helms/csi-ceph-secret.yaml
kubectl apply -f kubernetes-helms/csi-ceph-secret.yaml
```

Alternatively, create it with kubectl from literals:
```sh
kubectl create secret generic csi-ceph-secret \
  --from-literal=userID=<cephx-user> \
  --from-literal=userKey=<cephx-key> \
  --namespace=kube-system
```

---

## 5. Create Required ConfigMaps
You can apply the provided manifests directly (recommended):

```sh
kubectl apply -f kubernetes-helms/ceph-config-configmap.yaml
kubectl apply -f kubernetes-helms/ceph-csi-configmap.yaml
kubectl apply -f kubernetes-helms/ceph-csi-encryption-kms-configmap.yaml
```

Alternatively, you can create them from files manually:
```sh
# Copy your ceph.conf from a Ceph node to this directory first
# Example: scp user@ceph-node:/etc/ceph/ceph.conf ./kubernetes-helms/ceph.conf
kubectl create configmap ceph-config --from-file=ceph.conf=./kubernetes-helms/ceph.conf -n kube-system

# Create a minimal CSI config file (config.json) in this directory
# Example content:
# [
#   {
#     "clusterID": "<FSID>",
#     "monitors": ["10.0.0.4:6789", "10.0.0.5:6789", "10.0.0.6:6789"]
#   }
# ]
# Save as ./kubernetes-helms/config.json
kubectl create configmap ceph-csi-config --from-file=config.json=./kubernetes-helms/config.json -n kube-system

# If not using encryption, create an empty configmap
kubectl create configmap ceph-csi-encryption-kms-config -n kube-system
```

---

## 6. Create CSI StorageClass
- Edit and use the following (replace `<FSID>` with your Ceph FSID):

  `csi-ceph-rbd-storageclass.yaml`
  ```yaml
  apiVersion: storage.k8s.io/v1
  kind: StorageClass
  metadata:
    name: csi-ceph-rbd
  provisioner: rbd.csi.ceph.com
  parameters:
    clusterID: <FSID>
    pool: kube
    imageFeatures: layering
    csi.storage.k8s.io/provisioner-secret-name: csi-ceph-secret
    csi.storage.k8s.io/provisioner-secret-namespace: kube-system
    csi.storage.k8s.io/node-stage-secret-name: csi-ceph-secret
    csi.storage.k8s.io/node-stage-secret-namespace: kube-system
    fsType: ext4
  reclaimPolicy: Delete
  allowVolumeExpansion: true
  ```
  Apply:
  ```sh
  kubectl apply -f kubernetes-helms/csi-ceph-rbd-storageclass.yaml

  # Troubleshooting:
  # If CSI pods are stuck in ContainerCreating, check for missing ConfigMaps (ceph-config, ceph-csi-config, ceph-csi-encryption-kms-config)
  # and ServiceAccounts (rbd-csi-provisioner, csi-rbdplugin) in the kube-system namespace.
  # Use:
  #   kubectl get configmap -n kube-system
  #   kubectl get serviceaccount -n kube-system
  #   kubectl describe pod <pod-name> -n kube-system
  ```

---

## 7. Create PVC Example
- Example PVC manifest:

  `csi-ceph-pvc.yaml`
  ```yaml
  apiVersion: v1
  kind: PersistentVolumeClaim
  metadata:
    name: csi-ceph-pvc
  spec:
    storageClassName: csi-ceph-rbd
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 1Gi
  ```
  Apply:
  ```sh
  kubectl apply -f kubernetes-helms/csi-ceph-pvc.yaml
  ```

---

## 8. Verify
- Check CSI pods:
  ```sh
  kubectl get pods -n kube-system | grep csi
  ```
- Check PVC status:
  ```sh
  kubectl get pvc
  kubectl describe pvc csi-ceph-pvc
  ```

---

## 9. Troubleshooting
- If CSI pods are stuck in ContainerCreating, check for missing ConfigMaps or image pull errors.
- If PVC is Pending, check pod logs and events for errors.
- Ensure all resources are in the `kube-system` namespace.
- Error "rados: ret=-13, Permission denied" during provisioning:
  - This means the CephX user in csi-ceph-secret is missing or lacks permissions. Verify the user/key and caps.
  - Example to create a user with required caps (run on a Ceph monitor node as a user with admin rights):
    ```sh
    # Replace <POOL> with your pool (e.g., kube) and <USER> with a name (e.g., k8s)
    ceph auth get-or-create client.<USER> \
      mon 'allow r, allow command "osd blacklist", allow command "config-key get", allow command "config-key put"' \
      osd 'allow rwx pool=<POOL>'

    # Show key:
    ceph auth get-key client.<USER>
    ```
  - Update kubernetes-helms/csi-ceph-secret.yaml stringData.userID to <USER> and stringData.userKey to the key printed above.
  - Ensure the StorageClass pool parameter matches the pool granted in the caps.

---

## References
- [Ceph CSI Documentation](https://github.com/ceph/ceph-csi)
- [Kubernetes StorageClass Docs](https://kubernetes.io/docs/concepts/storage/storage-classes/)

---

**Start with these steps and follow the order for a clean, working Ceph CSI setup.**
