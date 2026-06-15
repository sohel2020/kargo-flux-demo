# Flux + Kargo promotion demo

dev → stage → prod promotion of a [podinfo](https://github.com/stefanprodan/podinfo) image tag,
on one local `kind` cluster.

- **Flux** deploys each environment from this Git repo (one Kustomization per namespace).
- **Kargo** watches the podinfo image registry, models *Freight*, and on promotion rewrites the
  `newTag` in the target overlay and pushes. Flux then reconciles the change.
- The two tools communicate only through Git.

```
new podinfo tag
  -> Kargo Warehouse makes Freight
  -> dev Stage auto-promotes  -> Kargo commits dev newTag  -> Flux deploys podinfo-dev
  -> you promote to stage      -> Kargo commits stage newTag -> Flux deploys podinfo-stage
  -> you promote to prod       -> Kargo commits prod newTag  -> Flux deploys podinfo-prod
```

dev is auto-promoted. stage and prod are manual gates.

## Prerequisites

- docker, kind, kubectl, flux, helm, gh (authenticated: `gh auth status`)
- A GitHub token with `repo` scope: `export GITHUB_TOKEN=$(gh auth token)`

## Setup

```bash
export GITHUB_TOKEN=$(gh auth token)
./setup.sh
```

This creates the kind cluster, installs cert-manager, runs `flux bootstrap github`
(which commits `clusters/local/flux-system` to this repo), and installs Kargo via Helm.

Then wire up the Kargo project:

```bash
kubectl apply -f kargo/project.yaml
sed "s|REPLACE_WITH_PAT|$GITHUB_TOKEN|" kargo/credentials.example.yaml > kargo/credentials.yaml
kubectl apply -f kargo/credentials.yaml          # git-ignored, holds the real token
kubectl apply -f kargo/warehouse.yaml
kubectl apply -f kargo/stages.yaml -f kargo/projectconfig.yaml
```

## Observe

```bash
# Flux
flux get kustomizations

# Kargo
kubectl get warehouse,freight,stage -n podinfo

# image running in each environment
for n in dev stage prod; do
  echo "podinfo-$n: $(kubectl get deploy podinfo -n podinfo-$n \
    -o jsonpath='{.spec.template.spec.containers[0].image}')"
done

# podinfo UI / version endpoint
kubectl -n podinfo-dev port-forward svc/podinfo 9898:9898 &
curl -s localhost:9898/version
```

Kargo UI (optional): `kubectl -n kargo port-forward svc/kargo-api 8080:8080`,
open https://localhost:8080, log in as `admin` / `admin`.

## Promote (manual, no Kargo CLI needed)

Promotion is triggered by applying a `Promotion` resource. Grab the freight name, then promote:

```bash
FREIGHT=$(kubectl get freight -n podinfo -o jsonpath='{.items[0].metadata.name}')

# dev -> stage
kubectl apply -f - <<EOF
apiVersion: kargo.akuity.io/v1alpha1
kind: Promotion
metadata:
  generateName: stage-
  namespace: podinfo
spec:
  stage: stage
  freight: $FREIGHT
EOF

# stage -> prod (run after stage is healthy)
kubectl apply -f - <<EOF
apiVersion: kargo.akuity.io/v1alpha1
kind: Promotion
metadata:
  generateName: prod-
  namespace: podinfo
spec:
  stage: prod
  freight: $FREIGHT
EOF
```

Watch the promotion: `kubectl get promotion -n podinfo -w`.
After it succeeds, Kargo has pushed a commit; Flux deploys within its 1m interval.

(If the Kargo CLI is installed, `kargo promote --project podinfo --stage stage --freight $FREIGHT`
does the same thing.)

## Teardown

```bash
./teardown.sh
```
