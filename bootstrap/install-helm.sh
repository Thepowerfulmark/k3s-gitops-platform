#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=versions.sh
source "${ROOT}/versions.sh"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "run as root" >&2
  exit 1
fi

arch="$(uname -m)"
case "${arch}" in
  x86_64) helm_arch=amd64 ;;
  aarch64 | arm64) helm_arch=arm64 ;;
  *)
    echo "unsupported arch: ${arch}" >&2
    exit 1
    ;;
esac

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT
curl -fsSL -o "${tmpdir}/helm.tgz" "https://get.helm.sh/helm-${HELM_VERSION}-linux-${helm_arch}.tar.gz"
tar -xzf "${tmpdir}/helm.tgz" -C "${tmpdir}"
install -m 0755 "${tmpdir}/linux-${helm_arch}/helm" /usr/local/bin/helm
helm version --short
