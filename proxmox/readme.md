ansible-playbook -i inventory-01.ini proxmox-cloudimg.yml \
  -e vm_id=601 \
  -e vm_hostname=db-server-proxy-01 \
  -e vm_ip_address=10.0.2.10 \
  -e vm_gateway=10.0.0.1 \
  -e netmask=16 \
  -e vm_memory=1024 \
  -e vm_cores=1 \
  -e vm_disk_size=16G


ansible-playbook -i inventory-02.ini proxmox-cloudimg.yml \
  -e vm_id=602 \
  -e vm_hostname=db-server-proxy-02 \
  -e vm_ip_address=10.0.2.30 \
  -e vm_gateway=10.0.0.1 \
  -e netmask=16 \
  -e vm_memory=1024 \
  -e vm_cores=1 \
  -e vm_disk_size=16G