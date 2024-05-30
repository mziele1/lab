#!/bin/bash


# wget the latest ubuntu cloud image and configure it as a template for pve
# also use cloud-init for basic user/ssh initialization
# see:
#   https://github.com/UntouchedWagons/Ubuntu-CloudInit-Docs
#   https://cloudinit.readthedocs.io/en/latest/reference/modules.html
#   https://github.com/canonical/cloud-init/tree/main/doc/examples


BUILD_DIR="./build/"
IMAGE_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
IMAGE_SIZE="64" # in GB
MEMORY_SIZE="8196" # in MB
CPU_CORES="4"
VM_ID="8001" # each template needs its own unique id
APT_MIRROR="http://linux.yz.yamagata-u.ac.jp/ubuntu/" # default http://archive.ubuntu.com/ubuntu/
ANSIBLE_PUBKEY_PATH="./ansible_ed25519.pub"


IMAGE_FILENAME=$(basename "$IMAGE_URL")
IMAGE_PATH="${BUILD_DIR}/${IMAGE_FILENAME}"
RELEASE="${IMAGE_FILENAME%%-*}"


# delete anything with a conflicting id
qm destroy "$VM_ID"
DESTROY_STATUS=$?
if [ $DESTROY_STATUS -ne 0 ] && [ $DESTROY_STATUS -ne 2 ]; then
    echo "Make sure to full clone/delete any linked clones"
    exit
fi

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
    --net0 virtio=BC:24:11:1A:27:97,bridge=vmbr0

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
  sources:
    docker.list:
      source: deb [arch=amd64] https://download.docker.com/linux/ubuntu $RELEASE stable
      keyid: 9DC858229FC7DD38854AE2D88D81803C0EBFCD88
packages:
  - qemu-guest-agent
  - dbus-user-session
  - uidmap
  - systemd-container
  - docker-ce
  - docker-ce-cli
  - docker-ce-rootless-extras
  - containerd.io
  - docker-buildx-plugin
  - docker-compose-plugin
  - acl
package_update: true
package_upgrade: true
package_reboot_if_required: true
ssh_pwauth: false
groups:
  docker
user:
  name: ansible
  gecos: Ansible User
  groups: sudo, docker
  sudo: ALL=(ALL) NOPASSWD:ALL
  shell: /bin/bash
  lock_passwd: true
  ssh_authorized_keys:
    - "$(cat "$ANSIBLE_PUBKEY_PATH")"
ansible:
  install_method: distro # https://bugs.launchpad.net/ubuntu/+source/cloud-init/+bug/2040291
  package_name: ansible
  run_user: ansible
EOF
cp itfun_network.yaml /var/lib/vz/snippets/
qm set "$VM_ID" --cicustom "network=local:snippets/itfun_network.yaml,vendor=local:snippets/vendor.yaml"
qm set "$VM_ID" --tags ubuntu-template,cloudinit
qm set "$VM_ID" --cipassword $(openssl passwd -6 testpassword)
qm set "$VM_ID" --ipconfig0 ip=dhcp
