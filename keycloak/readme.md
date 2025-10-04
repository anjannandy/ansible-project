# Keycloak deployment via Ansible (VM 10.0.2.10, PostgreSQL 10.0.2.20)

This document provides a clean, step-by-step guide to deploy Keycloak with HTTPS on a VM at 10.0.2.10 using Ansible, backed by a PostgreSQL database at 10.0.2.20. The playbooks are idempotent and enable Keycloak health and metrics endpoints.

## Prerequisites
- Control machine (your laptop/workstation) with:
  - Ansible installed: `pipx install ansible` or use your distro package
  - Python 3.8+ (`python3 --version`)
  - Access to this repository
- Network/Access:
  - SSH access to 10.0.2.10 as user `anandy` (configured in inventory)
  - 10.0.2.10 can reach 10.0.2.20:5432 (PostgreSQL)
  - Port 8443 open to your clients on 10.0.2.10 (firewall/security group)
- SSL certificates:
  - Place your TLS files at `keycloak-ssl-certs/keycloak.crt` and `keycloak-ssl-certs/keycloak.key`
  - Or use the provided generator playbook to create self-signed certs (see below)

## Repository layout (relevant parts)
- keycloak/
  - inventory.ini – inventory for the Keycloak host
  - keycloak-install.yml – installs and configures Keycloak
  - postgresql-keycloak-db.yml – prepares the PostgreSQL database/user for Keycloak
  - keycloak.conf.j2 – Keycloak configuration template (HTTPS, hostname, APIs enabled)
  - keycloak.service.j2 – systemd service template (admin user/password env)
  - generate-keycloak-cert.yml – optional cert generation playbook
- keycloak-ssl-certs/ – put keycloak.crt and keycloak.key here (not tracked)

## Inventory
File: `keycloak/inventory.ini`

```
[keycloak-server]
vault ansible_host=10.0.2.10 ansible_user=anandy
```

- The hostname label `vault` is just an alias for 10.0.2.10 in the `keycloak-server` group.

## Default variables (key excerpts)
Defined in `keycloak/keycloak-install.yml`:
- keycloak_version: 22.0.5
- keycloak_hostname: 10.0.2.10 (served hostname/IP)
- cert_source_dir: ../keycloak-ssl-certs
- Database:
  - db_host: 10.0.2.20
  - db_port: 5432
  - db_name: keycloak
  - db_user: keycloak
  - db_password: keycloak_123
- Admin credentials:
  - keycloak_admin_user: anandy
  - keycloak_admin_password: welcome

You can override any variable at runtime using `-e var=value`.

## 0) Quick health checks (optional but recommended)
- Ansible and Python:
  - `ansible --version && python3 --version`
- SSH to target:
  - `ssh anandy@10.0.2.10 'echo OK'`
- Cert files present:
  - `ls -l keycloak-ssl-certs/`
- PostgreSQL reachable:
  - `nc -vz 10.0.2.20 5432 || telnet 10.0.2.20 5432`

## 1) (Optional) Generate self-signed TLS certificates
If you don’t have certs, you can generate local self-signed certs that the Keycloak install will copy:

```
ansible-playbook keycloak/generate-keycloak-cert.yml
ls -l keycloak-ssl-certs/
```

Ensure the files are named exactly `keycloak.crt` and `keycloak.key`.

## 2) Prepare the PostgreSQL database for Keycloak
This playbook runs on localhost and connects to your PostgreSQL server at 10.0.2.20 to create the database, user, and privileges for Keycloak.

```
ansible-playbook keycloak/postgresql-keycloak-db.yml
```

- On success, you’ll see a message beginning with “✅ PostgreSQL Database Setup Complete”.
- If your PostgreSQL admin credentials/host differ, override variables, e.g.:

```
ansible-playbook keycloak/postgresql-keycloak-db.yml \
  -e postgres_host=10.0.2.20 \
  -e postgres_port=5432 \
  -e postgres_admin_user=postgres \
  -e postgres_admin_password=postgres_password \
  -e keycloak_db_name=keycloak \
  -e keycloak_db_user=keycloak \
  -e keycloak_db_password=keycloak_123
```

## 3) Install and configure Keycloak on 10.0.2.10
This playbook is idempotent and will:
- Install Java 17
- Download and extract Keycloak {{ keycloak_version }}
- Configure HTTPS with your provided certs
- Enable health and metrics endpoints
- Install and start a systemd service for Keycloak

Run:

```
ansible-playbook -i keycloak/inventory.ini keycloak/keycloak-install.yml
```

If your database settings differ from defaults, override them on the command line, for example:

```
ansible-playbook -i keycloak/inventory.ini keycloak/keycloak-install.yml \
  -e db_host=10.0.2.20 -e db_name=keycloak \
  -e db_user=keycloak -e db_password=keycloak_123
```

## 4) Verify Keycloak is up
The playbook waits for the service, but you can also verify:

- Service status via Ansible:
```
ansible -i keycloak/inventory.ini keycloak-server -m shell -a "systemctl status keycloak --no-pager"
```

- Test over HTTPS (ignore warnings if self-signed):
```
curl -k https://10.0.2.10:8443/
```

- Health endpoints:
```
curl -k https://10.0.2.10:8443/health/ready
curl -k https://10.0.2.10:8443/health/live
```

- Metrics endpoint:
```
curl -k https://10.0.2.10:8443/metrics
```

- Admin console: open https://10.0.2.10:8443/ in your browser and log in with:
  - Username: `anandy`
  - Password: `welcome`

## 5) Confirm idempotency
Re-run the install playbook; expect minimal or zero changed tasks:

```
ansible-playbook -i keycloak/inventory.ini keycloak/keycloak-install.yml
```

Look for `changed=0` in the summary (or a very low number if updates occur).

## Troubleshooting
- Logs on target VM:
```
ssh anandy@10.0.2.10 'journalctl -u keycloak -n 200 --no-pager'
```
- Ensure Keycloak is listening on 8443:
```
ssh anandy@10.0.2.10 'ss -tulpen | grep 8443'
```
- Check certs and permissions on target:
```
ssh anandy@10.0.2.10 'ls -l /opt/keycloak/conf/ssl'
```
- DB connectivity from target:
```
ssh anandy@10.0.2.10 'nc -vz 10.0.2.20 5432'
```
- If you customized hostname or want to use DNS instead of IP, set `keycloak_hostname` accordingly (and ensure your certificate SubjectAltName matches).

## Security hardening
- Change the default admin password immediately after deployment.
- Store secrets in Ansible Vault (e.g., DB password, admin password):
```
ansible-vault create group_vars/all/vault.yml
# Add: vault_db_password: "..." and vault_keycloak_admin_password: "..."
```
Then reference them in playbooks or override with `-e @group_vars/all/vault.yml`.
- Restrict inbound access to port 8443 to trusted CIDRs.
- Use certificates from a trusted CA where possible.

## Uninstall / clean-up (manual)
- Stop and disable service:
```
ssh anandy@10.0.2.10 'sudo systemctl disable --now keycloak'
```
- Remove service file and Keycloak directory (be careful):
```
ssh anandy@10.0.2.10 'sudo rm -f /etc/systemd/system/keycloak.service && sudo systemctl daemon-reload'
ssh anandy@10.0.2.10 'sudo rm -rf /opt/keycloak*'
```

## Notes
- The playbooks enable health and metrics (`/health/*`, `/metrics`) by default.
- Java 17 is installed (required by Keycloak 22.x).
- The `keycloak.service` config sets admin credentials from playbook variables.

## Health checks explained
- /health/live: process liveness. Returns 200 OK when the Keycloak process is running and hasn’t encountered a fatal error. If this fails (non-2xx), systemd or your orchestrator can restart the service.
- /health/ready: service readiness. Returns 200 OK when Keycloak is fully initialized and dependencies (like database) are reachable. Typical failure causes include DB connectivity/privileges or misconfiguration in keycloak.conf.
- Exit codes and automation:
  - curl -fsS -k https://10.0.2.10:8443/health/ready will return exit code 0 on success and non-zero on failure. This is suitable for scripts and monitoring.
  - You can combine both checks:
    - curl -fsS -k https://10.0.2.10:8443/health/live && curl -fsS -k https://10.0.2.10:8443/health/ready
- Expected responses (abridged examples):
  - Live: {"status":"UP"}
  - Ready: {"status":"UP"}
- How they’re enabled: In keycloak/keycloak.conf.j2 the flags metrics-enabled=true and health-enabled=true are set.

## Metrics endpoint
- URL: https://10.0.2.10:8443/metrics (Prometheus text exposition format).
- Scraping example (Prometheus):
  - job_name: 'keycloak'
    metrics_path: /metrics
    scheme: https
    static_configs:
      - targets: ['10.0.2.10:8443']
    tls_config:
      insecure_skip_verify: true  # only for self-signed; prefer proper CA certs
- Security note: Protect this endpoint. Place behind a trusted network, reverse proxy with auth, or restrict via firewall.

## Technical details: what these playbooks do
- Version and runtime
  - Keycloak version: 22.0.5 (configurable via keycloak_version).
  - Java: openjdk-17-jdk is installed to meet Keycloak 22.x requirements.
- Installation layout on target VM
  - Archive extracted to /opt/keycloak-<version> (e.g., /opt/keycloak-22.0.5).
  - /opt/keycloak may be created as a symlink to the versioned directory when safe (empty or non-existing). If an existing non-empty directory is detected, the play uses the versioned directory directly.
  - Ownership: user/group keycloak:keycloak.
- Configuration
  - Main config: {{ keycloak_home }}/conf/keycloak.conf from template keycloak/keycloak.conf.j2.
  - TLS files: {{ keycloak_home }}/conf/ssl/keycloak.crt and .../keycloak.key copied from keycloak-ssl-certs/.
  - Hostname: keycloak_hostname (defaults to 10.0.2.10). Adjust to your DNS if needed.
  - Database: JDBC URL jdbc:postgresql://<db_host>:<db_port>/<db_name>, credentials set from play vars. The DB prep playbook grants required privileges (including USAGE, CREATE on public schema).
- Service management
  - Systemd unit: /etc/systemd/system/keycloak.service from keycloak/keycloak.service.j2.
  - ExecStart: {{ keycloak_home }}/bin/kc.sh start
  - Environment: KEYCLOAK_ADMIN and KEYCLOAK_ADMIN_PASSWORD set from play variables for first-run bootstrap.
  - Build step: kc.sh build is executed during provisioning to materialize config.
  - Logs: journalctl -u keycloak.
- Networking
  - HTTPS on port 8443 (set in keycloak.conf). The play waits for 127.0.0.1:8443 to be ready from the remote host to avoid firewall false negatives.
- Idempotency mechanisms
  - unarchive uses args: creates to avoid re-extraction when the version is already present.
  - Symlink creation only occurs when /opt/keycloak is absent, or is a symlink, or is an empty directory.
  - Templates and copy tasks are only marked changed when content differs.
  - Service start is only triggered when needed; daemon-reload is notified on unit changes.

If you need more detailed operational docs (backup, upgrade, multi-node clustering), open an issue and we’ll extend this README accordingly.
