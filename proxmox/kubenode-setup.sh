ansible-playbook -i inventory.ini proxmox-cloudimg.yml \
  -e vm_id=501 \
  -e vm_hostname=ub2404vm01srv01 \
  -e vm_ip_address=10.0.1.1 \
  -e vm_gateway=10.0.0.1 \
  -e netmask=16 \
  -e vm_memory=2048 \
  -e vm_cores=2 \
  -e vm_disk_size=64G



ansible-playbook -i inventory.ini proxmox-cloudimg.yml \
  -e vm_id=502 \
  -e vm_hostname=ub2404vm02srv01 \
  -e vm_ip_address=10.0.1.2 \
  -e vm_gateway=10.0.0.1 \
  -e netmask=16 \
  -e vm_memory=2048 \
  -e vm_cores=2 \
  -e vm_disk_size=64G



ansible-playbook -i inventory.ini proxmox-cloudimg.yml \
  -e vm_id=503 \
  -e vm_hostname=ub2404vm03srv01 \
  -e vm_ip_address=10.0.1.3 \
  -e vm_gateway=10.0.0.1 \
  -e netmask=16 \
  -e vm_memory=2048 \
  -e vm_cores=2 \
  -e vm_disk_size=64G

ansible-playbook -i inventory.ini proxmox-cloudimg.yml \
  -e vm_id=504 \
  -e vm_hostname=ub2404vm04srv01 \
  -e vm_ip_address=10.0.1.4 \
  -e vm_gateway=10.0.0.1 \
  -e netmask=16 \
  -e vm_memory=2048 \
  -e vm_cores=2 \
  -e vm_disk_size=64G

ansible-playbook -i inventory.ini proxmox-cloudimg.yml \
  -e vm_id=505 \
  -e vm_hostname=ub2404vm05srv01 \
  -e vm_ip_address=10.0.1.5 \
  -e vm_gateway=10.0.0.1 \
  -e netmask=16 \
  -e vm_memory=2048 \
  -e vm_cores=2 \
  -e vm_disk_size=64G

