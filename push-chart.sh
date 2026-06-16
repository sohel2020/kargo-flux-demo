#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHART_DIR="$SCRIPT_DIR/charts/demo"
VERSION="${1:-0.1.0}"
REGISTRY_FILE="$SCRIPT_DIR/.chart-registry"

# Reuse registry path across runs so all versions land in the same OCI repo.
# First run generates a random name; subsequent runs read from .chart-registry.
if [ -f "$REGISTRY_FILE" ]; then
  CHART_NAME=$(cat "$REGISTRY_FILE")
  echo "==> Reusing registry: ttl.sh/${CHART_NAME}"
else
  CHART_NAME="demo-$(uuidgen | tr '[:upper:]' '[:lower:]' | cut -c1-8)"
  echo "$CHART_NAME" > "$REGISTRY_FILE"
  echo "==> New registry: ttl.sh/${CHART_NAME}"
fi

echo "==> Linting chart..."
helm lint "$CHART_DIR"

echo "==> Packaging chart (version: $VERSION)..."
helm package "$CHART_DIR" --version "$VERSION" --destination /tmp

CHART_PKG="/tmp/demo-${VERSION}.tgz"

echo "==> Pushing to ttl.sh/${CHART_NAME}..."
helm push "$CHART_PKG" "oci://ttl.sh/${CHART_NAME}"

# Patch manifests if they still have the placeholder
if grep -rq "demo-REPLACE_ME" "$SCRIPT_DIR/clusters/local/demo-helm-repo.yaml" 2>/dev/null; then
  echo ""
  echo "==> Patching manifests with registry: $CHART_NAME"
  sed -i.bak "s|demo-REPLACE_ME|${CHART_NAME}|g" \
    "$SCRIPT_DIR/clusters/local/demo-helm-repo.yaml" \
    "$SCRIPT_DIR/kargo-demo/warehouse.yaml" \
    "$SCRIPT_DIR/kargo-demo/stages.yaml"
  find "$SCRIPT_DIR" -name "*.bak" -delete
fi

echo ""
echo "============================================"
echo "  CHART PUSHED"
echo "============================================"
echo ""
echo "OCI ref:  oci://ttl.sh/${CHART_NAME}/demo:${VERSION}"
echo "Expires:  ~2 hours (ttl.sh default)"
echo ""
echo "Pull test:"
echo "  helm pull oci://ttl.sh/${CHART_NAME}/demo --version ${VERSION}"
echo ""
echo "============================================"
echo "  SETUP (first time only)"
echo "============================================"
echo ""
echo "1. Commit and push so Flux picks up the new manifests:"
echo "   git add -A && git commit -m 'add demo helm chart' && git push"
echo ""
echo "2. Apply Kargo demo project:"
echo "   kubectl apply -f kargo-demo/project.yaml"
echo ""
echo "3. Create credentials secret:"
echo "   export GITHUB_TOKEN=\$(gh auth token)"
echo "   sed \"s|REPLACE_WITH_PAT|\$GITHUB_TOKEN|\" kargo-demo/credentials.example.yaml | kubectl apply -f -"
echo ""
echo "4. Apply warehouse, stages, project config:"
echo "   kubectl apply -f kargo-demo/warehouse.yaml"
echo "   kubectl apply -f kargo-demo/stages.yaml"
echo "   kubectl apply -f kargo-demo/projectconfig.yaml"
echo ""
echo "============================================"
echo "  TRIGGER A PROMOTION"
echo "============================================"
echo ""
echo "Push a new chart version:"
echo "  ./push-chart.sh 0.2.0"
echo ""
echo "Kargo warehouse polls for new chart versions."
echo "New freight appears, auto-promotes to dev, then manual promote stage/prod."
echo ""
echo "============================================"
echo "  KARGO UI"
echo "============================================"
echo ""
echo "  kubectl -n kargo port-forward svc/kargo-api 8080:8080"
echo ""
echo "  Open:     https://localhost:8080"
echo "  Username: admin"
echo "  Password: admin"
echo ""
