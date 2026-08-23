#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../bash/common" && pwd)/logger.sh"

# === Pause helper ===
# Shows a hint about the next step. If running interactively, waits for
# Enter (continue) or q (quit). If stdin isn't a tty, just prints and continues.
pause() {
    printf "${HINT}%s\n" "$1"
    if [ -t 0 ]; then
        printf "${INFO}Press Enter to continue or q to quit: "
        local answer
        read -r answer
        case "$answer" in
            q|Q) printf "${INFO}Aborted by user.\n"; exit 0 ;;
        esac
    fi
}

# === Parse args (--ubuntu | --rocky required) ===
usage() {
    printf "${ERROR}Required flag: --ubuntu or --rocky\n"
    printf "${HINT}Usage: %s --ubuntu | --rocky\n" "$0"
    exit 1
}

OS_TYPE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --ubuntu) OS_TYPE="ubuntu" ;;
        --rocky)  OS_TYPE="rocky"  ;;
        -h|--help) usage ;;
        *) printf "${ERROR}Unknown flag: %s\n" "$1"; usage ;;
    esac
    shift
done
[ -n "$OS_TYPE" ] || usage

# === Architecture detection ===
case "$(uname -m)" in
    arm64|aarch64)
        UBUNTU_ARCH="arm64";  UBUNTU_OSTYPE="Ubuntu_arm64"
        ROCKY_ARCH="aarch64"; ROCKY_OSTYPE="RedHat10_arm64"
        ;;
    x86_64|amd64)
        UBUNTU_ARCH="amd64";  UBUNTU_OSTYPE="Ubuntu_64"
        ROCKY_ARCH="x86_64";  ROCKY_OSTYPE="RedHat10_64"
        ;;
    *) printf "${ERROR}unsupported architecture: %s\n" "$(uname -m)"; exit 1 ;;
esac

# === Per-OS config ===
# Cloud images are pre-installed disk images that boot in seconds (vs ~15min for
# an ISO autoinstall). Initial config (user, SSH, packages) is delivered via
# cloud-init's NoCloud datasource — a tiny ISO with a "cidata" volume label.
case "$OS_TYPE" in
    ubuntu)
        VM_NAME="Ubuntu24"
        # Ubuntu publishes the cloud image as .img but the file is qcow2 internally.
        # We save it with a .qcow2 extension so VBox's QCOW backend picks it up.
        IMAGE_URL="https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-${UBUNTU_ARCH}.img"
        IMAGE_FILE="ubuntu-24.04-server-cloudimg-${UBUNTU_ARCH}.qcow2"
        VBOX_OSTYPE="$UBUNTU_OSTYPE"
        VM_USER="ubuntu"
        VM_PASS="ubuntu"
        SUDO_GROUP="sudo"
        HOSTNAME_VM="ubuntu24"
        SSH_SERVICE="ssh"
        SNAPSHOT_DESCRIPTION="Ubuntu 24.04 cloud image, cloud-init done"
        ;;
    rocky)
        VM_NAME="Rocky10"
        IMAGE_URL="https://dl.rockylinux.org/pub/rocky/10/images/${ROCKY_ARCH}/Rocky-10-GenericCloud-Base.latest.${ROCKY_ARCH}.qcow2"
        IMAGE_FILE="Rocky-10-GenericCloud-Base.latest.${ROCKY_ARCH}.qcow2"
        VBOX_OSTYPE="$ROCKY_OSTYPE"
        VM_USER="rocky"
        VM_PASS="rocky"
        SUDO_GROUP="wheel"
        HOSTNAME_VM="rocky10"
        SSH_SERVICE="sshd"
        SNAPSHOT_DESCRIPTION="Rocky 10 cloud image, cloud-init done"
        ;;
esac

# === Common derived paths ===
VM_DIR="$HOME/VirtualBox VMs/${VM_NAME}"
IMAGE_SRC="$(dirname "$VM_DIR")/${IMAGE_FILE}"
VDI_PATH="${VM_DIR}/${VM_NAME}.vdi"
SEED_ISO="${VM_DIR}/seed.iso"
SNAPSHOT_NAME="clean-install"
SSH_PORT=2222
SSH="sshpass -p $VM_PASS ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $SSH_PORT ${VM_USER}@localhost"
RAM_MB=4096
CPUS=2
DISK_MB=25600

# === Ensure host dependencies ===
ensure_brew_pkg()  { brew list "$1" >/dev/null 2>&1 || brew install "$1"; }
ensure_brew_cask() { brew list --cask "$1" >/dev/null 2>&1 || brew install --cask "$1"; }

if [[ "$(uname -s)" != "Darwin" ]]; then
    printf "${ERROR}vm-create.sh currently supports macOS only.\n"
    exit 1
fi
if ! command -v brew >/dev/null 2>&1; then
    printf "${ERROR}Homebrew not found. Install it first:\n"
    printf "${HINT}/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"\n"
    exit 1
fi
if ! command -v VBoxManage >/dev/null 2>&1; then
    pause "Next: install VirtualBox via brew cask. macOS will pop a password dialog (sudo for the .pkg). On Apple Silicon you may also need to open System Settings → Privacy & Security and click 'Allow' for an Oracle system extension, then re-run this script."
    printf "${INFO}Installing VirtualBox...\n"
    ensure_brew_cask virtualbox
fi
command -v sshpass >/dev/null 2>&1 || { printf "${INFO}Installing sshpass...\n"; ensure_brew_pkg sshpass; }
command -v xorriso >/dev/null 2>&1 || { printf "${INFO}Installing xorriso...\n"; ensure_brew_pkg xorriso; }

# === Skip if VM already built ===
if VBoxManage list vms | grep -q "\"${VM_NAME}\"" \
   && VBoxManage snapshot "$VM_NAME" list 2>/dev/null | grep -q "Name: ${SNAPSHOT_NAME}"; then
    printf "${INFO}VM \"%s\" with snapshot \"%s\" already exists. Nothing to do.\n" "$VM_NAME" "$SNAPSHOT_NAME"
    printf "${HINT}Run vm-test.sh to use it, or delete the VM manually to rebuild.\n"
    exit 0
fi

# === Ensure cloud image present ===
if [ ! -f "$IMAGE_SRC" ]; then
    printf "${INFO}%s cloud image not found at %s\n" "$OS_TYPE" "$IMAGE_SRC"
    printf "${INFO}Downloading from %s\n" "$IMAGE_URL"
    mkdir -p "$(dirname "$IMAGE_SRC")"
    if ! curl -L --fail -o "${IMAGE_SRC}.partial" "$IMAGE_URL"; then
        rm -f "${IMAGE_SRC}.partial"
        printf "${ERROR}Cloud image download failed.\n"
        exit 1
    fi
    mv "${IMAGE_SRC}.partial" "$IMAGE_SRC"
fi

# === Cleanup any existing VM ===
printf "${INFO}Cleaning up any existing VM\n"
VBoxManage controlvm "$VM_NAME" poweroff 2>/dev/null || true
sleep 2
VBoxManage unregistervm "$VM_NAME" --delete 2>/dev/null || true
rm -rf "$VM_DIR"
mkdir -p "$VM_DIR"

# === Convert cloud image (qcow2) to VDI ===
# VBox's QCOW backend reads qcow2 natively, so clonemedium handles the conversion
# without needing qemu-img.
printf "${INFO}Cloning cloud image to VDI\n"
VBoxManage clonemedium "$IMAGE_SRC" "$VDI_PATH" --format VDI

printf "${INFO}Resizing VDI to %s MB\n" "$DISK_MB"
VBoxManage modifyhd "$VDI_PATH" --resize "$DISK_MB"

# === Generate cloud-init seed ISO ===
# NoCloud datasource: a tiny ISO with volume label "cidata" containing
# user-data + meta-data. cloud-init in the guest finds it on the attached DVD
# and runs once on first boot, then never again.
printf "${INFO}Building cloud-init seed ISO\n"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

cat > "$WORK_DIR/user-data" <<UDEOF
#cloud-config
hostname: ${HOSTNAME_VM}
users:
  - name: ${VM_USER}
    plain_text_passwd: ${VM_PASS}
    lock_passwd: false
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: [${SUDO_GROUP}]
ssh_pwauth: true
chpasswd:
  expire: false
package_update: true
packages:
  - git
  - curl
runcmd:
  - systemctl enable --now ${SSH_SERVICE}
UDEOF

cat > "$WORK_DIR/meta-data" <<MDEOF
instance-id: iid-local01
local-hostname: ${HOSTNAME_VM}
MDEOF

xorriso -as mkisofs \
    -output "$SEED_ISO" \
    -volid CIDATA \
    -joliet -rock \
    "$WORK_DIR/user-data" "$WORK_DIR/meta-data"

# === Create VM ===
printf "${INFO}Creating VM\n"
VBoxManage createvm --name "$VM_NAME" --ostype "$VBOX_OSTYPE" --basefolder "$(dirname "$VM_DIR")" --register

VBoxManage modifyvm "$VM_NAME" \
    --memory $RAM_MB \
    --cpus $CPUS \
    --vram 128 \
    --graphicscontroller vmsvga \
    --nic1 nat \
    --natpf1 "ssh,tcp,,${SSH_PORT},,22" \
    --boot1 disk \
    --boot2 dvd \
    --boot3 none \
    --boot4 none \
    --uart1 0x3F8 4 \
    --uartmode1 file "${VM_DIR}/serial.log"

VBoxManage storagectl "$VM_NAME" \
    --name "SATA" \
    --add sata \
    --controller IntelAhci \
    --portcount 2

VBoxManage storageattach "$VM_NAME" \
    --storagectl "SATA" --port 0 --device 0 \
    --type hdd --medium "$VDI_PATH"

VBoxManage storageattach "$VM_NAME" \
    --storagectl "SATA" --port 1 --device 0 \
    --type dvddrive --medium "$SEED_ISO"

# === Boot — cloud-init runs on first boot, then VM is ready ===
printf "${INFO}Booting VM (cloud-init configures user/SSH on first boot)\n"
printf "${HINT}Tail the serial console live: tail -f \"%s\"\n" "${VM_DIR}/serial.log"
VBoxManage startvm "$VM_NAME" --type headless

printf "${INFO}Waiting for SSH on localhost:%s (expect ~60-120s on first boot)...\n" "$SSH_PORT"
ELAPSED=0
while [ $ELAPSED -lt 300 ]; do
    if $SSH echo "SSH_READY" 2>/dev/null; then
        printf "${SUCCESS}SSH available after %ss.\n" "$ELAPSED"
        break
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

if [ $ELAPSED -ge 300 ]; then
    printf "${ERROR}SSH did not come up within 300s. Check %s\n" "${VM_DIR}/serial.log"
    exit 1
fi

# === Wait for cloud-init to finish ===
# SSH comes up early in cloud-init (after network + ssh modules), but later
# modules like `packages` install git/curl. Snapshotting before cloud-init
# completes leaves a half-configured system. `status --wait` blocks until done.
printf "${INFO}Waiting for cloud-init to complete (installs packages, etc.)...\n"
$SSH "sudo timeout 600 cloud-init status --wait" || {
    printf "${ERROR}cloud-init did not complete within 10 min. Status:\n"
    $SSH "sudo cloud-init status --long"
    exit 1
}

# === Verify ===
printf "${INFO}Verifying system\n"
$SSH <<VERIFY
echo "Kernel: \$(uname -a)"
echo "Disk:   \$(df -h / | tail -1)"
echo "SSH:    \$(systemctl is-active ${SSH_SERVICE})"
echo "User:   \$(whoami)"
echo "git:    \$(command -v git || echo MISSING)"
echo "curl:   \$(command -v curl || echo MISSING)"
VERIFY

# === Shut down + detach seed ISO + snapshot ===
printf "${INFO}Shutting down for snapshot\n"
$SSH "sudo shutdown -h now" 2>/dev/null || true

sleep 5
while true; do
    STATE=$(VBoxManage showvminfo "$VM_NAME" --machinereadable 2>/dev/null | grep '^VMState=' | cut -d'"' -f2)
    [ "$STATE" = "poweroff" ] && break
    sleep 3
done

# Detach seed ISO before snapshot — cloud-init doesn't re-run on subsequent boots,
# so the seed is no longer needed and shouldn't be referenced by the snapshot.
VBoxManage storageattach "$VM_NAME" \
    --storagectl "SATA" --port 1 --device 0 \
    --type dvddrive --medium emptydrive

VBoxManage snapshot "$VM_NAME" take "$SNAPSHOT_NAME" --description "$SNAPSHOT_DESCRIPTION"

echo ""
printf "${SUCCESS}Provisioning complete. Snapshot '%s' created.\n" "$SNAPSHOT_NAME"
printf "${HINT}Use vm-test.sh --%s to run tests from a clean state.\n" "$OS_TYPE"
