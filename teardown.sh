#!/usr/bin/env bash
set -euo pipefail
kind delete cluster --name kargo-flux
echo "cluster deleted."
echo "to delete the GitHub repo: gh repo delete sohel2020/kargo-flux-demo --yes"
