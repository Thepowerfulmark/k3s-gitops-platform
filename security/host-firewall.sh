#!/usr/bin/env bash
# IPv4 host firewall for a single-node k3s machine.
# Own chain, inserted at the head of INPUT, with a rollback timer.
# Pod and service ranges below are the k3s defaults: 10.42.0.0/16 and 10.43.0.0/16.
set -euo pipefail

CHAIN="${CHAIN:-PLATFORM-IN}"
ADMIN_CIDR="${ADMIN_CIDR:-}"
ROLLBACK_SECONDS="${ROLLBACK_SECONDS:-300}"
STATE_DIR="${STATE_DIR:-/var/lib/k3s-gitops-platform/firewall}"
POD_CIDR="${POD_CIDR:-10.42.0.0/16}"
SERVICE_CIDR="${SERVICE_CIDR:-10.43.0.0/16}"
UI_PORTS="${UI_PORTS:-30080,30081,30082}"
API_PORT="${API_PORT:-6443}"
SSH_PORT="${SSH_PORT:-22}"
DEST="/usr/local/sbin/k3s-gitops-firewall.sh"

usage() {
  cat <<'EOF'
usage: host-firewall.sh check|apply|apply-persistent|commit|rollback|remove

check             validate inputs and exit
apply             save current rules, install the chain, start the rollback timer
apply-persistent  install the chain without a timer (used at boot after commit)
commit            cancel the timer and enable the boot service
rollback          restore the rules saved by apply
remove            delete the chain and the boot service

Set ADMIN_CIDR to the admin network. The placeholder admin-cidr-here is rejected.
EOF
}

die() {
  echo "$1" >&2
  exit 1
}

is_cidr() {
  [[ "$1" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$ ]]
}

validate() {
  [[ -n "${ADMIN_CIDR}" ]] || die "set ADMIN_CIDR"
  [[ "${ADMIN_CIDR}" != "admin-cidr-here" ]] || die "replace ADMIN_CIDR"
  is_cidr "${ADMIN_CIDR}" || die "ADMIN_CIDR must be an IPv4 CIDR"
  [[ "${ADMIN_CIDR}" != "0.0.0.0/0" ]] || die "ADMIN_CIDR is too wide"
  is_cidr "${POD_CIDR}" || die "POD_CIDR must be an IPv4 CIDR"
  is_cidr "${SERVICE_CIDR}" || die "SERVICE_CIDR must be an IPv4 CIDR"
  [[ "${CHAIN}" =~ ^[A-Z0-9-]+$ ]] || die "CHAIN has unexpected characters"
  [[ "${UI_PORTS}" =~ ^[0-9]+(,[0-9]+)*$ ]] || die "UI_PORTS must be a comma-separated list"
  [[ "${SSH_PORT}" =~ ^[0-9]+$ && "${API_PORT}" =~ ^[0-9]+$ ]] || die "ports must be numeric"
  [[ "${ROLLBACK_SECONDS}" =~ ^[0-9]+$ ]] || die "ROLLBACK_SECONDS must be a number"
  if (( ROLLBACK_SECONDS < 30 || ROLLBACK_SECONDS > 3600 )); then
    die "ROLLBACK_SECONDS must be between 30 and 3600"
  fi
}

require_root() {
  [[ "$(id -u)" -eq 0 ]] || die "run as root"
}

write_env() {
  umask 077
  mkdir -p "${STATE_DIR}"
  cat > "${STATE_DIR}/firewall.env" <<EOF
ADMIN_CIDR=${ADMIN_CIDR}
POD_CIDR=${POD_CIDR}
SERVICE_CIDR=${SERVICE_CIDR}
UI_PORTS=${UI_PORTS}
API_PORT=${API_PORT}
SSH_PORT=${SSH_PORT}
CHAIN=${CHAIN}
ROLLBACK_SECONDS=${ROLLBACK_SECONDS}
EOF
}

install_self() {
  mkdir -p /usr/local/sbin
  local src
  src="$(readlink -f "$0")"
  if [[ "${src}" != "$(readlink -f "${DEST}")" ]]; then
    install -m 0755 "${src}" "${DEST}"
  fi
}

install_chain() {
  local guarded="${SSH_PORT},${API_PORT},${UI_PORTS}"
  if ! iptables -nL "${CHAIN}" >/dev/null 2>&1; then
    iptables -N "${CHAIN}"
  fi
  iptables -F "${CHAIN}"
  iptables -A "${CHAIN}" -i lo -j ACCEPT
  iptables -A "${CHAIN}" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  iptables -A "${CHAIN}" -i cni0 -j ACCEPT
  iptables -A "${CHAIN}" -i flannel.1 -j ACCEPT
  iptables -A "${CHAIN}" -i docker0 -j ACCEPT
  iptables -A "${CHAIN}" -i br+ -j ACCEPT
  iptables -A "${CHAIN}" -s "${POD_CIDR}" -j ACCEPT
  iptables -A "${CHAIN}" -s "${SERVICE_CIDR}" -j ACCEPT
  iptables -A "${CHAIN}" -p icmp --icmp-type echo-request -j ACCEPT
  iptables -A "${CHAIN}" -p tcp -m multiport --dports 80,443 -j ACCEPT
  iptables -A "${CHAIN}" -p tcp -s "${ADMIN_CIDR}" -m multiport --dports "${guarded}" -j ACCEPT
  iptables -A "${CHAIN}" -p tcp -m multiport --dports "${guarded}" -j DROP
  iptables -A "${CHAIN}" -j RETURN
  if ! iptables -C INPUT -j "${CHAIN}" 2>/dev/null; then
    iptables -I INPUT 1 -j "${CHAIN}"
  fi
}

start_timer() {
  type systemd-run >/dev/null 2>&1 || die "systemd-run is required"
  systemctl stop k3s-gitops-fw-rollback.timer >/dev/null 2>&1 || true
  systemd-run \
    --unit=k3s-gitops-fw-rollback \
    --on-active="${ROLLBACK_SECONDS}" \
    --timer-property=AccuracySec=1s \
    "${DEST}" rollback
}

save_backup() {
  umask 077
  mkdir -p "${STATE_DIR}"
  if [[ ! -f "${STATE_DIR}/iptables.before" ]]; then
    iptables-save > "${STATE_DIR}/iptables.before"
  fi
}

commit_rules() {
  [[ -f "${STATE_DIR}/iptables.before" ]] || die "nothing to commit"
  [[ -f "${STATE_DIR}/firewall.env" ]] || die "missing firewall.env"
  systemctl stop k3s-gitops-fw-rollback.timer >/dev/null 2>&1 || true
  install -m 0600 "${STATE_DIR}/firewall.env" /etc/k3s-gitops-firewall.env
  cat > /etc/systemd/system/k3s-gitops-firewall.service <<'EOF'
[Unit]
Description=Apply the k3s gitops host firewall chain
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
EnvironmentFile=/etc/k3s-gitops-firewall.env
ExecStart=/usr/local/sbin/k3s-gitops-firewall.sh apply-persistent
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable k3s-gitops-firewall.service
  mv "${STATE_DIR}/iptables.before" "${STATE_DIR}/iptables.committed"
  echo "committed"
}

rollback_rules() {
  systemctl stop k3s-gitops-fw-rollback.timer >/dev/null 2>&1 || true
  [[ -f "${STATE_DIR}/iptables.before" ]] || die "no backup"
  iptables-restore < "${STATE_DIR}/iptables.before"
  rm -f "${STATE_DIR}/iptables.before"
  echo "restored"
}

remove_rules() {
  systemctl stop k3s-gitops-fw-rollback.timer >/dev/null 2>&1 || true
  systemctl disable --now k3s-gitops-firewall.service >/dev/null 2>&1 || true
  rm -f /etc/systemd/system/k3s-gitops-firewall.service /etc/k3s-gitops-firewall.env
  systemctl daemon-reload || true
  while iptables -C INPUT -j "${CHAIN}" 2>/dev/null; do
    iptables -D INPUT -j "${CHAIN}"
  done
  if iptables -nL "${CHAIN}" >/dev/null 2>&1; then
    iptables -F "${CHAIN}"
    iptables -X "${CHAIN}"
  fi
  echo "removed"
}

main() {
  local mode="${1:-}"
  case "${mode}" in
    check)
      validate
      echo "check ok"
      ;;
    apply)
      validate
      require_root
      install_self
      write_env
      save_backup
      start_timer
      install_chain
      echo "applied; rollback in ${ROLLBACK_SECONDS}s unless you commit"
      ;;
    apply-persistent)
      validate
      require_root
      install_chain
      echo "applied"
      ;;
    commit)
      require_root
      commit_rules
      ;;
    rollback)
      require_root
      rollback_rules
      ;;
    remove)
      require_root
      remove_rules
      ;;
    *)
      usage
      exit 2
      ;;
  esac
}

main "${1:-}"
