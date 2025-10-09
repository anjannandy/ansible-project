#!/bin/bash
# CephFS CSI Driver Installation Script
# This script installs and configures CephFS storage for Kubernetes

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}CephFS CSI Driver Installation${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""

# Configuration variables
NAMESPACE="ceph-csi-cephfs"
CEPH_CLUSTER_ID="8a8c14c8-f022-48bd-96f8-892cddb2dc43"
CEPHFS_NAME="cephfs"

# Step 1: Create namespace
echo -e "${YELLOW}Step 1: Creating namespace ${NAMESPACE}...${NC}"
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}✓ Namespace created${NC}"
echo ""

# Step 2: Apply ConfigMaps
echo -e "${YELLOW}Step 2: Creating ConfigMaps...${NC}"
kubectl apply -f ceph-csi-configmap.yml
kubectl apply -f cephfs-config.yml
echo -e "${GREEN}✓ ConfigMaps created${NC}"
echo ""

# Step 3: Apply Secret
echo -e "${YELLOW}Step 3: Creating Secret...${NC}"
echo -e "${RED}WARNING: Update cephfs-secret.yml with your actual Ceph credentials before proceeding!${NC}"
read -p "Have you updated the secret with correct credentials? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}Please update cephfs-secret.yml and run this script again.${NC}"
    exit 1
fi

kubectl apply -f cephfs-secret.yml
echo -e "${GREEN}✓ Secret created${NC}"
echo ""

# Step 4: Add Ceph CSI Helm repo
echo -e "${YELLOW}Step 4: Adding Ceph CSI Helm repository...${NC}"
helm repo add ceph-csi https://ceph.github.io/csi-charts 2>/dev/null || true
helm repo update
echo -e "${GREEN}✓ Helm repo added${NC}"
echo ""

# Step 5: Install CephFS CSI Driver
echo -e "${YELLOW}Step 5: Installing CephFS CSI Driver...${NC}"
helm upgrade --install ceph-csi-cephfs ceph-csi/ceph-csi-cephfs \
  --namespace ${NAMESPACE} \
  --version 3.7.2 \
  --values values-cephfs.yml \
  --wait \
  --timeout 10m

echo -e "${GREEN}✓ CephFS CSI Driver installed${NC}"
echo ""

# Step 6: Wait for pods to be ready
echo -e "${YELLOW}Step 6: Waiting for CSI pods to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app=ceph-csi-cephfs -n ${NAMESPACE} --timeout=300s
echo -e "${GREEN}✓ All CSI pods are ready${NC}"
echo ""

# Step 7: Create StorageClass
echo -e "${YELLOW}Step 7: Creating StorageClass...${NC}"
kubectl apply -f cephfs-storageclass.yml
echo -e "${GREEN}✓ StorageClass created${NC}"
echo ""

# Step 8: Verify installation
echo -e "${YELLOW}Step 8: Verifying installation...${NC}"
echo ""
echo "Provisioner Pods:"
kubectl get pods -n ${NAMESPACE} -l app=ceph-csi-cephfs,component=provisioner
echo ""
echo "NodePlugin Pods:"
kubectl get pods -n ${NAMESPACE} -l app=ceph-csi-cephfs,component=nodeplugin
echo ""
echo "StorageClass:"
kubectl get storageclass csi-cephfs-sc
echo ""

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Test the installation:"
echo "   kubectl apply -f test-rwx-pvc-and-pods.yaml"
echo ""
echo "2. Verify PVC is bound:"
echo "   kubectl get pvc cephfs-pvc"
echo ""
echo "3. Check pods are running:"
echo "   kubectl get pods -l app=cephfs-test"
echo ""
echo "4. View logs from reader pods:"
echo "   kubectl logs cephfs-reader-1"
echo ""
