# ansible-project
`
ansible-playbook vm-cluster-setup-enhanced.yml
`

ansible-playbook vm-cluster-control.yml -e vm_action=start 
ansible-playbook vm-cluster-control.yml -e vm_action=status 
ansible-playbook vm-cluster-control.yml -e vm_action=stop 

ansible-playbook vm-cluster-snapshots.yml -e action=restore -e snapshot=before-k8s-setup

ansible-playbook -i inventory.yml kubernetes-setup.yml

ansible-playbook vm-cluster-snapshots.yml -e action=delete -e snapshot=before-k8s-setup
ansible-playbook vm-cluster-snapshots.yml -e action=create -e snapshot=before-k8s-setup
ansible-playbook vm-cluster-snapshots.yml -e action=restore -e snapshot=before-k8s-setup


# Dashboard IDs to import:
15757  # Kubernetes Views - Pods
13332  # Kubernetes Pods  
315    # Kubernetes cluster monitoring
7249   # Kubernetes Cluster
1860   # Node Exporter Full


**Dashboard IDs:**
- `10000` - Kubernetes / API server
- `10001` - Kubernetes / Cluster
- `10002` - Kubernetes / Node
- `10003` - Kubernetes / Pod

