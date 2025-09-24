### **Step 1: Setup DB only**
ansible-playbook -i inventory.ini vault-db-setup.yml

### **Step 2: Setup HTTP vault only**
ansible-playbook -i inventory.ini vault-setup.yml

### **Step 3: Unseal All**
ansible-playbook -i inventory.ini vault-manual-unseal.yml

### **Step 1: Setup directories only**
ansible-playbook -i inventory.ini vault-https-setup.yml --tags step1

### **Step 2: Check Vault status**
ansible-playbook -i inventory.ini vault-https-setup.yml --tags step2

### **Step 3: Generate certificates (requires unsealed Vault)**
ansible-playbook -i inventory.ini vault-https-setup.yml --tags step3 -e vault_root_token="YOUR_ROOT_TOKEN_HERE"

### **Step 4: Configure Vault for HTTPS**
ansible-playbook -i inventory.ini vault-https-setup.yml --tags step4

### **Step 5: Stop Vault services**
ansible-playbook -i inventory.ini vault-https-setup.yml --tags step5

### **Step 6: Start Vault with HTTPS**
ansible-playbook -i inventory.ini vault-https-setup.yml --tags step6


### **Step 7: Verify HTTPS is working**
ansible-playbook -i inventory.ini vault-https-setup.yml --tags step7

## Run All Steps at Once:
ansible-playbook -i inventory.ini vault-https-modular.yml -e vault_root_token="YOUR_ROOT_TOKEN_HERE"


## Run Specific Combinations:
ansible-playbook -i inventory.ini vault-https-modular.yml --tags "step1,step2,step3" -e vault_root_token="YOUR_ROOT_TOKEN_HERE"

## 
ansible-playbook -i inventory.ini vault-manual-https-unseal.yml 

