# Create backup directory
mkdir -p /root/proxmox-backup-$(date +%Y%m%d)
cd /root/proxmox-backup-$(date +%Y%m%d)

echo "=== Backing up Proxmox configuration ==="

# Backup PVE configuration
cp -r /etc/pve/ ./pve-config/

# Backup network configuration
cp /etc/network/interfaces ./interfaces
cp /etc/hosts ./hosts
cp /etc/hostname ./hostname

# Backup storage configuration
cp /etc/fstab ./fstab

# Backup SSH keys and config
cp -r /root/.ssh/ ./ssh-keys/ 2>/dev/null || echo "No SSH keys found"

# Backup cron jobs
crontab -l > ./root-crontab 2>/dev/null || echo "No crontab found"

# System info for restore reference
echo "=== System Information ===" > ./system-info.txt
uname -a >> ./system-info.txt
lsblk >> ./system-info.txt
pvs >> ./system-info.txt
vgs >> ./system-info.txt
lvs >> ./system-info.txt
df -h >> ./system-info.txt

echo "Backup created in: $(pwd)"


# Create compressed backup
cd /root/
tar -czf proxmox-backup-$(date +%Y%m%d-%H%M).tar.gz proxmox-backup-$(date +%Y%m%d)/

echo "=== Backup archive created ==="
ls -lah proxmox-backup-*.tar.gz
