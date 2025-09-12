ansible-playbook -i inventory.ini proxmox-cloudimg.yml \
  -e vm_id=505 \
  -e vm_hostname=dbserver01 \
  -e vm_ip_address=10.0.1.11 \
  -e vm_gateway=10.0.0.1 \
  -e netmask=16 \
  -e vm_memory=8192 \
  -e vm_cores=6 \
  -e vm_disk_size=500G
