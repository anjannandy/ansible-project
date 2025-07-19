#!/bin/bash
set -e

echo "🚀 Deploying alternative cAdvisor with full container runtime support..."

kubectl delete daemonset cadvisor -n kube-system --ignore-not-found=true
sleep 15

kubectl apply -f - << 'EOF'
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: cadvisor
  namespace: kube-system
  labels:
    app: cadvisor
spec:
  selector:
    matchLabels:
      app: cadvisor
  template:
    metadata:
      labels:
        app: cadvisor
    spec:
      hostNetwork: true
      hostPID: true
      automountServiceAccountToken: false  # Disable service account token mounting
      tolerations:
      - effect: NoSchedule
        operator: Exists
      - key: node.kubernetes.io/not-ready
        operator: Exists
        effect: NoExecute
      serviceAccountName: cadvisor
      containers:
      - name: cadvisor
        image: gcr.io/cadvisor/cadvisor:v0.46.0  # Using slightly older version
        ports:
        - containerPort: 8080
          hostPort: 8080
          name: http
          protocol: TCP
        resources:
          requests:
            memory: 200Mi
            cpu: 150m
          limits:
            memory: 400Mi
            cpu: 300m
        securityContext:
          privileged: true
          runAsUser: 0
        volumeMounts:
        - name: rootfs
          mountPath: /rootfs
          readOnly: true
        - name: var-run
          mountPath: /var/run
          readOnly: true
        - name: sys
          mountPath: /sys
          readOnly: true
        - name: docker
          mountPath: /var/lib/docker
          readOnly: true
        - name: dev-disk
          mountPath: /dev/disk
          readOnly: true
        - name: containerd
          mountPath: /run/containerd
          readOnly: true
        - name: proc
          mountPath: /host/proc
          readOnly: true
        args:
        - --housekeeping_interval=30s
        - --max_housekeeping_interval=60s
        - --event_storage_event_limit=default=0
        - --event_storage_age_limit=default=0
        - --disable_metrics=percpu,sched,tcp,udp,advtcp,hugetlb
        - --docker_only=false
        - --containerd=/run/containerd/containerd.sock
        - --allow_dynamic_housekeeping=false
        - --store_container_labels=false
        - --raw_cgroup_prefix_whitelist=/kubepods.slice,/kubepods
        - --v=1
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
            scheme: HTTP
          initialDelaySeconds: 60
          periodSeconds: 30
          timeoutSeconds: 10
          failureThreshold: 5
      volumes:
      - name: rootfs
        hostPath:
          path: /
      - name: var-run
        hostPath:
          path: /var/run
      - name: sys
        hostPath:
          path: /sys
      - name: docker
        hostPath:
          path: /var/lib/docker
      - name: dev-disk
        hostPath:
          path: /dev/disk
      - name: containerd
        hostPath:
          path: /run/containerd
      - name: proc
        hostPath:
          path: /proc
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cadvisor
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cadvisor
rules:
- apiGroups: [""]
  resources: ["nodes", "nodes/stats", "nodes/metrics", "pods"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cadvisor
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cadvisor
subjects:
- kind: ServiceAccount
  name: cadvisor
  namespace: kube-system
EOF

echo "✅ Alternative cAdvisor deployed!"
sleep 45
kubectl get pods -n kube-system -l app=cadvisor -o wide