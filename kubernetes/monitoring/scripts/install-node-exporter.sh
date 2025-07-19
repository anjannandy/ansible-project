#!/bin/bash
set -e

VERSION="1.7.0"
USER="node_exporter"
PORT="9100"

echo "Installing Node Exporter v${VERSION}..."

# Check if already installed
if systemctl is-active --quiet node_exporter 2>/dev/null; then
    echo "✅ Node Exporter already running"
    exit 0
fi

# Create user
if ! id "${USER}" &>/dev/null; then
    useradd --no-create-home --shell /bin/false --system "${USER}"
fi

# Download and install
cd /tmp
wget -q "https://github.com/prometheus/node_exporter/releases/download/v${VERSION}/node_exporter-${VERSION}.linux-amd64.tar.gz"
tar -xzf "node_exporter-${VERSION}.linux-amd64.tar.gz"
cp "node_exporter-${VERSION}.linux-amd64/node_exporter" /usr/local/bin/
chown "${USER}:${USER}" /usr/local/bin/node_exporter
chmod +x /usr/local/bin/node_exporter

# Create systemd service
cat > /etc/systemd/system/node_exporter.service << EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=${USER}
Group=${USER}
Type=simple
Restart=always
ExecStart=/usr/local/bin/node_exporter --web.listen-address=0.0.0.0:${PORT}

[Install]
WantedBy=multi-user.target
EOF

# Start service
systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter

# Verify
sleep 3
if systemctl is-active --quiet node_exporter; then
    echo "✅ Node Exporter installed and running"
    echo "📊 Endpoint: http://$(hostname -I | awk '{print $1}'):${PORT}/metrics"
else
    echo "❌ Node Exporter failed to start"
    exit 1
fi

# Cleanup
rm -rf /tmp/node_exporter-*