#!/bin/bash

# Kubernetes Cluster Status Checker
set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source utilities
source "${SCRIPT_DIR}/utils.sh"

# Check if kubectl is available
if ! command -v kubectl >/dev/null 2>&1; then
    echo "kubectl is not installed or not in PATH"
    exit 1
fi

# Check if kubeconfig is available
K8S_ADMIN_USER="${K8S_ADMIN_USER:-kubeadmin}"
KUBECONFIG="${KUBECONFIG:-/home/$K8S_ADMIN_USER/.kube/config}"
export KUBECONFIG

if [[ ! -f "$KUBECONFIG" ]]; then
    echo "kubeconfig not found at $KUBECONFIG"
    exit 1
fi

echo "================================================================"
echo "           KUBERNETES CLUSTER STATUS REPORT"
echo "================================================================"
echo ""

# Cluster info
echo -e "🔍 CLUSTER INFORMATION"
echo "----------------------------------------------------------------"
if kubectl cluster-info >/dev/null 2>&1; then
    kubectl cluster-info
    echo ""

    # Get cluster version
    echo "Kubernetes Version:"
    kubectl version --short 2>/dev/null || kubectl version --client --output=yaml | grep gitVersion
    echo ""
else
    echo "❌ Cannot connect to cluster"
    exit 1
fi

# Node status
echo -e "🖥️  NODE STATUS"
echo "----------------------------------------------------------------"
kubectl get nodes -o wide
echo ""

# Count nodes by status
ready_nodes=$(kubectl get nodes --no-headers | grep -c " Ready " || echo "0")
total_nodes=$(kubectl get nodes --no-headers | wc -l)
echo "Ready Nodes: $ready_nodes/$total_nodes"
echo ""

# System pods status
echo -e "🚀 SYSTEM PODS STATUS"
echo "----------------------------------------------------------------"
echo "Kube-system pods:"
kubectl get pods -n kube-system -o wide
echo ""

echo "CNI pods (if using Flannel):"
kubectl get pods -n kube-flannel -o wide 2>/dev/null || echo "No Flannel pods found"
echo ""

# Pod status summary
echo -e "📊 POD SUMMARY"
echo "----------------------------------------------------------------"
running_pods=$(kubectl get pods -A --no-headers | grep -c " Running " || echo "0")
pending_pods=$(kubectl get pods -A --no-headers | grep -c " Pending " || echo "0")
failed_pods=$(kubectl get pods -A --no-headers | grep -c " Failed\|Error\|CrashLoopBackOff " || echo "0")
total_pods=$(kubectl get pods -A --no-headers | wc -l)

echo "Total Pods: $total_pods"
echo "Running: $running_pods"
echo "Pending: $pending_pods"
echo "Failed/Error: $failed_pods"
echo ""

# Services
echo -e "🌐 SERVICES"
echo "----------------------------------------------------------------"
kubectl get services -A
echo ""

# Namespaces
echo -e "📁 NAMESPACES"
echo "----------------------------------------------------------------"
kubectl get namespaces
echo ""

# Health check
echo -e "🏥 CLUSTER HEALTH CHECK"
echo "----------------------------------------------------------------"

health_issues=0

# Check if all nodes are ready
if [[ $ready_nodes -ne $total_nodes ]]; then
    echo "❌ Not all nodes are ready ($ready_nodes/$total_nodes)"
    health_issues=$((health_issues + 1))
else
    echo "✅ All nodes are ready ($ready_nodes/$total_nodes)"
fi

# Check if essential system pods are running
coredns_pods=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers | grep -c " Running " || echo "0")
if [[ $coredns_pods -lt 1 ]]; then
    echo "❌ CoreDNS pods not running properly"
    health_issues=$((health_issues + 1))
else
    echo "✅ CoreDNS is running ($coredns_pods pods)"
fi

echo ""
echo "================================================================"
if [[ $health_issues -eq 0 ]]; then
    echo -e "🎉 CLUSTER STATUS: HEALTHY"
else
    echo -e "⚠️  CLUSTER STATUS: $health_issues ISSUES FOUND"
fi
echo "================================================================"

echo ""
echo "Report generated at: $(date)"
echo "================================================================"