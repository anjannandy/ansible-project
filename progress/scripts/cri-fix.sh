#!/bin/bash
# Simple containerd CRI fix - run this script

echo "=== Simple Containerd CRI Fix ==="

for worker in 192.168.1.191 192.168.1.192 192.168.1.193 192.168.1.194; do
    echo "========================================="
    echo "Fixing worker: $worker"
    echo "========================================="

    ssh ubuntu@$worker 'sudo bash -s' << 'SCRIPT'
        set -e

        echo "=== Stopping services ==="
        systemctl stop kubelet || true
        systemctl stop containerd || true
        sleep 2

        echo "=== Complete cleanup ==="
        rm -rf /etc/containerd/config.toml
        rm -rf /var/lib/containerd/*

        echo "=== Generate default containerd config ==="
        mkdir -p /etc/containerd
        containerd config default > /etc/containerd/config.toml

        echo "=== Enable SystemdCgroup ==="
        sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

        echo "=== Starting containerd ==="
        systemctl daemon-reload
        systemctl enable containerd
        systemctl start containerd

        echo "=== Waiting for containerd socket ==="
        timeout 30 bash -c 'until [ -S /var/run/containerd/containerd.sock ]; do sleep 1; done'

        echo "=== Installing crictl ==="
        cd /tmp
        VERSION="v1.30.0"
        if [ ! -f /usr/local/bin/crictl ]; then
            wget -q https://github.com/kubernetes-sigs/cri-tools/releases/download/$VERSION/crictl-$VERSION-linux-amd64.tar.gz
            tar zxf crictl-$VERSION-linux-amd64.tar.gz
            mv crictl /usr/local/bin/
            rm -f crictl-$VERSION-linux-amd64.tar.gz
        fi

        echo "=== Configuring crictl ==="
        cat > /etc/crictl.yaml << 'EOF'
runtime-endpoint: unix:///var/run/containerd/containerd.sock
image-endpoint: unix:///var/run/containerd/containerd.sock
timeout: 10
debug: false
EOF

        echo "=== Testing ==="
        sleep 5

        echo "Testing ctr version:"
        if ctr version; then
            echo "✓ containerd core OK"
        else
            echo "✗ containerd core FAILED"
            exit 1
        fi

        echo "Testing crictl version:"
        if crictl version; then
            echo "✓ containerd CRI OK"
        else
            echo "✗ containerd CRI FAILED"
            exit 1
        fi

        echo "Testing crictl info:"
        if crictl info > /dev/null; then
            echo "✓ containerd CRI info OK"
        else
            echo "✗ containerd CRI info FAILED"
            exit 1
        fi

        echo "=== Cleanup kubeadm state ==="
        kubeadm reset -f || true
        rm -rf /etc/kubernetes/kubelet.conf || true
        rm -rf /var/lib/kubelet/* || true
        rm -f /var/lib/k8s-setup-state/*_completed || true

        echo "=== Starting kubelet ==="
        systemctl enable kubelet
        systemctl start kubelet

        echo "=== Worker $(hostname) ready! ==="
SCRIPT

    if [ $? -eq 0 ]; then
        echo "✓ Worker $worker fixed successfully"
    else
        echo "✗ Worker $worker failed to fix"
    fi
done

echo ""
echo "========================================="
echo "All workers should now be ready!"
echo "Now run your Ansible playbook:"
echo "ansible-playbook fix-workers.yml"
echo "========================================="