#!/bin/bash
#
# Automated SSL Certificate Renewal Script for Grafana/Prometheus/Node Exporter
# This script checks certificate expiration and renews it from Vault if needed
#
# Installation:
# 1. Copy this script to /usr/local/bin/renew-monitoring-certs.sh on the monitoring server
# 2. Store Vault token securely in /etc/vault/token (mode 600, owned by root)
# 3. Add to crontab: 0 2 * * * /usr/local/bin/renew-monitoring-certs.sh
#
# Usage: ./renew-monitoring-certs.sh

set -e

# Configuration
VAULT_ADDR="${VAULT_ADDR:-https://10.0.2.40:8200}"
VAULT_TOKEN_FILE="/etc/vault/token"
CERT_DIR="/etc/ssl/grafana"
CERT_FILE="${CERT_DIR}/multi-domain-cert.pem"
RENEWAL_DAYS=15  # Renew if cert expires in less than this many days
HOSTNAME="grafana.homelab.com"
IP_ADDRESS="10.0.2.30"
LOG_FILE="/var/log/cert-renewal.log"

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to send notification (optional - can integrate with email/slack)
notify() {
    log "NOTIFICATION: $1"
    # Add your notification method here (email, slack, etc.)
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log "ERROR: This script must be run as root"
   exit 1
fi

log "========================================="
log "Certificate Renewal Check Started"
log "========================================="

# Check if certificate exists
if [ ! -f "$CERT_FILE" ]; then
    log "ERROR: Certificate file not found: $CERT_FILE"
    notify "Certificate file missing! Manual intervention required."
    exit 1
fi

# Get certificate expiration date
EXPIRY_DATE=$(openssl x509 -in "$CERT_FILE" -noout -enddate | cut -d= -f2)
EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s)
CURRENT_EPOCH=$(date +%s)
DAYS_UNTIL_EXPIRY=$(( ($EXPIRY_EPOCH - $CURRENT_EPOCH) / 86400 ))

log "Certificate expires on: $EXPIRY_DATE"
log "Days until expiry: $DAYS_UNTIL_EXPIRY"

# Check if renewal is needed
if [ $DAYS_UNTIL_EXPIRY -gt $RENEWAL_DAYS ]; then
    log "Certificate is still valid for $DAYS_UNTIL_EXPIRY days. No renewal needed."
    log "Next check will renew if less than $RENEWAL_DAYS days remain."
    exit 0
fi

log "WARNING: Certificate expires in $DAYS_UNTIL_EXPIRY days. Starting renewal process..."
notify "Certificate renewal triggered: $DAYS_UNTIL_EXPIRY days until expiry"

# Check if Vault token file exists
if [ ! -f "$VAULT_TOKEN_FILE" ]; then
    log "ERROR: Vault token file not found: $VAULT_TOKEN_FILE"
    log "Please create the token file with: echo 'your-vault-token' > $VAULT_TOKEN_FILE && chmod 600 $VAULT_TOKEN_FILE"
    notify "Certificate renewal FAILED: Vault token missing"
    exit 1
fi

# Read Vault token
VAULT_TOKEN=$(cat "$VAULT_TOKEN_FILE")

if [ -z "$VAULT_TOKEN" ]; then
    log "ERROR: Vault token is empty"
    notify "Certificate renewal FAILED: Empty Vault token"
    exit 1
fi

# Backup current certificates
BACKUP_DIR="${CERT_DIR}/backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
log "Backing up current certificates to: $BACKUP_DIR"
cp ${CERT_DIR}/multi-domain-*.pem "$BACKUP_DIR/" 2>/dev/null || true

# Generate new certificate from Vault
log "Requesting new certificate from Vault..."

# Generate JSON payload for Vault
JSON_PAYLOAD=$(cat <<EOF
{
  "common_name": "${HOSTNAME}",
  "alt_names": "${HOSTNAME}",
  "ip_sans": "${IP_ADDRESS}",
  "ttl": "8760h"
}
EOF
)

# Request certificate from Vault
RESPONSE=$(curl -sk -X POST \
    -H "X-Vault-Token: ${VAULT_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$JSON_PAYLOAD" \
    "${VAULT_ADDR}/v1/pki-intermediate/issue/homelab-dot-com")

# Check if request was successful
if echo "$RESPONSE" | grep -q '"errors"'; then
    log "ERROR: Failed to get certificate from Vault"
    log "Response: $RESPONSE"
    notify "Certificate renewal FAILED: Vault API error"
    exit 1
fi

# Extract certificate components
echo "$RESPONSE" | jq -r '.data.certificate' > "${CERT_DIR}/multi-domain-cert.pem.new"
echo "$RESPONSE" | jq -r '.data.private_key' > "${CERT_DIR}/multi-domain-key.pem.new"
echo "$RESPONSE" | jq -r '.data.ca_chain[]' > "${CERT_DIR}/multi-domain-ca.pem.new"

# Create fullchain (cert + CA chain)
cat "${CERT_DIR}/multi-domain-cert.pem.new" "${CERT_DIR}/multi-domain-ca.pem.new" > "${CERT_DIR}/multi-domain-fullchain.pem.new"

# Create bundle (cert + issuing CA + CA chain)
echo "$RESPONSE" | jq -r '.data.issuing_ca' > /tmp/issuing-ca.pem
cat "${CERT_DIR}/multi-domain-cert.pem.new" /tmp/issuing-ca.pem "${CERT_DIR}/multi-domain-ca.pem.new" > "${CERT_DIR}/multi-domain-bundle.pem.new"
rm /tmp/issuing-ca.pem

# Verify new certificate
if ! openssl x509 -in "${CERT_DIR}/multi-domain-cert.pem.new" -noout -text >/dev/null 2>&1; then
    log "ERROR: New certificate is invalid"
    rm -f ${CERT_DIR}/*.pem.new
    notify "Certificate renewal FAILED: Invalid certificate received"
    exit 1
fi

log "New certificate validated successfully"

# Replace old certificates with new ones
mv "${CERT_DIR}/multi-domain-cert.pem.new" "${CERT_DIR}/multi-domain-cert.pem"
mv "${CERT_DIR}/multi-domain-key.pem.new" "${CERT_DIR}/multi-domain-key.pem"
mv "${CERT_DIR}/multi-domain-ca.pem.new" "${CERT_DIR}/multi-domain-ca.pem"
mv "${CERT_DIR}/multi-domain-fullchain.pem.new" "${CERT_DIR}/multi-domain-fullchain.pem"
mv "${CERT_DIR}/multi-domain-bundle.pem.new" "${CERT_DIR}/multi-domain-bundle.pem"

# Set proper permissions
chmod 644 ${CERT_DIR}/multi-domain-*.pem
chmod 600 ${CERT_DIR}/multi-domain-key.pem

log "Certificates updated successfully"

# Restart services to use new certificates
log "Restarting services..."

systemctl restart grafana-server
log "✓ Grafana restarted"

systemctl restart prometheus
log "✓ Prometheus restarted"

systemctl restart node_exporter
log "✓ Node Exporter restarted"

# Verify services are running
sleep 5

if systemctl is-active --quiet grafana-server && \
   systemctl is-active --quiet prometheus && \
   systemctl is-active --quiet node_exporter; then
    log "SUCCESS: All services restarted successfully with new certificates"
    NEW_EXPIRY=$(openssl x509 -in "$CERT_FILE" -noout -enddate | cut -d= -f2)
    log "New certificate expires on: $NEW_EXPIRY"
    notify "Certificate renewal SUCCESSFUL. New expiry: $NEW_EXPIRY"
else
    log "ERROR: One or more services failed to restart"
    log "Grafana: $(systemctl is-active grafana-server)"
    log "Prometheus: $(systemctl is-active prometheus)"
    log "Node Exporter: $(systemctl is-active node_exporter)"
    notify "Certificate renewal completed but service restart FAILED"
    exit 1
fi

log "========================================="
log "Certificate Renewal Completed Successfully"
log "========================================="

exit 0

