# KrakenD on Kubernetes with Argo CD — POC control plane.
# Everything here is either "create the empty cluster" or "hand it over to Git".

CLUSTER              ?= krakend-poc
ARGOCD_CHART_VERSION ?= 10.4.0
ARGOCD_NS            ?= argocd
GATEWAY_HOST         ?= api.localhost
ARGOCD_HOST          ?= argocd.localhost
INGRESS_PORT         ?= 8080

# Upstream KrakenD chart — kept in sync with clusters/poc/krakend.yaml so that
# `make lint` renders exactly what Argo CD will apply.
CHART_REPO ?= https://github.com/krakend/contrib-helm-chart.git
CHART_REF  ?= 85f99eee90c487a86b40d2d8f7d17d64c6d43f15
CHART_DIR  ?= .cache/krakend-chart

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	grep -hE '^[a-zA-Z_.-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "};{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

.PHONY: up
up: cluster argocd bootstrap ## Full POC: create cluster, install Argo CD, hand over to Git
	@echo
	@echo "Argo CD:  http://$(ARGOCD_HOST):$(INGRESS_PORT)  (admin / \`make password\`)"
	@echo "Gateway:  curl -H 'Host: $(GATEWAY_HOST)' http://localhost:$(INGRESS_PORT)/v1/profile"

.PHONY: cluster
cluster: ## Create the k3d cluster from bootstrap/k3d/cluster.yaml
	k3d cluster create --config bootstrap/k3d/cluster.yaml

.PHONY: argocd
argocd: ## Install Argo CD (bootstrap only — Argo CD manages itself afterwards)
	@helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
	@helm repo update argo >/dev/null
	helm upgrade --install argocd argo/argo-cd \
	--namespace $(ARGOCD_NS) --create-namespace \
	--version $(ARGOCD_CHART_VERSION) \
	--values platform/argocd/values.yaml \
	--wait --timeout 10m

.PHONY: bootstrap
bootstrap: ## Apply the root Application (the only kubectl apply in the whole POC)
	kubectl apply -f bootstrap/root-app.yaml

.PHONY: repo-url
repo-url: ## Point the POC at your Git repo: make repo-url REPO_URL=https://github.com/me/repo.git
	@./scripts/set-repo-url.sh "$(REPO_URL)"

.PHONY: status
status: ## Show what Argo CD thinks of the world
	@kubectl -n $(ARGOCD_NS) get applications.argoproj.io
	@echo
	@kubectl -n gateway get deploy,pod,svc,ingress 2>/dev/null || true

.PHONY: password
password: ## Print the initial Argo CD admin password
	@kubectl -n $(ARGOCD_NS) get secret argocd-initial-admin-secret \
	-o jsonpath='{.data.password}' | base64 -d; echo

.PHONY: ui
ui: ## Open the Argo CD UI (user: admin, password: make password)
	@open http://$(ARGOCD_HOST):$(INGRESS_PORT) || true

.PHONY: smoke
smoke: ## Call the gateway through the ingress
	@echo "--- GET /__health"
	@curl -fsS -H 'Host: $(GATEWAY_HOST)' http://localhost:$(INGRESS_PORT)/__health; echo
	@echo "--- GET /v1/uuid"
	@curl -fsS -H 'Host: $(GATEWAY_HOST)' http://localhost:$(INGRESS_PORT)/v1/uuid; echo
	@echo "--- GET /v1/profile (two backends aggregated into one response)"
	@curl -fsS -H 'Host: $(GATEWAY_HOST)' http://localhost:$(INGRESS_PORT)/v1/profile; echo

.PHONY: chart
chart: ## Fetch the pinned KrakenD chart locally (used by `make lint`)
	@test -d $(CHART_DIR)/.git || git clone --quiet $(CHART_REPO) $(CHART_DIR)
	@git -C $(CHART_DIR) fetch --quiet origin $(CHART_REF) 2>/dev/null || git -C $(CHART_DIR) fetch --quiet origin
	@git -C $(CHART_DIR) checkout --quiet $(CHART_REF)

.PHONY: lint
lint: chart ## Render every manifest locally (no cluster needed)
	@kubectl kustomize apps/httpbin >/dev/null && echo "apps/httpbin        OK"
	@helm template krakend $(CHART_DIR) --values apps/krakend/values.yaml >/dev/null && echo "apps/krakend        OK"
	@helm template argocd argo/argo-cd --version $(ARGOCD_CHART_VERSION) --values platform/argocd/values.yaml >/dev/null && echo "platform/argocd     OK"

.PHONY: down
down: ## Delete the cluster
	k3d cluster delete $(CLUSTER)
