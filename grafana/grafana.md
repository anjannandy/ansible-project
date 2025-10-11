# ========================================
# Grafana & Prometheus Monitoring Stack
# Complete Installation Guide with HTTPS
# ========================================

## Overview
This guide provides step-by-step instructions to deploy a complete monitoring stack with:
- **Grafana** (latest) - Visualization and dashboards (HTTPS enabled)
- **Prometheus** 2.45.0 - Metrics collection and storage (HTTPS enabled)
- **Node Exporter** 1.6.1 - System metrics collection (HTTPS enabled)
- **SSL Certificates** from HashiCorp Vault for secure communication
- **Trusted CA Certificate** - Vault CA installed system-wide for proper certificate validation
- **Automated Certificate Renewal** - Auto-renew certificates 15 days before expiry

All services use SSL certificates generated from Vault. The Vault CA certificate is installed as a trusted root CA, enabling proper certificate validation without security compromises.

---

## Step 1: Create VM on Proxmox

Create a dedicated VM for the monitoring stack:

```bash
ansible-playbook -i inventory-01.ini proxmox-cloudimg.yml \
  -e vm_id=500 \
  -e vm_hostname=grafana.homelab.com \
  -e vm_ip_address=10.0.2.30 \
  -e vm_gateway=10.0.0.1 \
  -e netmask=16 \
  -e vm_memory=4096 \
  -e vm_cores=4 \
  -e vm_disk_size=64G
```

**VM Specifications:**
- IP: 10.0.2.30
- Hostname: grafana.homelab.com
- RAM: 4GB
- CPU: 4 cores
- Disk: 64GB

---

## Step 2: Generate SSL Certificates from Vault

### Option A: Using Ansible Playbook (Recommended)

```bash
ansible-playbook ../vault/generate-cert.yml --tags "save-files" \
  -e cert_hostname="grafana.homelab.com" \
  -e cert_ip="10.0.2.30" \
  -e cert_output_dir="./certs" \
  -e vault_root_token="hvs.Z9X5FA2dEhbh2A0VYGlyMiB5"
```

### Option B: Using Bash Script (Faster)

```bash
./retrieve-cert-from-vault.sh
```

Or with custom parameters:

```bash
./retrieve-cert-from-vault.sh \
  hvs.Z9X5FA2dEhbh2A0VYGlyMiB5 \
  https://10.0.2.40:8200 \
  grafana.homelab.com \
  10.0.2.30 \
  ./certs
```

### Verify Certificate Generation

Check that all certificate files were created:

```bash
ls -lh ./certs/
```

**Expected files:**
- `multi-domain-cert.pem` - Server certificate
- `multi-domain-key.pem` - Private key
- `multi-domain-ca.pem` - **CA certificate** (installed as trusted root CA)
- `multi-domain-fullchain.pem` - Full certificate chain (used by all services)
- `multi-domain-bundle.pem` - Certificate bundle
- `multi-domain-info.txt` - Certificate information

### Verify Certificate Details

```bash
# Check certificate subject
openssl x509 -in ./certs/multi-domain-cert.pem -text -noout | grep -A2 "Subject:"

# Check Subject Alternative Names (SAN)
openssl x509 -in ./certs/multi-domain-cert.pem -text -noout | grep -A1 "Subject Alternative Name"

# Check expiration date
openssl x509 -in ./certs/multi-domain-cert.pem -noout -enddate
```

---

## Step 3: Install Grafana, Prometheus & Node Exporter

### Option A: Using Ansible Playbook (Recommended for Production)

```bash
ansible-playbook -i inventory.ini install-grafana-prometheus.yml
```

**What this does:**
- Installs Grafana with HTTPS enabled
- Installs Prometheus with HTTPS enabled
- Installs Node Exporter with HTTPS enabled
- Copies SSL certificates to `/etc/ssl/grafana/` (single location)
- **Installs Vault CA certificate as trusted root CA** at `/usr/local/share/ca-certificates/vault-ca.crt`
- Updates system CA trust store
- Configures all services to start on boot
- Sets up Prometheus to scrape metrics with proper certificate validation

### Option B: Using Bash Script (Simpler, Faster)

```bash
chmod +x install-monitoring.sh
./install-monitoring.sh
```

Or with custom parameters:

```bash
./install-monitoring.sh 10.0.2.30 ./certs anandy
```

**Script parameters:**
1. Target IP (default: 10.0.2.30)
2. Certificate directory (default: ./certs)
3. SSH user (default: anandy)

**What this script does:**
- ✅ Installs all required dependencies including `jq`
- ✅ Copies SSL certificates to `/etc/ssl/grafana/` on the server
- ✅ **Installs Vault CA as system-trusted root certificate**
- ✅ Installs and configures Grafana, Prometheus, and Node Exporter with HTTPS
- ✅ All three services use the same certificates from one location
- ✅ Enables proper certificate validation (no insecure_skip_verify)

---

## Step 4: Deploy Automated Certificate Renewal

This critical step sets up automatic certificate renewal 15 days before expiry.

### Deploy the Renewal Script

```bash
chmod +x deploy-cert-renewal.sh
./deploy-cert-renewal.sh 10.0.2.30 hvs.Z9X5FA2dEhbh2A0VYGlyMiB5 anandy
```

**What this does:**
- Installs `renew-monitoring-certs.sh` to `/usr/local/bin/` on the server
- Stores Vault token **securely** in `/etc/vault/token` (mode 600, root only)
- Sets up a cron job to run daily at 2 AM
- Checks if certificate expires in less than 15 days
- Auto-renews, updates CA trust, and restarts services if renewal is needed

### Test Certificate Renewal Manually

```bash
# Test the renewal script (won't renew unless cert expires soon)
ssh anandy@10.0.2.30 'sudo /usr/local/bin/renew-monitoring-certs.sh'

# View renewal logs
ssh anandy@10.0.2.30 'sudo tail -f /var/log/cert-renewal.log'

# Check when certificates expire
ssh anandy@10.0.2.30 'sudo openssl x509 -in /etc/ssl/grafana/multi-domain-cert.pem -noout -enddate'
```

### Verify Cron Job

```bash
ssh anandy@10.0.2.30 'sudo crontab -l'
```

Expected output:
```
0 2 * * * /usr/local/bin/renew-monitoring-certs.sh >> /var/log/cert-renewal.log 2>&1
```

---

## Step 5: Verify Installation

### Check Service Status

```bash
ssh anandy@10.0.2.30 'systemctl status grafana-server prometheus node_exporter'
```

All services should show `active (running)` status.

### Verify Vault CA is Trusted

```bash
# Check CA certificate is installed
ssh anandy@10.0.2.30 'ls -lh /usr/local/share/ca-certificates/vault-ca.crt'

# Verify it's in the system trust store
ssh anandy@10.0.2.30 'grep -q "BEGIN CERTIFICATE" /etc/ssl/certs/ca-certificates.crt && echo "✅ System CA bundle updated"'
```

### Check Listening Ports

```bash
ssh anandy@10.0.2.30 'sudo ss -tlnp | grep -E "(3000|9090|9100)"'
```

**Expected output:**
- Port 3000 - Grafana (HTTPS)
- Port 9090 - Prometheus (HTTPS)
- Port 9100 - Node Exporter (HTTPS)

### Test HTTPS Endpoints with Certificate Validation

```bash
# Test Grafana HTTPS (with certificate validation)
curl https://10.0.2.30:3000/api/health --cacert ./certs/multi-domain-ca.pem

# Test Prometheus HTTPS
curl https://10.0.2.30:9090/api/v1/status/config --cacert ./certs/multi-domain-ca.pem

# Test Node Exporter HTTPS
curl https://10.0.2.30:9100/metrics --cacert ./certs/multi-domain-ca.pem | head -20
```

### View Service Logs

```bash
# Grafana logs
ssh anandy@10.0.2.30 'journalctl -u grafana-server -f'

# Prometheus logs
ssh anandy@10.0.2.30 'journalctl -u prometheus -f'

# Node Exporter logs
ssh anandy@10.0.2.30 'journalctl -u node_exporter -f'
```

Press `Ctrl+C` to stop following logs.

---

## Step 6: Access & Configure Grafana

### Initial Access

1. Open your browser and navigate to: **https://grafana.homelab.com:3000** or **https://10.0.2.30:3000**
2. You may see a certificate warning (since it's a Vault-issued cert not in your browser's trust store)
   - Click "Advanced" → "Proceed to grafana.homelab.com"
   - **Note:** This is only in your browser. On the server itself, the CA is trusted!
3. Login with default credentials:
   - **Username:** `admin`
   - **Password:** `admin123`

### Change Admin Password (Important!)

1. After first login, go to user profile (bottom left icon)
2. Click "Change Password"
3. Set a strong password
4. Click "Save"

---

## Step 7: Add Prometheus Data Source

### Configure Prometheus Connection

1. In Grafana, click **Connections** → **Data Sources**
2. Click **Add data source**
3. Select **Prometheus**
4. Configure the following settings:
   - **Name:** `Prometheus`
   - **URL:** `https://localhost:9090`
   - **Skip TLS Verify:** **LEAVE IT OFF** ❌
   
   ⚠️ **IMPORTANT:** Do NOT toggle "Skip TLS Verify" ON. The Vault CA certificate has been installed as a trusted root CA on the system, so proper certificate validation is enabled and working!

5. Scroll down and click **Save & Test**
6. You should see: ✅ **"Successfully queried the Prometheus API"**

**Why it works without "Skip TLS Verify":**
- The Vault CA certificate is installed at `/usr/local/share/ca-certificates/vault-ca.crt`
- System CA trust store has been updated with `update-ca-certificates`
- Grafana uses the system CA trust store for HTTPS connections
- All certificates are properly validated - **no security compromises!**

---

## Step 8: Import Pre-built Dashboards

### Import Node Exporter Dashboard

1. Click **Dashboards** (four squares icon) → **Import**
2. Enter Dashboard ID: **1860**
3. Click **Load**
4. Select **Prometheus** as the data source
5. Click **Import**

This dashboard provides comprehensive system metrics:
- CPU usage
- Memory usage
- Disk I/O
- Network traffic
- System load

### Import Prometheus Stats Dashboard

1. Click **Dashboards** → **Import**
2. Enter Dashboard ID: **2**
3. Click **Load**
4. Select **Prometheus** as the data source
5. Click **Import**

This dashboard shows Prometheus internal metrics and performance.

### Other Recommended Dashboards

- **Grafana Metrics:** Dashboard ID `3590`
- **Node Exporter Full:** Dashboard ID `1860`
- **Linux Server Metrics:** Dashboard ID `12486`

---

## Configuration Details

### SSL Certificates & CA Trust

**Certificate Location (Single Source):** `/etc/ssl/grafana/`

**Files used:**
- `multi-domain-fullchain.pem` - Used by Grafana, Prometheus, and Node Exporter
- `multi-domain-key.pem` - Private key (permissions: 600)
- `multi-domain-ca.pem` - CA certificate
- `backups/` - Automatic backups created before each renewal

**Trusted CA Certificate:** `/usr/local/share/ca-certificates/vault-ca.crt`
- Installed during setup
- Added to system CA trust store
- Enables proper certificate validation across all services
- **Production-ready security - no insecure_skip_verify needed!**

**Certificate access:**
```bash
# List certificates
ssh anandy@10.0.2.30 'sudo ls -lh /etc/ssl/grafana/'

# View certificate details
ssh anandy@10.0.2.30 'sudo openssl x509 -in /etc/ssl/grafana/multi-domain-cert.pem -text -noout | head -20'

# Check expiration
ssh anandy@10.0.2.30 'sudo openssl x509 -in /etc/ssl/grafana/multi-domain-cert.pem -noout -dates'

# Verify CA is trusted
ssh anandy@10.0.2.30 'ls -lh /usr/local/share/ca-certificates/vault-ca.crt'
```

### Grafana Configuration

**Config file:** `/etc/grafana/grafana.ini`

**Key settings:**
- Protocol: HTTPS
- Port: 3000
- Domain: grafana.homelab.com
- SSL Cert: `/etc/ssl/grafana/multi-domain-fullchain.pem`
- SSL Key: `/etc/ssl/grafana/multi-domain-key.pem`

**View config:**
```bash
ssh anandy@10.0.2.30 'sudo cat /etc/grafana/grafana.ini | grep -A15 "\[server\]"'
```

### Prometheus Configuration

**Config files:**
- `/etc/prometheus/prometheus.yml` - Main configuration
- `/etc/prometheus/web-config.yml` - HTTPS/TLS configuration

**Key settings:**
- HTTPS enabled on port 9090
- Scrape interval: 15 seconds
- Data retention: 30 days or 16GB (whichever comes first)
- Data directory: `/var/lib/prometheus`
- **Certificate validation: ENABLED** (uses system CA trust store)

**Scrape targets (all with proper certificate validation):**
1. **Prometheus itself** (HTTPS) - `localhost:9090`
2. **Node Exporter** (HTTPS) - `localhost:9100`
3. **Grafana** (HTTPS) - `localhost:3000`

**View config:**
```bash
ssh anandy@10.0.2.30 'sudo cat /etc/prometheus/prometheus.yml'
ssh anandy@10.0.2.30 'sudo cat /etc/prometheus/web-config.yml'
```

**Validate config:**
```bash
ssh anandy@10.0.2.30 'sudo /usr/local/bin/promtool check config /etc/prometheus/prometheus.yml'
```

### Node Exporter Configuration

**Port:** 9100 (HTTPS)
**Metrics endpoint:** https://10.0.2.30:9100/metrics
**Config file:** `/etc/node_exporter/web-config.yml`

**View metrics:**
```bash
curl -k https://10.0.2.30:9100/metrics | head -50
```

**View config:**
```bash
ssh anandy@10.0.2.30 'sudo cat /etc/node_exporter/web-config.yml'
```

---

## Access URLs

| Service | URL | Protocol | Notes |
|---------|-----|----------|-------|
| Grafana | https://grafana.homelab.com:3000 | HTTPS | Web UI for dashboards |
| Grafana | https://10.0.2.30:3000 | HTTPS | Direct IP access |
| Prometheus | https://10.0.2.30:9090 | HTTPS | Query interface |
| Node Exporter | https://10.0.2.30:9100/metrics | HTTPS | System metrics |

---

## Automated Certificate Renewal

### How It Works

1. **Daily Check:** Cron job runs at 2 AM daily
2. **Expiry Check:** Checks if certificate expires in less than 15 days
3. **Auto-Renewal:** If needed, requests new cert from Vault
4. **Backup:** Backs up old certificates before renewal
5. **Restart:** Restarts all services with new certificates
6. **Logging:** Logs all actions to `/var/log/cert-renewal.log`

### Renewal Script Location

- **Script:** `/usr/local/bin/renew-monitoring-certs.sh`
- **Vault Token:** `/etc/vault/token` (mode 600, root only)
- **Log File:** `/var/log/cert-renewal.log`
- **Backups:** `/etc/ssl/grafana/backups/YYYYMMDD_HHMMSS/`

### Manual Certificate Renewal

```bash
# Force renewal check (won't renew unless needed)
ssh anandy@10.0.2.30 'sudo /usr/local/bin/renew-monitoring-certs.sh'
```

### View Renewal History

```bash
# View full log
ssh anandy@10.0.2.30 'sudo cat /var/log/cert-renewal.log'

# View last renewal
ssh anandy@10.0.2.30 'sudo tail -50 /var/log/cert-renewal.log'

# Follow renewal log in real-time
ssh anandy@10.0.2.30 'sudo tail -f /var/log/cert-renewal.log'
```

### Check Certificate Backups

```bash
# List all backups
ssh anandy@10.0.2.30 'sudo ls -lh /etc/ssl/grafana/backups/'

# View specific backup
ssh anandy@10.0.2.30 'sudo ls -lh /etc/ssl/grafana/backups/20251010_020000/'
```

### Vault Token Security

The Vault token is stored securely:
- **Location:** `/etc/vault/token`
- **Permissions:** 600 (readable only by root)
- **Owner:** root:root

**To update the Vault token:**
```bash
ssh anandy@10.0.2.30 'echo "new-vault-token" | sudo tee /etc/vault/token && sudo chmod 600 /etc/vault/token'
```

### Modify Renewal Threshold

Edit the script to change when renewal happens (default: 15 days):

```bash
ssh anandy@10.0.2.30 'sudo nano /usr/local/bin/renew-monitoring-certs.sh'
# Change: RENEWAL_DAYS=15
```

---

## Maintenance & Operations

### Restart Services

```bash
# Restart all services
ssh anandy@10.0.2.30 'sudo systemctl restart grafana-server prometheus node_exporter'

# Restart individual service
ssh anandy@10.0.2.30 'sudo systemctl restart grafana-server'
ssh anandy@10.0.2.30 'sudo systemctl restart prometheus'
ssh anandy@10.0.2.30 'sudo systemctl restart node_exporter'
```

### Reload Prometheus Configuration

```bash
# Reload without restart (requires --web.enable-lifecycle)
ssh anandy@10.0.2.30 'curl -X POST https://localhost:9090/-/reload -k'
```

### Check Disk Usage

```bash
# Check Prometheus data directory size
ssh anandy@10.0.2.30 'sudo du -sh /var/lib/prometheus'

# Check detailed breakdown
ssh anandy@10.0.2.30 'sudo du -h --max-depth=1 /var/lib/prometheus'
```

### Backup Configuration

```bash
# Backup Grafana config
scp anandy@10.0.2.30:/etc/grafana/grafana.ini ./backups/grafana.ini.bak

# Backup Prometheus config
scp anandy@10.0.2.30:/etc/prometheus/prometheus.yml ./backups/prometheus.yml.bak
scp anandy@10.0.2.30:/etc/prometheus/web-config.yml ./backups/web-config.yml.bak

# Backup Node Exporter config
scp anandy@10.0.2.30:/etc/node_exporter/web-config.yml ./backups/node-exporter-web-config.yml.bak

# Backup current certificates
scp anandy@10.0.2.30:/etc/ssl/grafana/multi-domain-*.pem ./backups/certs/
```

---

## Troubleshooting

### Grafana Not Accessible via HTTPS

**Check SSL certificates:**
```bash
ssh anandy@10.0.2.30 'sudo ls -lh /etc/ssl/grafana/'
```

**Verify Grafana is using certificates:**
```bash
ssh anandy@10.0.2.30 'sudo cat /etc/grafana/grafana.ini | grep -E "(cert_file|cert_key)"'
```

**Check Grafana logs for SSL errors:**
```bash
ssh anandy@10.0.2.30 'sudo journalctl -u grafana-server -n 50 | grep -i ssl'
```

### Prometheus HTTPS Connection Issues

**Test Prometheus HTTPS:**
```bash
curl -k https://10.0.2.30:9090/api/v1/status/config
```

**Check web config file:**
```bash
ssh anandy@10.0.2.30 'sudo cat /etc/prometheus/web-config.yml'
```

**Verify Prometheus can read certificates:**
```bash
ssh anandy@10.0.2.30 'sudo -u prometheus ls -lh /etc/ssl/grafana/'
```

### Node Exporter HTTPS Issues

**Test Node Exporter HTTPS:**
```bash
curl -k https://10.0.2.30:9100/metrics
```

**Check web config:**
```bash
ssh anandy@10.0.2.30 'sudo cat /etc/node_exporter/web-config.yml'
```

**Verify Node Exporter can read certificates:**
```bash
ssh anandy@10.0.2.30 'sudo -u node_exporter ls -lh /etc/ssl/grafana/'
```

### Prometheus Not Scraping Targets

**Check targets status:**
1. Open https://10.0.2.30:9090/targets
2. All targets should show "UP" status

**Via command line:**
```bash
curl -k https://10.0.2.30:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'
```

**Check scrape errors:**
```bash
ssh anandy@10.0.2.30 'sudo journalctl -u prometheus -n 100 | grep -i error'
```

### Certificate Renewal Issues

**Check if renewal script exists:**
```bash
ssh anandy@10.0.2.30 'sudo ls -lh /usr/local/bin/renew-monitoring-certs.sh'
```

**Verify Vault token:**
```bash
ssh anandy@10.0.2.30 'sudo test -f /etc/vault/token && echo "Token file exists" || echo "Token file missing"'
```

**Test Vault connectivity:**
```bash
ssh anandy@10.0.2.30 'curl -k https://10.0.2.40:8200/v1/sys/health'
```

**View renewal errors:**
```bash
ssh anandy@10.0.2.30 'sudo grep ERROR /var/log/cert-renewal.log'
```

**Manually trigger renewal (for testing):**
```bash
# Temporarily change renewal threshold to 365 days to force renewal
ssh anandy@10.0.2.30 'sudo bash -c "sed -i \"s/RENEWAL_DAYS=15/RENEWAL_DAYS=365/\" /usr/local/bin/renew-monitoring-certs.sh"'
ssh anandy@10.0.2.30 'sudo /usr/local/bin/renew-monitoring-certs.sh'
# Restore original threshold
ssh anandy@10.0.2.30 'sudo bash -c "sed -i \"s/RENEWAL_DAYS=365/RENEWAL_DAYS=15/\" /usr/local/bin/renew-monitoring-certs.sh"'
```

### Firewall Issues

**Check if UFW is active:**
```bash
ssh anandy@10.0.2.30 'sudo ufw status'
```

**Allow required ports:**
```bash
ssh anandy@10.0.2.30 'sudo ufw allow 3000/tcp comment "Grafana HTTPS"'
ssh anandy@10.0.2.30 'sudo ufw allow 9090/tcp comment "Prometheus HTTPS"'
ssh anandy@10.0.2.30 'sudo ufw allow 9100/tcp comment "Node Exporter HTTPS"'
```

---

## Security Best Practices

1. **Change default admin password** immediately after first login
2. **Use strong passwords** for all Grafana users
3. **Disable anonymous access** (already configured)
4. **Disable user sign-up** (already configured)
5. **Secure Vault token** - Keep `/etc/vault/token` with 600 permissions, root only
6. **Monitor renewal logs** - Check `/var/log/cert-renewal.log` regularly
7. **Proper certificate validation** - Vault CA trusted system-wide, no security shortcuts
8. **Use firewall rules** to restrict access to specific IPs if needed
9. **Keep software updated** - regularly update Grafana, Prometheus, and Node Exporter
10. **Backup certificates** - Automated backups are created before each renewal
11. **Rotate Vault tokens** periodically for enhanced security

---

## Summary

✅ **Grafana** - Running on port 3000 with HTTPS enabled  
✅ **Prometheus** - Running on port 9090 with HTTPS enabled  
✅ **Node Exporter** - Running on port 9100 with HTTPS enabled  
✅ **SSL Certificates** - Vault-issued certificates protecting all services  
✅ **Vault CA Trusted** - Installed as system-wide trusted root CA  
✅ **Certificate Validation** - Proper validation enabled, no security compromises  
✅ **Auto-Renewal** - Certificates automatically renewed 15 days before expiry  
✅ **Auto-start** - All services configured to start on boot  
✅ **Single Certificate Location** - All certs in `/etc/ssl/grafana/`  
✅ **Monitoring** - Complete observability stack ready for production use  
✅ **Security** - Vault token stored securely with proper permissions

**Quick Access:**
- Grafana UI: https://grafana.homelab.com:3000
- Prometheus: https://10.0.2.30:9090
- Node Exporter: https://10.0.2.30:9100/metrics

**Important Files:**
- Certificates: `/etc/ssl/grafana/` (single location)
- Trusted CA: `/usr/local/share/ca-certificates/vault-ca.crt`
- Certificate Renewal Script: `/usr/local/bin/renew-monitoring-certs.sh`
- Vault Token (secure): `/etc/vault/token` (600 permissions, root only)
- Renewal Logs: `/var/log/cert-renewal.log`
- Certificate Backups: `/etc/ssl/grafana/backups/`

**Security Highlights:**
- ✅ No `insecure_skip_verify` anywhere
- ✅ Proper TLS certificate validation enabled
- ✅ Vault CA trusted system-wide
- ✅ Production-ready configuration
