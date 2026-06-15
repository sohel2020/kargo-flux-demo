#!/usr/bin/env bash
# Manually promote the latest Freight into a Stage.
# Usage: ./promote.sh <stage-name>   e.g. ./promote.sh stage   ./promote.sh prod
#
# Why this script: a manually-created Kargo Promotion must carry spec.steps itself.
# Kargo only copies a Stage's promotionTemplate into the Promotion automatically for
# *auto*-promotions (done by the controller). For manual promotions we inline the
# Stage's own promotionTemplate steps here. (The Kargo CLI/UI do this copy for you.)
set -euo pipefail

STAGE="${1:?usage: ./promote.sh <stage-name>}"
NS=podinfo

FREIGHT=$(kubectl get freight -n "$NS" -o jsonpath='{.items[0].metadata.name}')
[ -n "$FREIGHT" ] || { echo "no freight found in namespace $NS"; exit 1; }

STEPS=$(kubectl get stage "$STAGE" -n "$NS" -o jsonpath='{.spec.promotionTemplate.spec.steps}')
[ -n "$STEPS" ] || { echo "stage $STAGE has no promotionTemplate steps"; exit 1; }

python3 - "$STAGE" "$FREIGHT" "$STEPS" <<'PY' | kubectl create -f -
import sys, json
stage, freight, steps = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
print(json.dumps({
    "apiVersion": "kargo.akuity.io/v1alpha1",
    "kind": "Promotion",
    "metadata": {"generateName": f"{stage}-", "namespace": "podinfo"},
    "spec": {"stage": stage, "freight": freight, "steps": steps},
}))
PY

echo "promotion created for stage '$STAGE' with freight $FREIGHT"
echo "watch: kubectl get promotion -n $NS -w"
