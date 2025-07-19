#!/bin/bash
set -e

echo "Deploying cAdvisor with fixed configuration..."

# Remove any existing cAdvisor deployment
kubectl delete daemonset cadvisor -n kube-system --ignore-not-found=true

# Wait for cleanup
sleep 10

kubectl apply -f - << 'EOF'
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: cadvisor
  namespace: kube-system
  labels:
    app: cadvisor
    version: v0.47.0
spec:
  selector:
    matchLabels:
      app: cadvisor
  template:
    metadata:
      labels:
        app: cadvisor
        version: v0.47.0
    spec:
      # Use host network for easier access
      hostNetwork: true
      hostPID: true
      tolerations:
      - key: node-role.kubernetes.io/master
        effect: NoSchedule
      - key: node-role.kubernetes.io/control-plane
        effect: NoSchedule
      containers:
      - name: cadvisor
        image: gcr.io/cadvisor/cadvisor:v0.47.0
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
            memory: 300Mi
            cpu: 300m
        securityContext:
          privileged: true
          runAsNonRoot: false
          runAsUser: 0
        volumeMounts:
        - name: rootfs
          mountPath: /rootfs
          readOnly: true
        - name: var-run
          mountPath: /var/run
          readOnly: false
        - name: sys
          mountPath: /sys
          readOnly: true
        - name: docker
          mountPath: /var/lib/docker
          readOnly: true
        - name: dev-disk
          mountPath: /dev/disk
          readOnly: true
        - name: proc
          mountPath: /host/proc
          readOnly: true
        args:
        - --housekeeping_interval=10s
        - --max_housekeeping_interval=15s
        - --event_storage_event_limit=default=0
        - --event_storage_age_limit=default=0
        - --disable_metrics=percpu,sched,tcp,udp,advtcp,hugetlb,referenced_memory,cpu_topology,resctrl,cpuset,process,memory_numa
        - --docker_only=false
        - --store_container_labels=false
        - --whitelisted_container_labels=io.kubernetes.container.name,io.kubernetes.pod.name,io.kubernetes.pod.namespace
        - --v=2
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
            scheme: HTTP
          initialDelaySeconds: 30
          periodSeconds: 30
          timeoutSeconds: 5
        readinessProbe:
          httpGet:
            path: /healthz
            port: 8080
            scheme: HTTP
          initialDelaySeconds: 5
          periodSeconds: 10
          timeoutSeconds: 5
      automountServiceAccountToken: false
      volumes:
      - name: rootfs
        hostPath:
          path: /
          type: Directory
      - name: var-run
        hostPath:
          path: /var/run
          type: Directory
      - name: sys
        hostPath:
          path: /sys
          type: Directory
      - name: docker
        hostPath:
          path: /var/lib/docker
          type: DirectoryOrCreate
      - name: dev-disk
        hostPath:
          path: /dev/disk
          type: DirectoryOrCreate
      - name: proc
        hostPath:
          path: /proc
          type: Directory
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
EOF

echo "✅ cAdvisor deployed with fixed configuration!"

# Wait for pods to start
echo "⏳ Waiting for cAdvisor pods to start..."
sleep 30

# Check deployment status
echo "📊 Checking cAdvisor pod status..."
kubectl get pods -n kube-system -l app=cadvisor -o wide

# Wait a bit more for full startup
echo "⏳ Waiting for cAdvisor to fully initialize..."
sleep 30

echo ""
echo "🔍 Final status check..."
kubectl get pods -n kube-system -l app=cadvisor

echo ""
echo "📊 Testing cAdvisor endpoints:"
for node in $(kubectl get nodes --no-headers | awk '{print $1}'); do
    node_ip=$(kubectl get node $node -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
    echo "- $node ($node_ip): http://$node_ip:8080"
done

echo ""
echo "⚠️  If pods are still failing, check logs with:"
echo "kubectl logs -n kube-system -l app=cadvisor"