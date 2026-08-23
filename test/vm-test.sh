#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../bash/common" && pwd)/logger.sh"

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
        --rocky)  OS_TYPE="rocky" ;;
        -h|--help) usage ;;
        *) printf "${ERROR}Unknown flag: %s\n" "$1"; usage ;;
    esac
    shift
done
[ -n "$OS_TYPE" ] || usage

# === Config (per-OS) ===
case "$OS_TYPE" in
    ubuntu) VM_NAME="Ubuntu24"; VM_USER="ubuntu"; VM_PASS="ubuntu" ;;
    rocky)  VM_NAME="Rocky10";  VM_USER="rocky";  VM_PASS="rocky"  ;;
esac
SNAPSHOT="clean-install"
SSH_PORT=2222
DOTFILES_REPO="https://github.com/jamesmatthewhamilton/Matthew-Configurations.git"

# === Cleanup trap (ensures VM is powered off on exit/Ctrl-C) ===
cleanup() { VBoxManage controlvm "$VM_NAME" poweroff 2>/dev/null || true; }
trap cleanup EXIT INT TERM

# === Dep checks ===
for cmd in VBoxManage sshpass; do
    command -v "$cmd" >/dev/null 2>&1 || {
        printf "${ERROR}%s not found. Run: bash test/vm-create.sh\n" "$cmd"
        exit 1
    }
done

# === Require VM + snapshot (vm-create.sh builds them) ===
if ! VBoxManage list vms | grep -q "\"${VM_NAME}\""; then
    printf "${ERROR}VM \"%s\" not found. Run: bash test/vm-create.sh\n" "$VM_NAME"
    exit 1
fi
if ! VBoxManage snapshot "$VM_NAME" list 2>/dev/null | grep -q "Name: ${SNAPSHOT}"; then
    printf "${ERROR}Snapshot \"%s\" missing. Run: bash test/vm-create.sh\n" "$SNAPSHOT"
    exit 1
fi

# === Restore clean state and start ===
printf "${INFO}Restoring snapshot \"%s\"\n" "$SNAPSHOT"
VBoxManage controlvm "$VM_NAME" poweroff 2>/dev/null || true
sleep 2
VBoxManage snapshot "$VM_NAME" restore "$SNAPSHOT"
VBoxManage startvm "$VM_NAME" --type headless

# === Wait for SSH (120s timeout) ===
printf "${INFO}Waiting for SSH...\n"
ELAPSED=0
while ! sshpass -p "$VM_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=3 -p $SSH_PORT "${VM_USER}@localhost" true 2>/dev/null; do
    sleep 3
    ELAPSED=$((ELAPSED + 3))
    if [ $ELAPSED -ge 120 ]; then
        printf "${ERROR}SSH did not come up within 120s.\n"
        exit 1
    fi
done
printf "${SUCCESS}VM ready.\n"

# === Clone dotfiles into VM ===
printf "${INFO}Cloning dotfiles inside VM\n"
sshpass -p "$VM_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -p $SSH_PORT "${VM_USER}@localhost" \
    "mkdir -p ~/Repos && cd ~/Repos && git clone $DOTFILES_REPO dotfiles"

# === Drop into interactive SSH at ~/Repos/dotfiles ===
printf "${HINT}Dropping into SSH. Run ./runonce/runonce.sh to test. Exit shell to power off VM.\n"
sshpass -p "$VM_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -p $SSH_PORT -t "${VM_USER}@localhost" "cd ~/Repos/dotfiles && exec bash --login"

printf "${INFO}SSH session ended. Powering off VM (via trap).\n"
