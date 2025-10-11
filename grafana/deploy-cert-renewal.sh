#!/bin/bash
# Deploy Certificate Auto-Renewal to Monitoring Server
# Usage: ./deploy-cert-renewal.sh [target_ip] [vault_token] [ssh_user]

set -e

TARGET_IP="${1:-10.0.2.30}"
VAULT_TOKEN="${2}"
SSH_USER="${3:-anandy}"

if [ -z "$VAULT_TOKEN" ]; then
    echo "ERROR: Vault token is required"
    echo "Usage: $0 <target_ip> <vault_token> [ssh_user]"
    echo "Example: $0 10.0.2.30 hvs.Z9X5FA2dEhbh2A0VYGlyMiB5 anandy"
    exit 1
fi

echo "========================================="
echo "Certificate Auto-Renewal Deployment"
echo "========================================="
echo "Target: $TARGET_IP"
echo "SSH User: $SSH_USER"
echo ""

# Copy renewal script to server
echo "📦 Copying renewal script to server..."
scp renew-monitoring-certs.sh ${SSH_USER}@${TARGET_IP}:/tmp/
echo "✅ Script copied"

# Install and configure on server
echo "🔧 Configuring auto-renewal on server..."
ssh ${SSH_USER}@${TARGET_IP} "sudo bash -s" <<ENDSSH
set -e

# Install jq if not present (required for parsing Vault JSON responses)
if ! command -v jq &> /dev/null; then
    echo "Installing jq..."
    apt-get update -qq
    apt-get install -y -qq jq
fi

# Move script to /usr/local/bin
mv /tmp/renew-monitoring-certs.sh /usr/local/bin/
chmod +x /usr/local/bin/renew-monitoring-certs.sh
chown root:root /usr/local/bin/renew-monitoring-certs.sh

# Create Vault token directory
mkdir -p /etc/vault
chmod 700 /etc/vault

# Store Vault token securely
echo "${VAULT_TOKEN}" > /etc/vault/token
chmod 600 /etc/vault/token
chown root:root /etc/vault/token

# Create log directory
mkdir -p /var/log
touch /var/log/cert-renewal.log
chmod 644 /var/log/cert-renewal.log

# Create backup directory for old certificates
mkdir -p /etc/ssl/grafana/backups
chmod 755 /etc/ssl/grafana/backups

# Add cron job to run daily at 2 AM
CRON_JOB="0 2 * * * /usr/local/bin/renew-monitoring-certs.sh >> /var/log/cert-renewal.log 2>&1"

# Check if cron job already exists
if ! crontab -l 2>/dev/null | grep -q "renew-monitoring-certs.sh"; then
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo "✅ Cron job added"
else
    echo "✅ Cron job already exists"
fi

# Display cron jobs
echo ""
echo "Current cron jobs:"
crontab -l | grep -v "^#" || true

echo ""
echo "✅ Auto-renewal configured successfully!"
ENDSSH

echo ""
echo "========================================="
echo "Deployment Complete!"
echo "========================================="
echo ""
echo "Configuration:"
echo "- Renewal script: /usr/local/bin/renew-monitoring-certs.sh"
echo "- Vault token stored securely in: /etc/vault/token"
echo "- Log file: /var/log/cert-renewal.log"
echo "- Cron schedule: Daily at 2 AM"
echo "- Renewal threshold: 15 days before expiry"
echo ""
echo "Test the renewal script manually:"
echo "  ssh ${SSH_USER}@${TARGET_IP} 'sudo /usr/local/bin/renew-monitoring-certs.sh'"
echo ""
echo "View renewal logs:"
echo "  ssh ${SSH_USER}@${TARGET_IP} 'sudo tail -f /var/log/cert-renewal.log'"
echo ""
echo "Check cron jobs:"
echo "  ssh ${SSH_USER}@${TARGET_IP} 'sudo crontab -l'"
echo ""
