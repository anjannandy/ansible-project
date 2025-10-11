# Grafana Monitoring Stack - Quick Start Guide
# Complete Installation from Scratch

## Prerequisites
- Proxmox server ready
- Vault server running at 10.0.2.40:8200
- Vault root token: hvs.Z9X5FA2dEhbh2A0VYGlyMiB5

---

## Step-by-Step Installation

### 1. Navigate to Grafana Directory
```bash
cd /Users/anandy/git/ansible-project/grafana
```

### 2. Clean Up Old VM (if exists)
```bash
# Delete old VM from Proxmox if it exists
# You can do this manually or via Proxmox UI
```

### 3. Generate SSL Certificates from Vault
```bash
./retrieve-cert-from-vault.sh \
  hvs.Z9X5FA2dEhbh2A0VYGlyMiB5 \
  https://10.0.2.40:8200 \
  grafana.homelab.com \
  10.0.2.30 \
  ./certs
```

**Verify certificates were created:**
```bash
ls -lh ./certs/
```

You should see:
- multi-domain-cert.pem
- multi-domain-key.pem
- multi-domain-ca.pem
- multi-domain-fullchain.pem
- multi-domain-bundle.pem
- multi-domain-info.txt

### 4. Install Grafana, Prometheus & Node Exporter
```bash
./install-monitoring.sh 10.0.2.30 ./certs anandy
```

**What this does:**
- Copies SSL certificates to /etc/ssl/grafana/ on the server (SINGLE LOCATION)
- Installs Grafana with HTTPS
- Installs Prometheus with HTTPS
- Installs Node Exporter with HTTPS
- All three services use the SAME certificates from /etc/ssl/grafana/
- Configures auto-start on boot

### 5. Deploy Automated Certificate Renewal
```bash
./deploy-cert-renewal.sh 10.0.2.30 hvs.Z9X5FA2dEhbh2A0VYGlyMiB5 anandy
```

**What this does:**
- Installs renewal script to /usr/local/bin/renew-monitoring-certs.sh
- Stores Vault token SECURELY in /etc/vault/token (mode 600, root only)
- Sets up daily cron job (runs at 2 AM)
- Creates logging and backup directories

### 6. Verify Installation

**Check services are running:**
```bash
ssh anandy@10.0.2.30 'systemctl status grafana-server prometheus node_exporter'
```

**Test HTTPS endpoints:**
```bash
# Grafana
curl -k https://10.0.2.30:3000/api/health

# Prometheus
curl -k https://10.0.2.30:9090/api/v1/status/config

# Node Exporter
curl -k https://10.0.2.30:9100/metrics | head -20
```

**Verify certificate location (SINGLE COPY):**
```bash
ssh anandy@10.0.2.30 'sudo ls -lh /etc/ssl/grafana/'
```

You should see all certificates in ONE location:
```
/etc/ssl/grafana/
├── multi-domain-cert.pem
├── multi-domain-key.pem (600 permissions)
├── multi-domain-ca.pem
├── multi-domain-fullchain.pem
├── multi-domain-bundle.pem
└── backups/
```

**Verify all services use the same certificates:**
```bash
# Grafana config
ssh anandy@10.0.2.30 'sudo grep "cert_file\|cert_key" /etc/grafana/grafana.ini'

# Prometheus config
ssh anandy@10.0.2.30 'sudo cat /etc/prometheus/web-config.yml'

# Node Exporter config
ssh anandy@10.0.2.30 'sudo cat /etc/node_exporter/web-config.yml'
```

All should point to: /etc/ssl/grafana/multi-domain-fullchain.pem

### 7. Verify Vault Token Security

**Check token file permissions:**
```bash
ssh anandy@10.0.2.30 'sudo ls -lh /etc/vault/token'
```

Should show: `-rw------- 1 root root` (only root can read)

**Verify cron job:**
```bash
ssh anandy@10.0.2.30 'sudo crontab -l'
```

Should show:
```
0 2 * * * /usr/local/bin/renew-monitoring-certs.sh >> /var/log/cert-renewal.log 2>&1
```

### 8. Test Certificate Renewal (Optional)

**Test renewal script:**
```bash
ssh anandy@10.0.2.30 'sudo /usr/local/bin/renew-monitoring-certs.sh'
```

**View renewal log:**
```bash
ssh anandy@10.0.2.30 'sudo cat /var/log/cert-renewal.log'
```

### 9. Access Grafana

**Open browser:**
```
https://grafana.homelab.com:3000
```

Or:
```
https://10.0.2.30:3000
```

**Login:**
- Username: `admin`
- Password: `admin123`

**IMPORTANT: Change password immediately!**

### 10. Configure Grafana Data Source

1. Go to Configuration → Data Sources
2. Add data source → Prometheus
3. URL: `https://localhost:9090`
4. Toggle ON: "Skip TLS Verify"
5. Click "Save & Test"

### 11. Import Dashboards

1. Dashboards → Import
2. Enter Dashboard ID: `1860` (Node Exporter Full)
3. Select Prometheus data source
4. Click Import

Repeat for other dashboards:
- Dashboard ID `2` - Prometheus Stats
- Dashboard ID `3590` - Grafana Metrics

---

## Security Verification Checklist

✅ **Single Certificate Location:**
- All certificates in /etc/ssl/grafana/
- No duplicate certificates elsewhere
- All services use the same certificates

✅ **Vault Token Security:**
- Token stored in /etc/vault/token
- Permissions: 600 (rw-------)
- Owner: root:root
- Only accessible by root

✅ **Certificate Renewal:**
- Cron job configured
- Runs daily at 2 AM
- Renews 15 days before expiry
- Auto-backs up old certificates
- Auto-restarts services

✅ **HTTPS Enabled:**
- Grafana: https://10.0.2.30:3000
- Prometheus: https://10.0.2.30:9090
- Node Exporter: https://10.0.2.30:9100

---

## Troubleshooting Commands

**Check certificate expiration:**
```bash
ssh anandy@10.0.2.30 'sudo openssl x509 -in /etc/ssl/grafana/multi-domain-cert.pem -noout -dates'
```

**View service logs:**
```bash
ssh anandy@10.0.2.30 'sudo journalctl -u grafana-server -n 50'
ssh anandy@10.0.2.30 'sudo journalctl -u prometheus -n 50'
ssh anandy@10.0.2.30 'sudo journalctl -u node_exporter -n 50'
```

**Check renewal log:**
```bash
ssh anandy@10.0.2.30 'sudo tail -f /var/log/cert-renewal.log'
```

**Verify Vault connectivity from VM:**
```bash
ssh anandy@10.0.2.30 'curl -k https://10.0.2.40:8200/v1/sys/health'
```

---

## What Happens Automatically

1. **Daily at 2 AM:** Cron runs renewal script
2. **Renewal Check:** Script checks if cert expires in <15 days
3. **If Renewal Needed:**
   - Backs up old certificates to /etc/ssl/grafana/backups/YYYYMMDD_HHMMSS/
   - Requests new certificate from Vault using stored token
   - Validates new certificate
   - Replaces old certificates in /etc/ssl/grafana/
   - Restarts grafana-server, prometheus, node_exporter
   - Logs everything to /var/log/cert-renewal.log
4. **If No Renewal Needed:** Logs status and exits

---

## Summary

**Single Certificate Copy:** ✅
- Location: /etc/ssl/grafana/
- Used by: Grafana, Prometheus, Node Exporter
- Renewed automatically every ~1 year

**Vault Token Security:** ✅
- Location: /etc/vault/token
- Permissions: 600 (root only)
- Never exposed in logs or scripts

**Auto-Renewal:** ✅
- Runs daily at 2 AM
- Renews 15 days before expiry
- Automatic backup and service restart
- Full logging

**All Services HTTPS:** ✅
- Grafana: Port 3000
- Prometheus: Port 9090
- Node Exporter: Port 9100

---

## Quick Reference

**Installation Order:**
1. `./retrieve-cert-from-vault.sh` → Generate certs
2. `./install-monitoring.sh` → Install services
3. `./deploy-cert-renewal.sh` → Setup auto-renewal

**Important Files on VM:**
- Certificates: `/etc/ssl/grafana/`
- Vault Token: `/etc/vault/token` (secure)
- Renewal Script: `/usr/local/bin/renew-monitoring-certs.sh`
- Renewal Log: `/var/log/cert-renewal.log`
- Certificate Backups: `/etc/ssl/grafana/backups/`

**Access URLs:**
- Grafana: https://grafana.homelab.com:3000
- Prometheus: https://10.0.2.30:9090
- Node Exporter: https://10.0.2.30:9100/metrics

