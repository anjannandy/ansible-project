#!/bin/bash

# Main Kubernetes setup script
# Exit on any error
set -e

# Parameters
NODE_ROLE="$1"
STATE_DIR="$2"
LOG_DIR="$3"
K8S_VERSION="$4"
POD_CIDR="$5"
MASTER_IP="$6"
KUBEADM_TIMEOUT="$7"
APT_TIMEOUT="$8"
MAX_RETRIES="$9"
MASTER_HOST="${10}"

# Validate parameters
if [[ $# -lt 10 ]]; then
    echo "Usage: $0 <role> <state_dir> <log_dir> <k8s_version> <pod_cidr> <master_ip> <kubeadm_timeout> <apt_timeout> <max_retries> <master_host>"
    exit 1
fi

# Set up logging
LOG_FILE="${LOG_DIR}/$(hostname)-setup.log"
mkdir -p "$LOG_DIR"

# Source utilities
SCRIPT_DIR="$(dirname "$0")"
if [[ -f "${SCRIPT_DIR}/utils.sh" ]]; then
    source "${SCRIPT_DIR}/utils.sh"
else
    echo "ERROR: utils.sh not found in ${SCRIPT_DIR}"
    exit 1
fi

# Initialize logging
init_logging

# Main execution
main() {
    log_info "Starting Kubernetes setup for ${NODE_ROLE} node"
    log_info "Parameters: Role=$NODE_ROLE, K8S_VERSION=$K8S_VERSION, POD_CIDR=$POD_CIDR, MASTER_IP=$MASTER_IP"
    
    # Validate environment
    if ! validate_environment; then
        log_error "Environment validation failed"
        exit 1
    fi
    
    # Step 1: System preparation
    if ! check_state "01_system_prep"; then
        log_info "=== Step 1: System Preparation ==="
        system_prep || exit 1
        mark_complete "01_system_prep"
    else
        log_info "Step 1: System Preparation - SKIPPED (already completed)"
    fi
    
    # Step 2: Docker installation
    if ! check_state "02_docker_install"; then
        log_info "=== Step 2: Docker Installation ==="
        install_docker || exit 1
        mark_complete "02_docker_install"
    else
        log_info "Step 2: Docker Installation - SKIPPED (already completed)"
    fi
    
    # Step 3: Kubernetes installation
    if ! check_state "03_k8s_install"; then
        log_info "=== Step 3: Kubernetes Installation ==="
        install_kubernetes || exit 1
        mark_complete "03_k8s_install"
    else
        log_info "Step 3: Kubernetes Installation - SKIPPED (already completed)"
    fi
    
    # Step 4: System configuration
    if ! check_state "04_system_config"; then
        log_info "=== Step 4: System Configuration ==="
        configure_system || exit 1
        mark_complete "04_system_config"
    else
        log_info "Step 4: System Configuration - SKIPPED (already completed)"
    fi
    
    # Step 5: Role-specific setup
    if [[ "$NODE_ROLE" == "master" ]]; then
        if ! check_state "05_master_init"; then
            log_info "=== Step 5: Master Initialization ==="
            initialize_master || exit 1
            mark_complete "05_master_init"
        else
            log_info "Step 5: Master Initialization - SKIPPED (already completed)"
        fi
        
        if ! check_state "06_cni_install"; then
            log_info "=== Step 6: CNI Installation ==="
            install_cni || exit 1
            mark_complete "06_cni_install"
        else
            log_info "Step 6: CNI Installation - SKIPPED (already completed)"
        fi
    else
        if ! check_state "05_worker_join"; then
            log_info "=== Step 5: Worker Join ==="
            join_worker || exit 1
            mark_complete "05_worker_join"
        else
            log_info "Step 5: Worker Join - SKIPPED (already completed)"
        fi
    fi
    
    # Final verification
    log_info "=== Final Verification ==="
    verify_installation
    
    log_success "Kubernetes setup completed successfully!"
    return 0
}

# System preparation
system_prep() {
    log_info "Killing conflicting processes..."
    sudo pkill -f "unattended-upgr" || true
    sudo pkill -f "apt-get" || true
    sudo pkill -f "dpkg" || true
    sleep 2
    
    log_info "Removing package locks..."
    sudo rm -f /var/lib/dpkg/lock*
    sudo rm -f /var/lib/apt/lists/lock
    sudo rm -f /var/cache/apt/archives/lock
    
    log_info "Configuring dpkg..."
    sudo dpkg --configure -a || true
    
    log_info "Updating package index..."
    retry_command "sudo apt-get update" "$MAX_RETRIES"
    
    log_info "Installing prerequisites..."
    retry_command "sudo apt-get install -y apt-transport-https ca-certificates curl gnupg" "$MAX_RETRIES"
    
    log_success "System preparation completed"
}

# Docker installation
install_docker() {
    log_info "Creating keyrings directory..."
    sudo mkdir -p /etc/apt/keyrings
    
    log_info "Adding Docker GPG key..."
    retry_command "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg --batch --yes" "$MAX_RETRIES"
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    
    log_info "Adding Docker repository..."
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    retry_command "sudo apt-get update" "$MAX_RETRIES"

    log_info "Installing Docker..."
    retry_command "sudo apt-get install -y docker-ce docker-ce-cli containerd.io" "$MAX_RETRIES"

    log_info "Configuring Docker daemon..."
    sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

    log_info "Configuring containerd..."
    sudo mkdir -p /etc/containerd
    sudo containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
    sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

    log_info "Restarting services..."
    sudo systemctl daemon-reload
    sudo systemctl enable docker containerd
    sudo systemctl restart containerd
    sudo systemctl restart docker

    # Wait for services to start
    wait_for_service "docker" 30 5
    wait_for_service "containerd" 30 5

    # Test containerd
    if sudo ctr version >/dev/null 2>&1; then
        log_success "Containerd is responding"
    else
        log_error "Containerd is not responding"
        return 1
    fi

    # Add user to docker group
    sudo usermod -aG docker ubuntu

    log_success "Docker installation completed"
}

# Kubernetes installation
install_kubernetes() {
    log_info "Adding Kubernetes GPG key..."
    retry_command "curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg --batch --yes" "$MAX_RETRIES"
    sudo chmod a+r /etc/apt/keyrings/kubernetes-apt-keyring.gpg

    log_info "Adding Kubernetes repository..."
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

    retry_command "sudo apt-get update" "$MAX_RETRIES"

    log_info "Installing Kubernetes components..."
    retry_command "sudo apt-get install -y kubelet=$K8S_VERSION kubeadm=$K8S_VERSION kubectl=$K8S_VERSION" "$MAX_RETRIES"

    log_info "Holding Kubernetes packages..."
    sudo apt-mark hold kubelet kubeadm kubectl

    log_info "Configuring kubelet..."
    echo 'KUBELET_EXTRA_ARGS=--cgroup-driver=systemd' | sudo tee /etc/default/kubelet
    sudo systemctl enable kubelet

    log_success "Kubernetes installation completed"
}

# System configuration
configure_system() {
    log_info "Loading kernel modules..."
    sudo modprobe overlay
    sudo modprobe br_netfilter

    cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

    log_info "Configuring sysctl..."
    cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

    sudo sysctl --system

    log_info "Disabling swap..."
    sudo swapoff -a
    sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
    sudo sed -i '/\/swap\.img/s/^/#/' /etc/fstab

    log_success "System configuration completed"
}

# Master initialization
initialize_master() {
    log_info "Checking for existing cluster..."
    if [[ -f /etc/kubernetes/admin.conf ]]; then
        log_info "Resetting existing cluster..."
        sudo kubeadm reset -f
        sudo rm -rf /etc/kubernetes/
        sudo rm -rf /var/lib/etcd/
        sudo rm -rf /etc/cni/net.d/
        sudo systemctl stop kubelet
        sudo systemctl stop docker
        sudo systemctl stop containerd
        sleep 2
        sudo systemctl start containerd
        sudo systemctl start docker
        sleep 3
    fi

    log_info "Creating kubeadm config..."
    cat > /tmp/kubeadm-config.yaml <<EOF
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v1.30.0
networking:
  podSubnet: $POD_CIDR
apiServer:
  advertiseAddress: $MASTER_IP
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: $MASTER_IP
  bindPort: 6443
EOF

    log_info "Initializing Kubernetes cluster (this may take several minutes)..."
    log_info "Command: sudo kubeadm init --config=/tmp/kubeadm-config.yaml"

    if sudo timeout "$KUBEADM_TIMEOUT" kubeadm init --config=/tmp/kubeadm-config.yaml --ignore-preflight-errors=all --v=2; then
        log_success "Cluster initialized successfully"
    else
        log_error "Cluster initialization failed"
        log_info "Checking kubelet status..."
        sudo systemctl status kubelet --no-pager -l
        log_info "Checking containerd status..."
        sudo systemctl status containerd --no-pager -l
        log_info "Checking kubelet logs..."
        sudo journalctl -xeu kubelet --no-pager -l | tail -50
        return 1
    fi

    log_info "Setting up kubeconfig..."
    mkdir -p /home/ubuntu/.kube
    sudo cp /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
    sudo chown ubuntu:ubuntu /home/ubuntu/.kube/config

    log_info "Generating join command..."
    sudo kubeadm token create --print-join-command > "$STATE_DIR/join-command.sh"
    chmod +x "$STATE_DIR/join-command.sh"

    log_info "Waiting for API server..."
    wait_for_api_server

    log_success "Master initialization completed"
}

# Worker join
join_worker() {
    log_info "Waiting for join command from master..."
    local join_file="/var/lib/k8s-setup-state/join-command.sh"
    local attempts=0

    while [[ $attempts -lt 30 ]]; do
        if ssh -o StrictHostKeyChecking=no ubuntu@"$MASTER_HOST" "test -f $join_file"; then
            log_success "Join command available"
            break
        fi
        log_info "Waiting for join command... ($((attempts + 1))/30)"
        sleep 10
        ((attempts++))
    done

    if [[ $attempts -eq 30 ]]; then
        log_error "Join command not available after 5 minutes"
        return 1
    fi

    log_info "Retrieving join command..."
    ssh -o StrictHostKeyChecking=no ubuntu@"$MASTER_HOST" "cat $join_file" > /tmp/join-command.sh
    chmod +x /tmp/join-command.sh

    log_info "Joining cluster..."
    if sudo bash /tmp/join-command.sh; then
        log_success "Successfully joined cluster"
    else
        log_error "Failed to join cluster"
        return 1
    fi
}

# CNI installation
install_cni() {
    log_info "Installing Flannel CNI..."
    export KUBECONFIG=/home/ubuntu/.kube/config

    # Wait for cluster to be ready
    log_info "Waiting for cluster to be ready..."
    local attempts=0
    while [[ $attempts -lt 10 ]]; do
        if kubectl get nodes &>/dev/null; then
            break
        fi
        log_info "Waiting for cluster... ($((attempts + 1))/10)"
        sleep 15
        ((attempts++))
    done

    if kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml; then
        log_success "Flannel CNI installed successfully"

        # Wait for flannel pods to be ready
        log_info "Waiting for Flannel pods to be ready..."
        kubectl wait --for=condition=ready pod -l app=flannel -n kube-flannel --timeout=300s || log_warning "Flannel pods may not be ready yet"
    else
        log_error "Failed to install Flannel CNI"
        return 1
    fi
}

# Wait for API server
wait_for_api_server() {
    local attempts=0
    export KUBECONFIG=/home/ubuntu/.kube/config

    while [[ $attempts -lt 30 ]]; do
        if kubectl get nodes &>/dev/null; then
            log_success "API server is ready"
            return 0
        fi
        log_info "Waiting for API server... ($((attempts + 1))/30)"
        sleep 10
        ((attempts++))
    done

    log_error "API server not ready after 5 minutes"
    return 1
}

# Verification
verify_installation() {
    log_info "=== Service Status ==="
    log_info "Docker status: $(sudo systemctl is-active docker)"
    log_info "Containerd status: $(sudo systemctl is-active containerd)"
    log_info "Kubelet status: $(sudo systemctl is-active kubelet)"

    if [[ "$NODE_ROLE" == "master" ]]; then
        export KUBECONFIG=/home/ubuntu/.kube/config
        log_info "=== Cluster Status ==="
        log_info "Cluster nodes:"
        kubectl get nodes -o wide || log_warning "Could not get nodes"
        log_info "System pods:"
        kubectl get pods -A || log_warning "Could not get system pods"
        log_info "Cluster info:"
        kubectl cluster-info || log_warning "Could not get cluster info"
    fi
}

# Run main function
main "$@"