#!/usr/bin/env bash
# Install Argo CD and publish the UI as a NodePort.
# If Argo CD is already installed, print the image and exit.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=versions.sh
source "${ROOT}/versions.sh"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "run as root" >&2
  exit 1
fi

if k3s kubectl -n argocd get deploy argocd-server >/dev/null 2>&1; then
  echo "Argo CD is already installed"
  k3s kubectl -n argocd get deploy argocd-server -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
  exit 0
fi

k3s kubectl create namespace argocd --dry-run=client -o yaml | k3s kubectl apply -f -
k3s kubectl apply -n argocd -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
k3s kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
k3s kubectl -n argocd patch svc argocd-server --type strategic \
  -p '{"spec":{"type":"NodePort","ports":[{"port":80,"nodePort":30081}]}}'
echo "Argo CD UI NodePort 30081"
