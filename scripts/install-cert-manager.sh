#!/usr/bin/env bash
set -euo pipefail
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
kubectl wait --namespace cert-manager --for=condition=Available deployment/cert-manager --timeout=180s
kubectl wait --namespace cert-manager --for=condition=Available deployment/cert-manager-cainjector --timeout=180s
kubectl wait --namespace cert-manager --for=condition=Available deployment/cert-manager-webhook --timeout=180s
kubectl get pods -n cert-manager
