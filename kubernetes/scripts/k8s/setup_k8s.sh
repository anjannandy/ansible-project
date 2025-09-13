#!/bin/bash

# Kubernetes Setup Script
set -euo pipefail

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# Initialize logging and state tracking
init_logging
log_info "Starting Kubernetes setup - Role: ${NODE_ROLE:-unknown}"

# Main function dispatcher
main() {
    local action="${1:-help}"

    case "$action" in
        "system_prep")
            system_preparation
            ;;
        "install_docker")
            install_docker
            ;;
        "install_kubernetes")
            install_kubernetes
            ;;
        "configure_system")
            configure_system
            ;;
        "initialize_master")
            initialize_master
            ;;
        "join_worker")
            join_worker
            ;;
        "install_cni")
            install_cni
            ;;
        "verify_installation")
            verify_installation
            ;;
        *)
            echo "Usage: $0 {system_prep|install_docker|install_kubernetes|configure_system|initialize_master|join_worker|install_cni|verify_installation}"
            exit 1
            ;;
    esac
}

# System preparation
system_preparation() {
    log_info "Starting system preparation..."

    # Update system
    retry_command "sudo apt-get update" 3
    retry_command "sudo apt-get upgrade -y" 2

    # Install essential packages
    retry_command "sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common jq" 3

    # Disable swap permanently
    log_info "Disabling swap..."
    sudo swapoff -a
    sudo sed -i '/swap/d' /etc/fstab

    # Load required kernel modules
    log_info "Loading kernel modules..."
    sudo tee /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF

    sudo modprobe overlay
    sudo modprobe br_netfilter

    # Configure sysctl settings
    log_info "Configuring sysctl settings..."
    sudo tee /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

    sudo sysctl --system

    mark_complete "01_system_prep"
    log_success "System preparation completed"
}

# Install Docker
install_docker() {
    log_info "Installing Docker..."

    # Add Docker repository
    retry_command "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg" 3

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    retry_command "sudo apt-get update" 3
    retry_command "sudo apt-get install -y docker-ce docker-ce-cli containerd.io" 3

    # Configure Docker daemon
    log_info "Configuring Docker daemon..."
    sudo mkdir -p /etc/docker
    sudo tee /etc/docker/daemon.json <<EOF
{
    "exec-opts": ["native.cgroupdriver=systemd"],
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m"
    },
    "storage-driver": "overlay2"
}
EOF

    # Configure containerd
    log_info "Configuring containerd..."
    sudo mkdir -p /etc/containerd
    containerd config default | sudo tee /etc/containerd/config.toml
    sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml

    # Start and enable services
    sudo systemctl daemon-reload
    sudo systemctl enable docker containerd
    sudo systemctl restart docker containerd

    # Add user to docker group
    sudo usermod -aG docker $USER

    mark_complete "02_docker_install"
    log_success "Docker installation completed"
}

# Install Kubernetes
install_kubernetes() {
    log_info "Installing Kubernetes components..."

    # Add Kubernetes repository
    retry_command "curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg" 3

    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

    retry_command "sudo apt-get update" 3

    # Install specific version if provided
    if [[ -n "${K8S_VERSION:-}" ]]; then
        log_info "Installing Kubernetes version: $K8S_VERSION"
        retry_command "sudo apt-get install -y kubelet=$K8S_VERSION kubeadm=$K8S_VERSION kubectl=$K8S_VERSION" 3
    else
        retry_command "sudo apt-get install -y kubelet kubeadm kubectl" 3
    fi

    # Hold packages to prevent automatic updates
    sudo apt-mark hold kubelet kubeadm kubectl

    # Enable kubelet
    sudo systemctl enable kubelet

    mark_complete "03_k8s_install"
    log_success "Kubernetes installation completed"
}

# Configure system
configure_system() {
    log_info "Configuring system for Kubernetes..."

    # Configure kubelet
    log_info "Configuring kubelet..."
    sudo mkdir -p /etc/systemd/system/kubelet.service.d

    # Set hostname resolution
    echo "127.0.0.1 $(hostname)" | sudo tee -a /etc/hosts

    # Configure firewall (if ufw is active)
    if sudo ufw status | grep -q "Status: active"; then
        log_info "Configuring firewall..."
        if [[ "${NODE_ROLE:-}" == "master" ]]; then
            sudo ufw allow 6443/tcp   # Kubernetes API
            sudo ufw allow 2379:2380/tcp # etcd
            sudo ufw allow 10250/tcp  # kubelet
            sudo ufw allow 10259/tcp  # kube-scheduler
            sudo ufw allow 10257/tcp  # kube-controller-manager
        fi
        sudo ufw allow 10250/tcp      # kubelet (all nodes)
        sudo ufw allow 30000:32767/tcp # NodePort services
    fi

    # Restart containerd and kubelet
    sudo systemctl restart containerd kubelet

    mark_complete "04_system_config"
    log_success "System configuration completed"
}

# Initialize master node
initialize_master() {
    log_info "Initializing Kubernetes master node..."

    local master_ip="${MASTER_IP:-$(hostname -I | awk '{print $1}')}"
    local pod_cidr="${POD_CIDR:-10.244.0.0/16}"

    log_info "Master IP: $master_ip"
    log_info "Pod CIDR: $pod_cidr"

    # Initialize cluster
    log_info "Running kubeadm init..."
    retry_command "sudo kubeadm init --apiserver-advertise-address=$master_ip --pod-network-cidr=$pod_cidr --ignore-preflight-errors=NumCPU,Mem" 2

    # Configure kubectl for kubeadmin user
    log_info "Configuring kubectl..."
    mkdir -p "/home/${K8S_ADMIN_USER:-kubeadmin}/.kube"
    sudo cp -i /etc/kubernetes/admin.conf "/home/${K8S_ADMIN_USER:-kubeadmin}/.kube/config"
    sudo chown "${K8S_ADMIN_USER:-kubeadmin}:${K8S_ADMIN_USER:-kubeadmin}" "/home/${K8S_ADMIN_USER:-kubeadmin}/.kube/config"

    # Generate join command for workers
    log_info "Generating worker join command..."
    kubeadm token create --print-join-command | sudo tee "/home/${K8S_ADMIN_USER:-kubeadmin}/kubeadm-join-command.sh"
    sudo chmod +x "/home/${K8S_ADMIN_USER:-kubeadmin}/kubeadm-join-command.sh"
    sudo chown "${K8S_ADMIN_USER:-kubeadmin}:${K8S_ADMIN_USER:-kubeadmin}" "/home/${K8S_ADMIN_USER:-kubeadmin}/kubeadm-join-command.sh"

    # Wait for control plane to be ready
    log_info "Waiting for control plane to be ready..."
    export KUBECONFIG="/home/${K8S_ADMIN_USER:-kubeadmin}/.kube/config"
    retry_command "kubectl get nodes" 5

    mark_complete "05_master_init"
    log_success "Master initialization completed"
}

# Join worker node
join_worker() {
    log_info "Joining worker node to cluster..."

    local master_host="${MASTER_HOST:-}"
    if [[ -z "$master_host" ]]; then
        log_error "MASTER_HOST environment variable is required for worker nodes"
        exit 1
    fi

    # Get join command from master
    log_info "Retrieving join command from master..."
    retry_command "scp -o StrictHostKeyChecking=no ${K8S_ADMIN_USER:-kubeadmin}@$master_host:/home/${K8S_ADMIN_USER:-kubeadmin}/kubeadm-join-command.sh /tmp/kubeadm-join-command.sh" 3

    if [[ -f /tmp/kubeadm-join-command.sh ]]; then
        log_info "Executing join command..."
        sudo bash /tmp/kubeadm-join-command.sh
        rm -f /tmp/kubeadm-join-command.sh
    else
        log_error "Failed to retrieve join command from master"
        exit 1
    fi

    mark_complete "05_worker_join"
    log_success "Worker join completed"
}

# Install CNI (Flannel)
install_cni() {
    log_info "Installing CNI (Flannel)..."

    # Wait for kubectl to be available
    export KUBECONFIG="/home/${K8S_ADMIN_USER:-kubeadmin}/.kube/config"
    retry_command "kubectl get nodes" 5

    # Install Flannel CNI
    log_info "Installing Flannel CNI plugin..."
    retry_command "kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml" 3

    # Wait for CNI pods to be ready
    log_info "Waiting for CNI pods to be ready..."
    sleep 30

    local max_wait=300
    local wait_time=0
    while [[ $wait_time -lt $max_wait ]]; do
        if kubectl get pods -n kube-flannel -o jsonpath='{.items[*].status.phase}' | grep -q "Running"; then
            log_success "CNI pods are running"
            break
        fi
        log_info "Waiting for CNI pods... ($wait_time/$max_wait seconds)"
        sleep 10
        wait_time=$((wait_time + 10))
    done

    mark_complete "06_cni_install"
    log_success "CNI installation completed"
}

# Verify installation
verify_installation() {
    log_info "Verifying Kubernetes installation..."

    # Check Docker
    if ! docker --version; then
        log_error "Docker verification failed"
        return 1
    fi

    # Check Kubernetes components
    if ! kubelet --version; then
        log_error "Kubelet verification failed"
        return 1
    fi

    if ! kubeadm version; then
        log_error "Kubeadm verification failed"
        return 1
    fi

    # Role-specific verification
    if [[ "${NODE_ROLE:-}" == "master" ]]; then
        log_info "Verifying master node..."

        if ! kubectl version --client; then
            log_error "Kubectl verification failed"
            return 1
        fi

        export KUBECONFIG="/home/${K8S_ADMIN_USER:-kubeadmin}/.kube/config"
        if ! kubectl get nodes; then
            log_error "Cannot access cluster"
            return 1
        fi

        log_info "Master node verification completed"
    else
        log_info "Verifying worker node..."

        # Check if kubelet is running
        if ! systemctl is-active --quiet kubelet; then
            log_error "Kubelet is not running"
            return 1
        fi

        log_info "Worker node verification completed"
    fi

    log_success "Installation verification completed"
}

# Run main function
main "$@"