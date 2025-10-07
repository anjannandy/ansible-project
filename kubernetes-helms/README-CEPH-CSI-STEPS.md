Ceph CSI debug & re-deploy notes

Purpose
- Record the troubleshooting and full re-deploy steps performed to get Ceph-CSI provisioning working with the Ceph cluster and Kubernetes cluster.

Environment (relevant hosts)
- Ceph monitor(s): 10.0.0.4, 10.0.0.5, 10.0.0.6 (clusterID: 8a8c14c8-f022-48bd-96f8-892cddb2dc43)
- Kubernetes master: 10.0.1.0
- Kubernetes workers: 10.0.1.1..10.0.1.4

High-level outcome
- Ceph CSI node DaemonSet and provisioner Deployment deployed and running on all workers.
- StorageClass csi-ceph-rbd created.
- PVCs provision successfully on Ceph (RBD images appear in pool 'kube').
- Test pod mounts PVC and can read/write.

Key actions performed (ordered)
1) Verified Ceph health and pools on Ceph admin (server01):
   - ceph -s
   - ceph osd pool ls detail
   - Confirmed pool 'kube' exists and application 'rbd' enabled.

2) Created CephX user key (client.k8s) or used existing key and recorded it:
   - ceph auth get client.k8s
   - Copied raw key value for Kubernetes secret.

3) (If missing) Create the Ceph pool and CephX credentials used by Kubernetes
   - Create pool (example name "kube") and enable RBD application:
     ceph osd pool create kube 128
     ceph osd pool application enable kube rbd
   - Create CephX user (client.k8s) with access to the pool and get its key:
     ceph auth get-or-create client.k8s mon 'profile rbd' \
       osd 'profile rbd pool=kube' mgr 'profile rbd'
     ceph auth get-key client.k8s   # copy the raw key output for the k8s secret
   - Important: replace pool name and capabilities to match your environment. Ensure the user has 'osd' caps that allow read/write on the target pool.

4) Created Kubernetes secret in kube-system with Ceph credentials:
   kubectl -n kube-system create secret generic csi-ceph-secret \
     --from-literal=userID=k8s \
     --from-literal=userKey='<CEPH_KEY>' --dry-run=client -o yaml | kubectl apply -f -

5) Deployed config maps and DaemonSet/Provisioner manifests from kubernetes-helms/:
   - ceph-csi-configmap.yaml (monitors & clusterID)
   - ceph-config-configmap.yaml (optional ceph.conf)
   - ceph-csi-encryption-kms-configmap.yaml (empty by default)
   - csi-rbdplugin.yaml (DaemonSet)
   - csi-rbdplugin-provisioner.yaml (Deployment)
   - csi-ceph-rbd-storageclass.yaml (StorageClass)

6) Fixed permission/serviceaccount issues:
   - Created serviceaccount kube-system/csi-rbdplugin (was missing)
   - Restarted daemonset (kubectl rollout restart) as needed.

7) Troubleshooting notable errors and fixes
   - CrashLoopBackOff with error "modprobe: Exec format error":
     * This indicated the container attempted to run a host modprobe that failed. Verified kernel modules exist and loaded rbd on each worker:
       sudo modprobe -v rbd
     * Avoided bind-mounting host /lib64 into containers (that overwrote container libc and caused 'exec /usr/local/bin/cephcsi: no such file or directory'). Any temporary /lib64 bind was removed.
   - "configmap ... not found" for ceph-csi-config / ceph-csi-encryption-kms-config:
     * Created / applied these ConfigMaps so the DaemonSet init container could copy files.
   - "provided secret is empty" when provisioning:
     * Ensured kube-system/csi-ceph-secret contains userID and userKey; recreated secret with correct key.
   - MountDevice / MountVolume.MountDevice failures due to missing node-stage secret or driver registration:
     * Recreated secret and ensured csi node pods register plugin at /var/lib/kubelet/plugins.

8) Validation steps performed
   - kubectl -n kube-system get pods -l app=csi-rbdplugin -o wide  # all node pods Running
   - kubectl -n kube-system get pods -l app=csi-rbdplugin-provisioner -o wide  # provisioners Running
   - kubectl apply -f my-pvc-and-pod.yaml  # example PVC + pod
   - kubectl get pvc/my-pvc -o wide  # status Bound
   - kubectl exec -it app-using-pvc -- cat /mnt/data/hello.txt  # verify read/write on mounted PVC
   - On Ceph: rbd ls -p kube  and rbd info -p kube <image>

Cleanup commands (if you want to remove everything)
- kubectl -n default delete -f kubernetes-helms/my-pvc-and-pod.yaml
- kubectl delete storageclass csi-ceph-rbd
- kubectl -n kube-system delete -f kubernetes-helms/csi-rbdplugin-provisioner.yaml
- kubectl -n kube-system delete -f kubernetes-helms/csi-rbdplugin.yaml
- kubectl -n kube-system delete configmap ceph-csi-config ceph-csi-encryption-kms-config ceph-config
- kubectl -n kube-system delete secret csi-ceph-secret
- Delete PVs and RBD images manually as needed (rbd rm)

Notes and recommendations
- Keep the Ceph monitors list in ceph-csi-configmap accurate (only real MON IPs/ports).
- Do not bind-mount host /lib or /lib64 into containers — it can break container runtime by replacing container libraries.
- Ensure the CephX user (client.k8s) caps include correct pool access (osd 'profile rbd pool=kube').
- Prefer using the official release manifests for the ceph-csi version that matches your Ceph and kernel features.

If you want, I can now:
- Re-run any specific validation command and paste output.
- Generate a minimal set of manifests (secret/configmap/storageclass) with placeholders filled for your environment.
