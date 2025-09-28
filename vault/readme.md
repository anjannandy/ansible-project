ansible-playbook -i inventory-01.ini proxmox-cloudimg.yml \
  -e vm_id=301 \
  -e vm_hostname=vault-01 \
  -e vm_ip_address=10.0.2.41 \
  -e vm_gateway=10.0.0.1 \
  -e netmask=16 \
  -e vm_memory=1024 \
  -e vm_cores=1 \
  -e vm_disk_size=16G

ansible-playbook -i inventory-02.ini proxmox-cloudimg.yml \
  -e vm_id=302 \
  -e vm_hostname=vault-02 \
  -e vm_ip_address=10.0.2.42 \
  -e vm_gateway=10.0.0.1 \
  -e netmask=16 \
  -e vm_memory=1024 \
  -e vm_cores=1 \
  -e vm_disk_size=16G

ansible-playbook -i inventory-02.ini proxmox-cloudimg.yml \
  -e vm_id=303 \
  -e vm_hostname=vault-03 \
  -e vm_ip_address=10.0.2.43 \
  -e vm_gateway=10.0.0.1 \
  -e netmask=16 \
  -e vm_memory=1024 \
  -e vm_cores=1 \
  -e vm_disk_size=16G


ansible-playbook -i inventory-01.ini proxmox-cloudimg.yml \
  -e vm_id=300 \
  -e vm_hostname=vault.homelab.com \
  -e vm_ip_address=10.0.2.40 \
  -e vm_gateway=10.0.0.1 \
  -e netmask=16 \
  -e vm_memory=256 \
  -e vm_cores=1 \
  -e vm_disk_size=4G


ansible-playbook -i inventory.ini vault-setup.yaml

ansible -i inventory.ini vault_nodes -b -m systemd -a "name=vault state=stopped"

ansible -i inventory.ini vault_nodes -b -m systemd -a "name=vault state=started"

ansible-playbook -i inventory.ini vault-setup.yaml --tags install

ansible-playbook -i inventory.ini vault-setup.yaml --tags install,configure

ansible -i inventory.ini 'vault_nodes[0]' -m uri -a "
  url=http://{{ ansible_host }}:8200/v1/sys/health
  method=GET
  status_code=[200,429,472,501,503]
"

ansible-playbook -i inventory.ini vault-setup.yaml --tags init

ansible -i inventory.ini 'vault_nodes[1:]' -b -m systemd -a "name=vault state=started"



# Only initialization and unsealing
ansible-playbook -i inventory.ini vault-setup.yaml --tags init,unseal


ansible -i inventory.ini vault_nodes -b -m shell -a "systemctl status vault --no-pager -l"

ansible-playbook -i inventory.ini vault-auto-unseal.yml


ansible -i inventory.ini vault-01 -b -m shell -a "systemctl restart vault"

# Wait 30 seconds, then check status
sleep 30
ansible -i inventory.ini vault-01 -m shell -a "curl -s http://localhost:8200/v1/sys/seal-status | jq '.sealed'"

# Check auto-unseal logs
ansible -i inventory.ini vault-01 -b -m shell -a "tail -20 /var/log/vault-auto-unseal.log"

#Manual Unseal

ansible -i inventory.ini vault-01 -m shell -a "
curl -X POST -H 'Content-Type: application/json' -d '{\"key\": \"\"}' http://localhost:8200/v1/sys/unseal &&
curl -X POST -H 'Content-Type: application/json' -d '{\"key\": \""}' http://localhost:8200/v1/sys/unseal &&
curl -X POST -H 'Content-Type: application/json' -d '{\"key\": \"\"}' http://localhost:8200/v1/sys/unseal
"

# 1. First, try the manual unseal to verify our keys work
ansible-playbook -i inventory.ini manual-unseal.yml

# 2. If that works, deploy the fixed auto-unseal script
ansible-playbook -i inventory.ini vault-auto-unseal-fixed.yml


# Method 2: If that fails, restart PostgreSQL and use the emergency playbook
ansible-playbook -i inventory.ini emergency-manual-unseal.yml

