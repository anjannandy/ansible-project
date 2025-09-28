gdisk /dev/nvme0n1
lsblk
fdisk -l

partprobe /dev/nvme0n1



ceph-volume lvm zap /dev/nvme0n1p4 --destroy
ceph-volume lvm create --data /dev/nvme0n1p4


ssh-copy-id -i ~/.ssh/id_rsa.pub root@10.0.0.4
ssh-copy-id -i ~/.ssh/id_rsa.pub root@10.0.0.5
ssh-copy-id -i ~/.ssh/id_rsa.pub root@10.0.0.6


mkdir -p /srv/nfs/hdd-bulk
mkdir -p /srv/nfs/ssd-fast

mount /dev/sda1 /srv/nfs/ssd-fast
mount /dev/sdb1 /srv/nfs/hdd-bulk


cat >> /etc/fstab << 'EOF'
# NFS Storage exports
/dev/sdb1    /srv/nfs/hdd-bulk   ext4    defaults    0    2
EOF

cat >> /etc/fstab << 'EOF'
# NFS Storage exports
/dev/sda1    /srv/nfs/ssd-fast   ext4    defaults    0    2
EOF


#Configure NFS exports for the cluster
cat > /etc/exports << 'EOF'
# NFS exports
/srv/nfs/ssd-fast    10.0.0.0/16(rw,sync,no_subtree_check,no_root_squash)
/srv/nfs/hdd-bulk    10.0.0.0/16(rw,sync,no_subtree_check,no_root_squash)
EOF

# Apply NFS configuration
exportfs -ra
systemctl restart nfs-kernel-server
systemctl enable nfs-kernel-server

echo "NFS server configured on server01"
exportfs -v
```


mount -t nfs server01:/srv/nfs/ssd-fast /srv/nfs/ssd-fast
mount -t nfs server01:/srv/nfs/hdd-bulk /srv/nfs/hdd-bulk

cat >> /etc/fstab << 'EOF'
server01:/srv/nfs/ssd-fast  /srv/nfs/ssd-fast  nfs  defaults,noatime  0 0
server01:/srv/nfs/hdd-bulk  /srv/nfs/hdd-bulk  nfs  defaults,noatime  0 0
EOF

rsync -aAXv / \
  --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} \
  /srv/nfs/hdd-bulk/server01/
  
 rsync -aAXv / /srv/nfs/hdd-bulk/server01/ --exclude=/srv/*



## Solution: Use Existing Keyrings
Since the bootstrap keys already exist, let's work with what you have:
### 1. Check Current Bootstrap Keys
``` bash
# On server01, check what bootstrap keys exist
ceph auth list | grep bootstrap
```



