#!/bin/bash
# Script to retrieve certificate from Vault and save to files

set -e

VAULT_TOKEN="${1:-hvs.Z9X5FA2dEhbh2A0VYGlyMiB5}"
VAULT_ADDR="${2:-https://10.0.2.40:8200}"
HOSTNAME="${3:-grafana.homelab.com}"
IP="${4:-10.0.2.30}"
OUTPUT_DIR="${5:-./certs}"

echo "=== Retrieving Certificate from Vault ==="
echo "Hostname: $HOSTNAME"
echo "IP: $IP"
echo "Output Directory: $OUTPUT_DIR"
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Generate a new certificate (since we can't retrieve the old one)
echo "Generating new certificate..."
RESPONSE=$(curl -sk -X POST \
  -H "X-Vault-Token: $VAULT_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"common_name\": \"$HOSTNAME\",
    \"alt_names\": \"$HOSTNAME,localhost\",
    \"ip_sans\": \"$IP,127.0.0.1\",
    \"ttl\": \"8760h\"
  }" \
  "$VAULT_ADDR/v1/pki-intermediate/issue/vault-server")

# Check if request was successful
if echo "$RESPONSE" | grep -q "errors"; then
  echo "❌ Error generating certificate:"
  echo "$RESPONSE" | jq '.'
  exit 1
fi

# Extract and save certificate components
echo "$RESPONSE" | jq -r '.data.certificate' > "$OUTPUT_DIR/multi-domain-cert.pem"
echo "$RESPONSE" | jq -r '.data.private_key' > "$OUTPUT_DIR/multi-domain-key.pem"
echo "$RESPONSE" | jq -r '.data.issuing_ca' > "$OUTPUT_DIR/multi-domain-ca.pem"

# Create fullchain
cat "$OUTPUT_DIR/multi-domain-cert.pem" "$OUTPUT_DIR/multi-domain-ca.pem" > "$OUTPUT_DIR/multi-domain-fullchain.pem"

# Create bundle
cat "$OUTPUT_DIR/multi-domain-cert.pem" "$OUTPUT_DIR/multi-domain-ca.pem" > "$OUTPUT_DIR/multi-domain-bundle.pem"

# Set proper permissions
chmod 600 "$OUTPUT_DIR/multi-domain-key.pem"
chmod 644 "$OUTPUT_DIR/multi-domain-cert.pem"
chmod 644 "$OUTPUT_DIR/multi-domain-ca.pem"
chmod 644 "$OUTPUT_DIR/multi-domain-fullchain.pem"
chmod 644 "$OUTPUT_DIR/multi-domain-bundle.pem"

# Extract certificate info
SERIAL=$(echo "$RESPONSE" | jq -r '.data.serial_number')
EXPIRATION=$(echo "$RESPONSE" | jq -r '.data.expiration')

# Create info file
cat > "$OUTPUT_DIR/multi-domain-info.txt" << EOF
Certificate Information
=======================
Generated: $(date)
Serial Number: $SERIAL
Expiration: $(date -r $EXPIRATION 2>/dev/null || date -d @$EXPIRATION 2>/dev/null || echo "Unix timestamp: $EXPIRATION")

Certificate Details:
- Common Name: $HOSTNAME
- Alternative Names: $HOSTNAME, localhost
- IP SANs: $IP, 127.0.0.1
- Valid for: 1 year
- Key Type: RSA 2048-bit

Files Generated:
================
- multi-domain-cert.pem       (Certificate)
- multi-domain-key.pem        (Private Key - keep secure!)
- multi-domain-ca.pem         (CA Certificate)
- multi-domain-fullchain.pem  (Cert + CA chain)
- multi-domain-bundle.pem     (Cert + CA bundle)

Verification:
=============
openssl x509 -in $OUTPUT_DIR/multi-domain-cert.pem -text -noout | grep -A2 "Subject:"
openssl x509 -in $OUTPUT_DIR/multi-domain-cert.pem -text -noout | grep -A1 "Subject Alternative Name"

Usage:
======
# Copy to server
scp $OUTPUT_DIR/multi-domain-* root@$IP:/etc/ssl/grafana/

# Nginx configuration
ssl_certificate /etc/ssl/grafana/multi-domain-fullchain.pem;
ssl_certificate_key /etc/ssl/grafana/multi-domain-key.pem;

# Apache configuration
SSLCertificateFile /etc/ssl/grafana/multi-domain-cert.pem
SSLCertificateKeyFile /etc/ssl/grafana/multi-domain-key.pem
SSLCertificateChainFile /etc/ssl/grafana/multi-domain-ca.pem
EOF

echo ""
echo "✅ Certificate retrieved and saved successfully!"
echo ""
echo "📁 Files saved to: $OUTPUT_DIR"
ls -lh "$OUTPUT_DIR"
echo ""
echo "📋 Certificate Details:"
openssl x509 -in "$OUTPUT_DIR/multi-domain-cert.pem" -text -noout | grep -A2 "Subject:"
echo ""
openssl x509 -in "$OUTPUT_DIR/multi-domain-cert.pem" -text -noout | grep -A1 "Subject Alternative Name"
echo ""
echo "✅ Certificate is valid and ready to use!"

