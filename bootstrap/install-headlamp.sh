#!/usr/bin/env bash
# Install Headlamp. If it is already installed, print the image and exit.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=versions.sh
source "${ROOT}/versions.sh"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "run as root" >&2
  exit 1
fi

if ! grep -q "headlamp:${HEADLAMP_VERSION}" "${ROOT}/headlamp.yaml"; then
  echo "headlamp.yaml does not match ${HEADLAMP_VERSION}" >&2
  exit 1
fi

if k3s kubectl -n kube-system get deploy headlamp >/dev/null 2>&1; then
  echo "Headlamp is already installed"
  k3s kubectl -n kube-system get deploy headlamp -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
  exit 0
fi

k3s kubectl apply -f "${ROOT}/headlamp.yaml"
k3s kubectl -n kube-system rollout status deploy/headlamp --timeout=180s
echo "Headlamp UI NodePort 30082"
