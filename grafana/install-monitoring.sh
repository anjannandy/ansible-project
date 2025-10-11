#!/bin/bash
# Install Grafana and Prometheus with SSL certificates
# Usage: ./install-monitoring.sh [target_ip] [cert_dir] [ssh_user]

set -e

TARGET_IP="${1:-10.0.2.30}"
CERT_DIR="${2:-./certs}"
SSH_USER="${3:-anandy}"
GRAFANA_DOMAIN="grafana.homelab.com"
GRAFANA_PORT="3000"
PROMETHEUS_VERSION="2.45.0"
NODE_EXPORTER_VERSION="1.6.1"

echo "========================================="
echo "Grafana & Prometheus Installation Script"
echo "========================================="
echo "Target: $TARGET_IP"
echo "SSH User: $SSH_USER"
echo "Certificates: $CERT_DIR"
echo ""

# Check if certificates exist locally
if [ ! -f "$CERT_DIR/multi-domain-fullchain.pem" ]; then
    echo "❌ Error: Certificates not found in $CERT_DIR"
    echo "Run ./retrieve-cert-from-vault.sh first!"
    exit 1
fi

echo "✅ Certificates found"
echo ""

# Copy certificates to target server
echo "📦 Copying SSL certificates to server..."
ssh $SSH_USER@$TARGET_IP "sudo mkdir -p /etc/ssl/grafana"
scp $CERT_DIR/multi-domain-*.pem $SSH_USER@$TARGET_IP:/tmp/
ssh $SSH_USER@$TARGET_IP "sudo mv /tmp/multi-domain-*.pem /etc/ssl/grafana/ && sudo chmod 600 /etc/ssl/grafana/multi-domain-key.pem && sudo chmod 644 /etc/ssl/grafana/multi-domain-*.pem"
echo "✅ Certificates copied"
echo ""

# Run installation on remote server
echo "🚀 Starting installation on $TARGET_IP..."
ssh $SSH_USER@$TARGET_IP 'sudo bash -s' << 'ENDSSH'
set -e

echo "📥 Updating system packages..."
apt-get update -qq

echo "📦 Installing dependencies..."
apt-get install -y -qq apt-transport-https software-properties-common wget curl gnupg tar adduser libfontconfig1 jq

# Install Vault CA certificate as trusted root CA
echo "🔐 Installing Vault CA certificate to system trust store..."
cp /etc/ssl/grafana/multi-domain-ca.pem /usr/local/share/ca-certificates/vault-ca.crt
update-ca-certificates
echo "✅ Vault CA certificate installed and trusted"

# Install Grafana
echo "📊 Installing Grafana..."
wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key
echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main" | tee /etc/apt/sources.list.d/grafana.list
apt-get update -qq
apt-get install -y -qq grafana

# Configure Grafana for HTTPS
echo "⚙️  Configuring Grafana for HTTPS..."
cat > /etc/grafana/grafana.ini << 'EOF'
[server]
protocol = https
http_addr = 0.0.0.0
http_port = 3000
domain = grafana.homelab.com
root_url = https://grafana.homelab.com:3000/
cert_file = /etc/ssl/grafana/multi-domain-fullchain.pem
cert_key = /etc/ssl/grafana/multi-domain-key.pem

[security]
admin_user = admin
admin_password = admin123

[users]
allow_sign_up = false

[auth.anonymous]
enabled = false
EOF

# Install Prometheus
echo "📈 Installing Prometheus..."
useradd --no-create-home --shell /bin/false prometheus || true
mkdir -p /etc/prometheus /var/lib/prometheus

cd /tmp
wget -q https://github.com/prometheus/prometheus/releases/download/v2.45.0/prometheus-2.45.0.linux-amd64.tar.gz
tar xzf prometheus-2.45.0.linux-amd64.tar.gz
cp prometheus-2.45.0.linux-amd64/prometheus /usr/local/bin/
cp prometheus-2.45.0.linux-amd64/promtool /usr/local/bin/
cp -r prometheus-2.45.0.linux-amd64/consoles /etc/prometheus/
cp -r prometheus-2.45.0.linux-amd64/console_libraries /etc/prometheus/
chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus /usr/local/bin/prometheus /usr/local/bin/promtool

# Configure Prometheus
cat > /etc/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    monitor: 'grafana-prometheus-stack'

scrape_configs:
  # Prometheus itself (HTTPS)
  - job_name: 'prometheus'
    scheme: https
    tls_config:
      insecure_skip_verify: true
    static_configs:
      - targets: ['localhost:9090']

  # Node Exporter (HTTPS)
  - job_name: 'node_exporter'
    scheme: https
    tls_config:
      insecure_skip_verify: true
    static_configs:
      - targets: ['localhost:9100']

  # Grafana (HTTPS)
  - job_name: 'grafana'
    scheme: https
    tls_config:
      insecure_skip_verify: true
    static_configs:
      - targets: ['localhost:3000']
EOF

chown prometheus:prometheus /etc/prometheus/prometheus.yml

# Configure Prometheus web config for HTTPS
cat > /etc/prometheus/web-config.yml << 'EOF'
tls_server_config:
  cert_file: /etc/ssl/grafana/multi-domain-fullchain.pem
  key_file: /etc/ssl/grafana/multi-domain-key.pem
EOF

chown prometheus:prometheus /etc/prometheus/web-config.yml

# Create Prometheus service
cat > /etc/systemd/system/prometheus.service << 'EOF'
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries \
  --web.listen-address=0.0.0.0:9090 \
  --web.config.file=/etc/prometheus/web-config.yml \
  --storage.tsdb.retention.time=30d \
  --storage.tsdb.retention.size=16GB \
  --web.enable-lifecycle

Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Install Node Exporter
echo "📊 Installing Node Exporter..."
useradd --no-create-home --shell /bin/false node_exporter || true
cd /tmp
wget -q https://github.com/prometheus/node_exporter/releases/download/v1.6.1/node_exporter-1.6.1.linux-amd64.tar.gz
tar xzf node_exporter-1.6.1.linux-amd64.tar.gz
cp node_exporter-1.6.1.linux-amd64/node_exporter /usr/local/bin/
chown node_exporter:node_exporter /usr/local/bin/node_exporter

# Create Node Exporter config directory
mkdir -p /etc/node_exporter
chown node_exporter:node_exporter /etc/node_exporter

# Configure Node Exporter web config for HTTPS
cat > /etc/node_exporter/web-config.yml << 'EOF'
tls_server_config:
  cert_file: /etc/ssl/grafana/multi-domain-fullchain.pem
  key_file: /etc/ssl/grafana/multi-domain-key.pem
EOF

chown node_exporter:node_exporter /etc/node_exporter/web-config.yml

# Create Node Exporter service
cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter \
  --collector.filesystem.mount-points-exclude='^/(sys|proc|dev|host|etc)($$|/)' \
  --web.listen-address=:9100 \
  --web.config.file=/etc/node_exporter/web-config.yml

Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Enable and start services
echo "🎯 Starting services..."
systemctl daemon-reload
systemctl enable grafana-server prometheus node_exporter
systemctl start grafana-server prometheus node_exporter

# Cleanup
rm -rf /tmp/prometheus-* /tmp/node_exporter-*

echo ""
echo "✅ Installation complete!"
ENDSSH

# Display status
echo ""
echo "========================================="
echo "Installation Summary"
echo "========================================="
echo ""
echo "✅ Grafana installed and running"
echo "   URL: https://$GRAFANA_DOMAIN:$GRAFANA_PORT"
echo "   Username: admin"
echo "   Password: admin123"
echo ""
echo "✅ Prometheus installed and running"
echo "   URL: https://$TARGET_IP:9090"
echo ""
echo "✅ Node Exporter installed and running"
echo "   Metrics: https://$TARGET_IP:9100/metrics"
echo ""
echo "Next Steps:"
echo "1. Access Grafana: https://grafana.homelab.com:3000"
echo "2. Login with admin/admin123"
echo "3. Change admin password!"
echo "4. Add Prometheus data source: https://localhost:9090"
echo "5. Import dashboards from grafana.com"
echo ""
echo "Check service status:"
echo "  ssh $SSH_USER@$TARGET_IP 'systemctl status grafana-server prometheus node_exporter'"
echo ""
