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