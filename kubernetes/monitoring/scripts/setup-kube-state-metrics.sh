#!/bin/bash
set -e

NAMESPACE="kube-system"
NODE_PORT="30080"

echo "Setting up kube-state-metrics..."

# Check kubectl access
if ! kubectl cluster-info &>/dev/null; then
    echo "❌ Cannot access Kubernetes cluster"
    exit 1
fi

# Apply manifests
echo "Deploying kube-state-metrics..."

kubectl apply -f - << 'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kube-state-metrics
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kube-state-metrics
rules:
- apiGroups: [""]
  resources: ["*"]
  verbs: ["list", "watch"]
- apiGroups: ["apps"]
  resources: ["*"]
  verbs: ["list", "watch"]
- apiGroups: ["batch"]
  resources: ["*"]
  verbs: ["list", "watch"]
- apiGroups: ["autoscaling"]
  resources: ["*"]
  verbs: ["list", "watch"]
- apiGroups: ["policy"]
  resources: ["*"]
  verbs: ["list", "watch"]
- apiGroups: ["storage.k8s.io"]
  resources: ["*"]
  verbs: ["list", "watch"]
- apiGroups: ["networking.k8s.io"]
  resources: ["*"]
  verbs: ["list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kube-state-metrics
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kube-state-metrics
subjects:
- kind: ServiceAccount
  name: kube-state-metrics
  namespace: kube-system
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kube-state-metrics
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kube-state-metrics
  template:
    metadata:
      labels:
        app: kube-state-metrics
    spec:
      serviceAccountName: kube-state-metrics
      containers:
      - name: kube-state-metrics
        image: registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.10.1
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: 10m
            memory: 32Mi
          limits:
            cpu: 100m
            memory: 150Mi
---
apiVersion: v1
kind: Service
metadata:
  name: kube-state-metrics
  namespace: kube-system
spec:
  type: NodePort
  ports:
  - port: 8080
    targetPort: 8080
    nodePort: 30080
  selector:
    app: kube-state-metrics
EOF

echo "Waiting for deployment..."
kubectl wait --for=condition=available --timeout=300s deployment/kube-state-metrics -n kube-system

NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "✅ kube-state-metrics deployed"
echo "📊 Endpoint: http://${NODE_IP}:${NODE_PORT}/metrics"