#!/usr/bin/env bash
# scripts/qemu-lab/qemu-lab.sh — per-VM QEMU lab for the 25-VM platform.
#
# Creates ONE real QEMU VM per platform VM, configures it with the matching
# Ansible playbooks, runs per-VM tests, then shuts it down. VMs are run
# strictly one at a time (RAM-friendly on a workstation).
#
# Usage:
#   ./qemu-lab.sh image          # download Ubuntu cloud image (once)
#   ./qemu-lab.sh run vm01       # full cycle: create+boot+config+test+shutdown
#   ./qemu-lab.sh all            # run every VM in order (1 at a time)
#   ./qemu-lab.sh status         # show running VMs
#   ./qemu-lab.sh shutdown vm01  # stop one VM (keep disk)
#   ./qemu-lab.sh cleanup        # stop all VMs and remove disks
#
# Advanced (step-by-step):
#   ./qemu-lab.sh create vm01    # disk + cloud-init seed
#   ./qemu-lab.sh boot vm01      # start QEMU (user-mode net, no root)
#   ./qemu-lab.sh config vm01    # run this VM's Ansible playbooks
#   ./qemu-lab.sh test vm01      # per-VM validation
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORK_DIR="$SCRIPT_DIR/work"
IMAGES_DIR="$SCRIPT_DIR/images"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -i ${SSH_KEY:-$HOME/.ssh/id_ed25519}"

# Load personal/secret config from repo root .env if present
if [ -f "$REPO_ROOT/.env" ]; then
  set -a; source "$REPO_ROOT/.env"; set +a
fi

# shellcheck source=vms.conf
source "$SCRIPT_DIR/vms.conf"

SSH_USER="${SSH_USER:-ubuntu}"
: "${SSH_KEY:=$HOME/.ssh/id_ed25519}"
: "${SSH_PUBKEY:=$HOME/.ssh/id_ed25519.pub}"

log() { echo -e "\033[1;34m[qemu-lab]\033[0m $*"; }
ok()  { echo -e "  \033[1;32m[PASS]\033[0m $*"; }
bad() { echo -e "  \033[1;31m[FAIL]\033[0m $*"; }

vm_name()  { echo "$1" | cut -d'|' -f1; }
vm_host()  { echo "$1" | cut -d'|' -f2; }
vm_role()  { echo "$1" | cut -d'|' -f3; }
vm_ram()   { echo "$1" | cut -d'|' -f4; }
vm_vcpu()  { echo "$1" | cut -d'|' -f5; }
vm_ssh()   { echo "$1" | cut -d'|' -f6; }
vm_pb()    { echo "$1" | cut -d'|' -f7; }

# Ansible groups per VM (mirrors scripts/generate-inventory.py VM_ROLE_GROUPS)
vm_groups() {
  case "$1" in
    vm01) echo "bastion" ;;
    vm02) echo "mgmt terraform" ;;
    vm03) echo "mgmt ansible" ;;
    vm04) echo "mgmt git" ;;
    vm05) echo "mgmt jenkins jenkins_master" ;;
    vm06|vm07) echo "mgmt jenkins jenkins_agent" ;;
    vm08|vm09|vm10) echo "k8s k8s_control_plane" ;;
    vm11|vm12|vm13|vm14|vm15|vm16) echo "k8s k8s_workers" ;;
    vm17) echo "data postgresql postgresql_primary" ;;
    vm18) echo "data postgresql postgresql_replica" ;;
    vm19) echo "monitoring prometheus" ;;
    vm20) echo "monitoring grafana" ;;
    vm21) echo "infra loadbalancers nginx_lb" ;;
    vm22) echo "infra loadbalancers haproxy_lb" ;;
    vm23|vm24) echo "apps standalone" ;;
    vm25) echo "apps standalone staging" ;;
  esac
}

get_vm() { # name -> full line
  local name="$1"
  for v in "${VMS[@]}"; do
    [[ "$(vm_name "$v")" == "$name" ]] && { echo "$v"; return 0; }
  done
  return 1
}

vm_running() { # name -> 0 if running
  local name="$1"
  pgrep -f "qemu-system.*${WORK_DIR}/${name}" >/dev/null 2>&1
}

ssh_cmd() { # name cmd...
  local name="$1"; shift
  local port; port="$(vm_ssh "$(get_vm "$name")")"
  ssh $SSH_OPTS -p "$port" "$SSH_USER@127.0.0.1" "$@"
}

wait_ssh() { # name, up to N seconds
  local name="$1" n="${2:-180}" i=0
  local port; port="$(vm_ssh "$(get_vm "$name")")"
  while ! ssh $SSH_OPTS -p "$port" "$SSH_USER@127.0.0.1" true >/dev/null 2>&1; do
    sleep 5; i=$((i+5))
    [[ "$i" -ge "$n" ]] && { log "timeout waiting for SSH on $name"; return 1; }
  done
  log "$name SSH up (${i}s)"
}

cmd_image() {
  mkdir -p "$IMAGES_DIR" "$WORK_DIR"
  if [[ -f "$IMAGES_DIR/$BASE_IMAGE" ]]; then
    log "base image already present: $IMAGES_DIR/$BASE_IMAGE"
    return 0
  fi
  log "downloading $IMAGE_URL ..."
  curl -L -o "$IMAGES_DIR/$BASE_IMAGE" "$IMAGE_URL"
  [[ -f "$SSH_PUBKEY" ]] || { log "ERROR: no ssh pubkey at $SSH_PUBKEY"; exit 1; }
  log "image ready"
}

cmd_create() {
  local name="$1" line vm host
  line="$(get_vm "$name")" || { log "unknown VM '$name'"; exit 1; }
  vm="$(vm_name "$line")"; host="$(vm_host "$line")"
  mkdir -p "$WORK_DIR" "$IMAGES_DIR"
  [[ -f "$IMAGES_DIR/$BASE_IMAGE" ]] || { log "run: $0 image first"; exit 1; }
  [[ -f "$SSH_PUBKEY" ]] || { log "ERROR: no ssh pubkey at $SSH_PUBKEY"; exit 1; }

  if [[ ! -f "$WORK_DIR/$vm.qcow2" ]]; then
    log "creating disk $vm.qcow2 (overlay on base image)"
    qemu-img create -f qcow2 -F qcow2 -b "$IMAGES_DIR/$BASE_IMAGE" "$WORK_DIR/$vm.qcow2" 20G >/dev/null
  fi

  log "writing cloud-init seed for $vm ($host)"
  local seed="$WORK_DIR/$vm-seed"
  rm -rf "$seed"; mkdir -p "$seed"
  cat > "$seed/user-data" <<EOF
#cloud-config
hostname: $host
manage_etc_hosts: true
users:
  - name: $SSH_USER
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - $(cat "$SSH_PUBKEY")
ssh_pwauth: false
package_update: false
package_upgrade: false
EOF
  cat > "$seed/meta-data" <<EOF
instance-id: $vm
local-hostname: $host
EOF
  genisoimage -quiet -output "$WORK_DIR/$vm-seed.iso" -volid cidata -joliet -rock "$seed" >/dev/null 2>&1
  log "created $vm"
}

cmd_boot() {
  local name="$1" line vm ram vcpu ssh
  line="$(get_vm "$name")" || { log "unknown VM '$name'"; exit 1; }
  vm="$(vm_name "$line")"; ram="$(vm_ram "$line")"; vcpu="$(vm_vcpu "$line")"; ssh="$(vm_ssh "$line")"
  [[ -f "$WORK_DIR/$vm.qcow2" ]] || { log "run: $0 create $vm first"; exit 1; }
  if vm_running "$vm"; then log "$vm already running"; return 0; fi

  log "booting $vm (${ram}MB, ${vcpu} vcpu, ssh -> 127.0.0.1:$ssh)"
  nohup qemu-system-x86_64 \
    -name "$vm" \
    -machine accel=kvm -cpu host -smp "$vcpu" -m "$ram" \
    -drive file="$WORK_DIR/$vm.qcow2",if=virtio,format=qcow2 \
    -drive file="$WORK_DIR/$vm-seed.iso",if=virtio,media=cdrom,format=raw \
    -netdev user,id=net0,hostfwd=tcp::"$ssh"-:22 \
    -device virtio-net-pci,netdev=net0 \
    -serial file:"$WORK_DIR/$vm-console.log" \
    -display none -daemonize -pidfile "$WORK_DIR/$vm.pid" >/dev/null 2>&1
  wait_ssh "$vm" 300
}

cmd_config() {
  local name="$1" line vm pb
  line="$(get_vm "$name")" || { log "unknown VM '$name'"; exit 1; }
  vm="$(vm_name "$line")"; pb="$(vm_pb "$line")"
  vm_running "$vm" || { log "$vm not running"; exit 1; }

  log "writing per-VM ansible inventory"
  local inv="$REPO_ROOT/ansible/inventory/qemu-$vm.ini"
  {
    echo "[all:vars]"
    echo "ansible_user=$SSH_USER"
    echo "ansible_ssh_private_key_file=$SSH_KEY"
    echo ""
    local g
    for g in $(vm_groups "$vm"); do
      echo "[$g]"
      echo "$vm ansible_host=127.0.0.1 ansible_port=$(vm_ssh "$line")"
      echo ""
    done
    echo "[$vm]"
    echo "$vm ansible_host=127.0.0.1 ansible_port=$(vm_ssh "$line")"
  } > "$inv"

  local playbook
  for playbook in $pb; do
    log "running $playbook on $vm"
    cd "$REPO_ROOT/ansible"
    ansible-playbook -i "$inv" "playbooks/$playbook" --diff || {
      bad "playbook $playbook failed on $vm (HA-only steps may need multi-VM mode)"
    }
  done
}

cmd_test() {
  local name="$1" line vm host role
  line="$(get_vm "$name")" || { log "unknown VM '$name'"; exit 1; }
  vm="$(vm_name "$line")"; host="$(vm_host "$line")"; role="$(vm_role "$line")"
  vm_running "$vm" || { log "$vm not running"; exit 1; }

  local PASS=0 FAIL=0
  ok_local() { ok "$1"; PASS=$((PASS+1)); }
  bad_local() { bad "$1"; FAIL=$((FAIL+1)); }

  log "=== $vm ($host) — $role ==="

  if ssh_cmd "$vm" 'true' 2>/dev/null; then ok_local "ssh reachable (127.0.0.1:$(vm_ssh "$line"))"; else bad_local "ssh unreachable"; fi

  local hostname_ok
  hostname_ok=$(ssh_cmd "$vm" 'hostname' 2>/dev/null || true)
  [[ "$hostname_ok" == "$host" ]] && ok_local "hostname=$host" || bad_local "hostname=$hostname_ok (want $host)"

  case "$vm" in
    vm01) ;;
    vm02) ssh_cmd "$vm" 'command -v terraform >/dev/null && terraform version | head -1' >/dev/null 2>&1 && ok_local "terraform installed" || bad_local "terraform missing (installed by hand, not ansible role)";;
    vm03) ssh_cmd "$vm" 'command -v ansible-playbook >/dev/null && ansible --version | head -1' >/dev/null 2>&1 && ok_local "ansible installed" || bad_local "ansible missing (installed by hand, not ansible role)";;
    vm04) ssh_cmd "$vm" 'command -v git >/dev/null && git --version' >/dev/null 2>&1 && ok_local "git installed" || bad_local "git missing";;
    vm05) ssh_cmd "$vm" 'systemctl is-active jenkins' 2>/dev/null | grep -q active && ok_local "jenkins service active" || bad_local "jenkins inactive";;
    vm06|vm07) ssh_cmd "$vm" 'systemctl is-active docker' 2>/dev/null | grep -q active && ok_local "docker active" || bad_local "docker inactive"; ssh_cmd "$vm" 'command -v java >/dev/null && java -version 2>&1 | head -1' >/dev/null 2>&1 && ok_local "java installed (agent runtime)" || bad_local "java missing";;
    vm08|vm09|vm10) ssh_cmd "$vm" 'command -v kubeadm >/dev/null && kubeadm version -o short' >/dev/null 2>&1 && ok_local "kubeadm installed" || bad_local "kubeadm missing"; ssh_cmd "$vm" 'command -v kubectl >/dev/null' >/dev/null 2>&1 && ok_local "kubectl installed" || bad_local "kubectl missing";;
    vm11|vm12|vm13|vm14|vm15|vm16) ssh_cmd "$vm" 'command -v kubeadm >/dev/null && kubeadm version -o short' >/dev/null 2>&1 && ok_local "kubeadm installed" || bad_local "kubeadm missing";;
    vm17) ssh_cmd "$vm" 'pg_isready -h localhost -U app1 >/dev/null 2>&1' 2>/dev/null && ok_local "postgres ready" || bad_local "postgres not ready"; ssh_cmd "$vm" "psql -U app1 -d app1 -tAc 'SHOW wal_level'" 2>/dev/null | grep -q replica && ok_local "wal_level=replica" || bad_local "wal_level != replica";;
    vm18) ssh_cmd "$vm" 'pg_isready -h localhost -U app1 >/dev/null 2>&1' 2>/dev/null && ok_local "postgres ready" || bad_local "postgres not ready (needs primary for basebackup)";;
    vm19) ssh_cmd "$vm" 'curl -sf http://localhost:9090/-/ready >/dev/null' 2>/dev/null && ok_local "prometheus /-/ready" || bad_local "prometheus not ready";;
    vm20) ssh_cmd "$vm" 'curl -sf http://localhost:3000/api/health >/dev/null' 2>/dev/null && ok_local "grafana /api/health" || bad_local "grafana not ready";;
    vm21) ssh_cmd "$vm" 'curl -sf http://localhost/healthz >/dev/null' 2>/dev/null && ok_local "nginx /healthz" || bad_local "nginx not serving";;
    vm22) ssh_cmd "$vm" 'haproxy -c -f /etc/haproxy/haproxy.cfg >/dev/null 2>&1' 2>/dev/null && ok_local "haproxy config valid" || bad_local "haproxy config invalid"; ssh_cmd "$vm" 'curl -sf http://localhost:9000/stats >/dev/null' 2>/dev/null && ok_local "haproxy stats :9000" || bad_local "haproxy stats unreachable";;
    vm23|vm24|vm25) ssh_cmd "$vm" 'systemctl is-active docker' 2>/dev/null | grep -q active && ok_local "docker active" || bad_local "docker inactive";;
  esac

  echo "  => $vm: $PASS passed, $FAIL failed"
  return 0
}

cmd_shutdown() {
  local name="$1" line vm
  line="$(get_vm "$name")" || { log "unknown VM '$name'"; exit 1; }
  vm="$(vm_name "$line")"
  vm_running "$vm" || { log "$vm not running"; return 0; }
  log "shutting down $vm (graceful, up to 60s)"
  ssh_cmd "$vm" 'sudo shutdown -h now' >/dev/null 2>&1 || true
  for _ in $(seq 1 12); do
    vm_running "$vm" || break
    sleep 5
  done
  if vm_running "$vm"; then
    log "$vm did not stop gracefully, killing"
    [[ -f "$WORK_DIR/$vm.pid" ]] && kill "$(cat "$WORK_DIR/$vm.pid")" 2>/dev/null || true
    sleep 3
  fi
  rm -f "$WORK_DIR/$vm.pid"
  log "$vm stopped"
}

cmd_run() {
  local name="$1"
  log "=== full cycle for $name ==="
  cmd_create "$name"
  cmd_boot "$name"
  cmd_config "$name"
  cmd_test "$name"
  cmd_shutdown "$name"
  log "=== $name done ==="
}

cmd_all() {
  local name line
  local done_file="$WORK_DIR/run-progress.txt"
  : > "$done_file"
  for v in "${VMS[@]}"; do
    name="$(vm_name "$v")"
    if grep -q "^$name$" "$done_file" 2>/dev/null; then
      log "skip $name (already done)"
      continue
    fi
    log "========== $name / ${#VMS[@]} VMs total =========="
    cmd_run "$name" || log "!! $name failed, continuing"
    echo "$name" >> "$done_file"
  done
  log "ALL VMs done"
}

cmd_status() {
  local any=0
  for v in "${VMS[@]}"; do
    local name; name="$(vm_name "$v")"
    if vm_running "$name"; then
      echo "$name: RUNNING (ssh 127.0.0.1:$(vm_ssh "$v"))"
      any=1
    fi
  done
  [[ "$any" -eq 0 ]] && echo "no VMs running"
}

cmd_cleanup() {
  local name
  for v in "${VMS[@]}"; do
    name="$(vm_name "$v")"
    vm_running "$name" && cmd_shutdown "$name"
  done
  log "removing VM disks"
  rm -f "$WORK_DIR"/*.qcow2 "$WORK_DIR"/*-seed.iso "$WORK_DIR"/*.pid
  rm -rf "$WORK_DIR"/*-seed
  rm -f "$REPO_ROOT/ansible/inventory"/qemu-*.ini
  log "cleanup done"
}

case "${1:-}" in
  image)    cmd_image ;;
  create)   cmd_create "$2" ;;
  boot)     cmd_boot "$2" ;;
  config)   cmd_config "$2" ;;
  test)     cmd_test "$2" ;;
  shutdown) cmd_shutdown "$2" ;;
  run)      cmd_run "$2" ;;
  all)      cmd_all ;;
  status)   cmd_status ;;
  cleanup)  cmd_cleanup ;;
  *)
    sed -n '2,20p' "$0" | sed 's/^# //'
    exit 1
    ;;
esac