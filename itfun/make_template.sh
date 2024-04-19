#!/bin/bash


# wget the latest ubuntu cloud image and configure it as a template for pve
# also use cloud-init for basic user/ssh initialization
# see:
#   https://github.com/UntouchedWagons/Ubuntu-CloudInit-Docs


BUILD_DIR="./build/"
IMAGE_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
IMAGE_SIZE="64" # in GB
MEMORY_SIZE="8196" # in MB
CPU_CORES="4"
VM_ID="8001" # each template needs its own unique id
APT_MIRROR="http://linux.yz.yamagata-u.ac.jp/ubuntu/" # default http://archive.ubuntu.com/ubuntu/


IMAGE_FILENAME=$(basename "$IMAGE_URL")
IMAGE_PATH="${BUILD_DIR}/${IMAGE_FILENAME}"


# delete anything with a conflicting id
qm destroy "$VM_ID"
mkdir -p "$BUILD_DIR"
#wget "$IMAGE_URL" -P "$BUILD_DIR"
cp "$IMAGE_FILENAME" "$BUILD_DIR"
# resize storage
qemu-img resize "$IMAGE_PATH" "$IMAGE_SIZE"G
 
# initialize vm settings
qm create "$VM_ID" --name "itfun-ubuntu-cloudinit-template" --ostype l26 \
    --memory "$MEMORY_SIZE" \
    --agent 1 \
    --bios ovmf --machine q35 --efidisk0 local-zfs:0,pre-enrolled-keys=0 \
    --cpu host --socket 1 --cores "$CPU_CORES" \
    --vga serial0 --serial0 socket  \
    --net0 virtio,bridge=vmbr0

# configure disk/image/boot
qm importdisk "$VM_ID" "$IMAGE_PATH" local-zfs
qm set "$VM_ID" --scsihw virtio-scsi-pci --virtio0 local-zfs:vm-"$VM_ID"-disk-1,discard=on
qm set "$VM_ID" --ide2 local-zfs:cloudinit
qm set "$VM_ID" --boot order=virtio0

# customize cloud-init
mkdir -p /var/lib/vz/snippets # may not exist
cat << EOF | tee /var/lib/vz/snippets/vendor.yaml
#cloud-config
apt:
  primary:
    - arches: [default]
      uri: "$APT_MIRROR"
packages:
  - qemu-guest-agent
package_update: true
package_upgrade: true
package_reboot_if_required: true
EOF
qm set "$VM_ID" --cicustom "vendor=local:snippets/vendor.yaml"
qm set "$VM_ID" --tags ubuntu-template,cloudinit
qm set "$VM_ID" --ciuser test
qm set "$VM_ID" --cipassword $(openssl passwd -6 testpassword)
qm set "$VM_ID" --sshkeys ~/.ssh/authorized_keys
qm set "$VM_ID" --ipconfig0 ip=dhcp
qm template "$VM_ID"
