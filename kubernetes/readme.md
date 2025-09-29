
# Kubernetes Cluster Setup

This project provides automated Kubernetes cluster setup with parallel execution capabilities.

## Directory Structure
kubernetes/
├── inventory/
│   └── inventory.yml
├── playbooks/
│   ├── kubernetes-setup.yml
│   ├── cluster-control.yml
│   ├── node-management.yml
│   └── pre-flight-checks.yml
├── scripts/
│   ├── k8s/
│   │   ├── setup_k8s.sh
│   │   ├── utils.sh
│   │   ├── run_step.sh
│   │   └── cluster_status.sh
│   └── user-management/
│       └── create_kubeadmin.sh
├── templates/
│   └── kubeconfig.j2
├── group_vars/
│   ├── all.yml
│   └── kubernetes.yml
└── README.md

## Quick Start

### 1. Pre-flight Checks
```bash
# Run before cluster setup to verify prerequisites
ansible-playbook -i inventory/inventory.yml playbooks/pre-flight-checks.yml
```
### 2. Setup Kubernetes Cluster
```bash
# Full cluster setup (parallel execution where possible)
ansible-playbook -i inventory/inventory.yml playbooks/kubernetes-setup.yml

# Check cluster status
ssh kubeadmin@10.0.1.0
kubectl get nodes
kubectl get pods -A
```

### 3. Cluster Control
```bash
# Start cluster
ansible-playbook -i inventory/inventory.yml playbooks/cluster-control.yml -e cluster_action=start

# Stop cluster
ansible-playbook -i inventory/inventory.yml playbooks/cluster-control.yml -e cluster_action=stop

# Check status
ansible-playbook -i inventory/inventory.yml playbooks/cluster-control.yml -e cluster_action=status

# Reset cluster (DANGER - removes all data)
ansible-playbook -i inventory/inventory.yml playbooks/cluster-control.yml -e cluster_action=reset
```

### 4. Node Management

```bash
# List current nodes
ansible-playbook -i inventory/inventory.yml playbooks/node-management.yml

# Add new worker node
ansible-playbook -i inventory/inventory.yml playbooks/node-management.yml \
  -e node_action=add -e node_name=new_worker_hostname

# Remove worker node
ansible-playbook -i inventory/inventory.yml playbooks/node-management.yml \
  -e node_action=remove -e node_name=worker_to_remove
```

## Features
- ✅ **Parallel Execution**: System prep, Docker, and K8s installation run in parallel
- ✅ **User Management**: Creates dedicated `kubeadmin` user with SSH access
- ✅ **State Tracking**: Resumes from failed steps
- ✅ **Comprehensive Logging**: Detailed logs for troubleshooting
- ✅ **Cluster Control**: Start, stop, status, and reset operations
- ✅ **Node Management**: Add and remove nodes dynamically
- ✅ **Health Checks**: Pre-flight and post-installation verification
- ✅ **Error Recovery**: Retry mechanisms and rollback capabilities

## Configuration
### Cluster Nodes
Current cluster configuration (5 nodes):
- **Master**: ub2404vm01srv01 (10.0.1.1)
- **Workers**:
    - ub2404vm02srv01 (10.0.1.2)
    - ub2404vm03srv01 (10.0.1.3)
    - ub2404vm04srv01 (10.0.1.4)
    - ub2404vm05srv01 (10.0.1.5)

### Access
- **Original User**: anandy (initial access)
- **K8s Admin User**: kubeadmin (cluster operations)
- **SSH Key**: /Users/anandy/.ssh/id_rsa

## Troubleshooting
### View Logs
``` bash
# On each node
ssh kubeadmin@<node-ip>
tail -f /home/kubeadmin/k8s-setup-logs/<hostname>-setup.log
```
### Manual Cluster Status
``` bash
ssh kubeadmin@10.0.1.1
/home/kubeadmin/k8s-scripts/cluster_status.sh
```
### Reset and Retry
``` bash
# Reset cluster
ansible-playbook -i inventory/inventory.yml playbooks/cluster-control.yml -e cluster_action=reset

# Setup again
ansible-playbook -i inventory/inventory.yml playbooks/kubernetes-setup.yml
```
## Advanced Usage
### Custom Kubernetes Version
``` bash
ansible-playbook -i inventory/inventory.yml playbooks/kubernetes-setup.yml \
  -e kubernetes_version="1.29.0-1.1"
```
### Different CNI Plugin
Edit : `group_vars/kubernetes.yml`
``` yaml
cni_plugin: calico  # or weave, cilium
```
## Execution Flow
1. **Pre-flight Checks** - Verify system requirements
2. **User Setup** - Create kubeadmin user with SSH access
3. **Parallel Preparation** - Copy scripts and create directories
4. **Parallel System Prep** - Update systems, configure kernel modules
5. **Parallel Docker Install** - Install and configure Docker/containerd
6. **Parallel K8s Install** - Install kubelet, kubeadm, kubectl
7. **Parallel System Config** - Configure firewall, services
8. **Serial Master Init** - Initialize Kubernetes master
9. **Parallel Worker Join** - Join workers to cluster
10. **CNI Installation** - Install Flannel network plugin
11. **Verification** - Verify cluster health and functionality

## Security Notes
- All nodes use SSH key authentication
- `kubeadmin` user has sudo access for K8s operations
- Firewall rules are configured automatically
- TLS encryption enabled for all cluster communication
- Regular security updates applied during setup

## Common Commands
``` bash
# Quick cluster status
ssh kubeadmin@10.0.1.1 'kubectl get nodes -o wide'

# Deploy test application
ssh kubeadmin@10.0.1.1 'kubectl create deployment nginx --image=nginx'
ssh kubeadmin@10.0.1.1 'kubectl expose deployment nginx --port=80 --type=NodePort'

# Scale application
ssh kubeadmin@10.0.1.1 'kubectl scale deployment nginx --replicas=3'

# View cluster events
ssh kubeadmin@10.0.1.1 'kubectl get events --sort-by=.metadata.creationTimestamp'
```
``` 


This provides the complete directory structure with exact file mappings and includes all the missing components like:
- Pre-flight checks playbook
- Kubeconfig template
- Complete node management functionality
- Proper user management setup
- Comprehensive error handling and logging
- State tracking and recovery mechanisms
```
