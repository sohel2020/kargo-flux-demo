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

## Promote (manual gates for stage and prod)

Use the helper:

```bash
./promote.sh stage    # dev  -> stage
./promote.sh prod     # stage -> prod (run after stage is healthy)
```

Watch it: `kubectl get promotion -n podinfo -w`.
After a promotion succeeds, Kargo has pushed a commit bumping that env's `newTag`;
Flux deploys the change within its 1m reconcile interval.

**Why a helper and not a bare `kubectl apply`?** A manually-created `Promotion` must
carry its `spec.steps` itself — Kargo only copies a Stage's `promotionTemplate` into
the Promotion automatically for *auto*-promotions (the controller does it). `promote.sh`
inlines the Stage's own template steps. The Kargo CLI/UI do this copy for you:

```bash
# equivalent, if the kargo CLI is installed and logged in:
kargo promote --project podinfo --stage stage --freight <freight-name>
```

## Teardown

```bash
./teardown.sh
```
