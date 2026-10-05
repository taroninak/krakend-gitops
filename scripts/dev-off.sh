#!/usr/bin/env bash
# make dev-off — hand demo-api and the gateway back to Git.
#
# Turns root's auto-sync back on, exactly as infra/charts/argocd-bootstrap
# defines it. root then restores demo-api's and krakend's own sync settings from
# Git, and they replace your local image and config with the released ones.
set -euo pipefail

ARGOCD_NS="${ARGOCD_NS:-argocd}"

kubectl -n "$ARGOCD_NS" patch application root --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}' >/dev/null
for app in root demo-api krakend; do
  kubectl -n "$ARGOCD_NS" annotate application "$app" argocd.argoproj.io/refresh=hard --overwrite >/dev/null
done

echo "Waiting for Argo CD to put demo-api and krakend back to what Git says..."
for _ in $(seq 1 60); do
  done_count=0
  for app in demo-api krakend; do
    state=$(kubectl -n "$ARGOCD_NS" get application "$app" \
      -o jsonpath='{.spec.syncPolicy.automated.selfHeal}/{.status.sync.status}/{.status.health.status}')
    [ "$state" = "true/Synced/Healthy" ] && done_count=$((done_count + 1))
  done
  [ "$done_count" = 2 ] && break
  sleep 5
done

kubectl -n demo rollout status deploy/demo-api --timeout=180s
kubectl -n gateway rollout status deploy/krakend --timeout=180s
echo "Back to Git."
