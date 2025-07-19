#!/bin/bash

# Script for cluster status verification
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Export required environment variables
export KUBECONFIG="${KUBECONFIG:-/home/ubuntu/.kube/config}"

echo "=== FINAL CLUSTER STATUS ==="
echo "Timestamp: $(date)"
echo ""
echo "=== Nodes ==="
kubectl get nodes -o wide
echo ""
echo "=== All Pods ==="
kubectl get pods -A -o wide
echo ""
echo "=== Cluster Info ==="
kubectl cluster-info
echo ""
echo "=== Node Conditions ==="
kubectl get nodes -o json | jq -r '.items[] | "\(.metadata.name): \(.status.conditions[] | select(.type=="Ready") | .status)"'
