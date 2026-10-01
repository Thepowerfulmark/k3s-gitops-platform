#!/usr/bin/env bash
# Install single-node k3s. If k3s is already present, print the version and exit.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=versions.sh
source "${ROOT}/versions.sh"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "run as root" >&2
  exit 1
fi

if [[ -x /usr/local/bin/k3s ]]; then
  echo "k3s is already installed"
  k3s --version
  exit 0
fi

curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${K3S_VERSION}" sh -s - server \
  --disable traefik \
  --disable servicelb \
  --write-kubeconfig-mode 600

k3s kubectl get nodes
