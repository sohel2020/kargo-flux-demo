#!/usr/bin/env bash
set -euo pipefail

OWNER=sohel2020
REPO=kargo-flux-demo
CLUSTER=kargo-flux
KARGO_VERSION=1.10.7

echo "==> kind cluster"
kind get clusters | grep -qx "$CLUSTER" || kind create cluster --name "$CLUSTER"
kubectl config use-context "kind-$CLUSTER"

echo "==> cert-manager (Kargo prerequisite)"
helm repo add jetstack https://charts.jetstack.io --force-update
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true --wait

#echo "==> Flux bootstrap (needs GITHUB_TOKEN with repo scope)"
#: "${GITHUB_TOKEN:?set GITHUB_TOKEN, e.g. export GITHUB_TOKEN=\$(gh auth token)}"
#flux bootstrap github \
#  --owner="$OWNER" --repository="$REPO" \
#  --path=clusters/local --branch=main --personal --token-auth

echo "==> Kargo via Helm (v$KARGO_VERSION)"
PW_HASH=$(htpasswd -bnBC 10 "" admin | tr -d ':\n')
SIGNING_KEY=$(openssl rand -base64 29 | tr -d '=+/')
helm upgrade --install kargo oci://ghcr.io/akuity/kargo-charts/kargo \
  --version "$KARGO_VERSION" \
  --namespace kargo --create-namespace \
  --set api.adminAccount.passwordHash="$PW_HASH" \
  --set api.adminAccount.tokenSigningKey="$SIGNING_KEY" \
  --wait

echo
echo "==> setup complete. Next:"
echo "    export GITHUB_TOKEN=\$(gh auth token)   # if not already set"
echo "    kubectl apply -f kargo/project.yaml"
echo "    sed \"s|REPLACE_WITH_PAT|\$GITHUB_TOKEN|\" kargo/credentials.example.yaml > kargo/credentials.yaml"
echo "    kubectl apply -f kargo/credentials.yaml"
echo "    kubectl apply -f kargo/warehouse.yaml"
echo "    kubectl apply -f kargo/stages.yaml -f kargo/projectconfig.yaml"
echo "    Kargo admin password: admin  (UI: kubectl -n kargo port-forward svc/kargo-api 8080:8080)"
