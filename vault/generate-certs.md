## Usage Examples:
Save this as `generate-cert.yml` and use it as follows:
### Basic Usage:
``` bash
ansible-playbook generate-cert.yml \
  -e cert_hostname="myserver.local" \
  -e cert_ip="192.168.1.50" \
  -e cert_output_dir="./certs/myserver" \
  -e vault_root_token="YOUR_VAULT_TOKEN"
```
### Advanced Usage with Custom Vault Server:
``` bash
ansible-playbook generate-cert.yml \
  -e cert_hostname="webserver.example.com" \
  -e cert_ip="10.0.1.100" \
  -e cert_output_dir="/tmp/certs/webserver" \
  -e vault_server_host="vault.company.com" \
  -e vault_server_port="8200" \
  -e vault_root_token="YOUR_VAULT_TOKEN"
```
### Run Only Specific Steps:
``` bash
# Just validate and check vault
ansible-playbook generate-cert.yml --tags "validate,check-vault" \
  -e cert_hostname="test.local" -e cert_ip="127.0.0.1" -e cert_output_dir="./test"

# Generate and save only
ansible-playbook generate-cert.yml --tags "generate,save-files" \
  -e cert_hostname="api.local" -e cert_ip="10.0.1.50" \
  -e cert_output_dir="./api-certs" -e vault_root_token="TOKEN"
```
## Key Features:
1. **Standalone Script**: Works independently without requiring the original playbook infrastructure
2. **Flexible Parameters**: Hostname, IP, and output directory are configurable
3. **Local Storage**: Saves all certificates to a local directory on the machine running Ansible
4. **Multiple Formats**: Generates individual files plus a bundle for easy deployment
5. **Comprehensive Validation**: Checks Vault connectivity and status before proceeding
6. **Detailed Output**: Provides clear success/failure messages with usage examples
7. **File Organization**: Creates organized certificate files with descriptive names
8. **Documentation**: Generates an info file with all certificate details

The script will create files like:
- `myserver-cert.pem` (certificate)
- `myserver-key.pem` (private key)
- `myserver-ca.pem` (CA certificate)
- `myserver-bundle.pem` (certificate + CA bundle)
- `myserver-info.txt` (certificate information)


ansible-playbook generate-cert.yml --tags "generate,save-files" \
  -e cert_hostname="api.local" -e cert_ip="10.0.1.50" \
  -e cert_output_dir="./api-certs" -e vault_root_token="TOKEN"