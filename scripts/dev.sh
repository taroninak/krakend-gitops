#!/usr/bin/env bash
# make dev — run your local demo-api code and gateway config in the cluster,
# without a release: no version bump, no CI, no push. Run it again after every
# change; undo everything with `make dev-off`.
#
# Argo CD reverts anything that differs from Git within seconds (selfHeal), so
# this first pauses auto-sync for demo-api and krakend — and for root, which
# owns their sync settings and would otherwise switch auto-sync straight back
# on. Every other Application keeps syncing from Git as usual.
#
# Why not Argo CD's skip-reconcile annotation, which looks made for this? On
# Argo CD 3.5.1 it did not stop selfHeal: a manual change was reverted with the
# annotation set.
set -euo pipefail
cd "$(dirname "$0")/.."

CLUSTER="${CLUSTER:-krakend-poc}"
ARGOCD_NS="${ARGOCD_NS:-argocd}"

step() { printf '\n==> %s\n' "$*"; }

step "Checking demo-api and the gateway config before touching the cluster"
make -s lint-demo-api lint-krakend

step "Pausing Argo CD auto-sync for root, demo-api and krakend"
for app in root demo-api krakend; do
  kubectl -n "$ARGOCD_NS" patch application "$app" --type merge \
    -p '{"spec":{"syncPolicy":{"automated":null}}}' >/dev/null
done

step "Building demo-api from services/demo-api"
# A new tag on every run, so demo-api always restarts on the code just built.
# (Not a content hash: BuildKit stamps each build with its time, so even an
# unchanged build gets a new image id.)
tag="dev-$(date +%Y%m%d-%H%M%S)"
docker build -q -t "demo-api:$tag" services/demo-api >/dev/null
kind load docker-image "demo-api:$tag" --name "$CLUSTER" >/dev/null

step "Applying demo-api $tag"
helm template demo-api apps/demo-api \
  --set image.repository=demo-api --set image.tag="$tag" \
  | kubectl -n demo apply -f - >/dev/null

# Rolls the gateway when its config, Lua or chart changed: the chart hashes the
# ConfigMap into the pod template.
step "Applying the gateway from apps/krakend (config, Lua and chart)"
helm template krakend apps/krakend | kubectl -n gateway apply -f - >/dev/null

step "Waiting for both to roll out"
kubectl -n demo rollout status deploy/demo-api --timeout=180s
kubectl -n gateway rollout status deploy/krakend --timeout=180s

cat <<MSG

Running your working copy:  demo-api $tag, gateway config from apps/krakend
Check it:                   make smoke    or    curl http://api.localhost:8080/v1/...
After another change:       make dev
Back to Git:                make dev-off
MSG
