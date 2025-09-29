ansible-playbook -i inventory-01.ini proxmox-cloudimg.yml \
  -e vm_id=200 \
  -e vm_hostname=kube-master \
  -e vm_ip_address=10.0.1.0 \
  -e vm_gateway=10.0.0.1 \
  -e netmask=16 \
  -e vm_memory=4096 \
  -e vm_cores=4 \
  -e vm_disk_size=64G


ansible-playbook -i inventory-02.ini proxmox-cloudimg.yml \
  -e vm_id=201 \
  -e vm_hostname=kube-worker01 \
  -e vm_ip_address=10.0.1.1 \
  -e vm_gateway=10.0.0.1 \
  -e netmask=16 \
  -e vm_memory=2048 \
  -e vm_cores=4 \
  -e vm_disk_size=64G


ansible-playbook -i inventory-02.ini proxmox-cloudimg.yml \
  -e vm_id=202 \
  -e vm_hostname=kube-worker02 \
  -e vm_ip_address=10.0.1.2 \
  -e vm_gateway=10.0.0.1 \
  -e netmask=16 \
  -e vm_memory=2048 \
  -e vm_cores=4 \
  -e vm_disk_size=64G


ansible-playbook -i inventory-03.ini proxmox-cloudimg.yml \
  -e vm_id=203 \
  -e vm_hostname=kube-worker03 \
  -e vm_ip_address=10.0.1.3 \
  -e vm_gateway=10.0.0.1 \
  -e netmask=16 \
  -e vm_memory=2048 \
  -e vm_cores=4 \
  -e vm_disk_size=64G

ansible-playbook -i inventory-03.ini proxmox-cloudimg.yml \
  -e vm_id=204 \
  -e vm_hostname=kube-worker04 \
  -e vm_ip_address=10.0.1.4 \
  -e vm_gateway=10.0.0.1 \
  -e netmask=16 \
  -e vm_memory=2048 \
  -e vm_cores=4 \
  -e vm_disk_size=64G