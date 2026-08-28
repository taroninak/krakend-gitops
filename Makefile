# KrakenD on Kubernetes with Argo CD — POC control plane.
#
#   OpenTofu owns the cluster and the Argo CD bootstrap (infra/).
#   Git owns everything that runs inside it (clusters/, apps/, platform/).

TOFU         ?= tofu
INFRA        ?= infra
ARGOCD_NS    ?= argocd
GATEWAY_HOST ?= api.localhost
ARGOCD_HOST  ?= argocd.localhost
KEYCLOAK_HOST ?= keycloak.localhost
IAM_NS       ?= iam

# Used by `make lint` to validate the gateway config with KrakenD itself.
KRAKEND_IMAGE ?= devopsfaith/krakend:2.9.4
RENDER_DIR    ?= .cache/krakend-render
INGRESS_PORT ?= 8080

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z_.-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "};{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

.PHONY: init
init: ## tofu init (run once, or after changing providers)
	@$(TOFU) -chdir=$(INFRA) init

.PHONY: plan
plan: ## Show what OpenTofu would change
	@$(TOFU) -chdir=$(INFRA) plan

.PHONY: up
up: ## Create the cluster, install Argo CD, hand over to Git
	@$(TOFU) -chdir=$(INFRA) apply -auto-approve
	@echo
	@$(TOFU) -chdir=$(INFRA) output

.PHONY: down
down: ## Destroy the cluster
	@$(TOFU) -chdir=$(INFRA) destroy -auto-approve

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

.PHONY: keycloak-ui
keycloak-ui: ## Open the Keycloak admin console (user: admin, password: make keycloak-password)
	@open http://$(KEYCLOAK_HOST):$(INGRESS_PORT) || true

.PHONY: keycloak-password
keycloak-password: ## Print the generated Keycloak admin password
	@kubectl -n $(IAM_NS) get secret keycloak-admin \
	-o jsonpath='{.data.KC_BOOTSTRAP_ADMIN_PASSWORD}' | base64 -d; echo

.PHONY: login
login: ## Open the browser login page (sign in, then the gateway accepts the cookie)
	@open http://$(GATEWAY_HOST):$(INGRESS_PORT)/login || true

.PHONY: realm-reimport
realm-reimport: ## Delete the poc realm and re-seed it from Git (DESTROYS realm state: users, clients)
	@./scripts/realm-reimport.sh

.PHONY: token
token: ## Print an access token for the krakend-demo client
	@./scripts/get-token.sh

.PHONY: config
config: ## Print the gateway config exactly as the chart assembles it
	@./scripts/render-krakend-config.sh

.PHONY: smoke
smoke: ## Call the gateway through the ingress
	@echo "--- GET /__health"
	@curl -fsS -H 'Host: $(GATEWAY_HOST)' http://localhost:$(INGRESS_PORT)/__health; echo
	@echo "--- GET /v1/uuid"
	@curl -fsS -H 'Host: $(GATEWAY_HOST)' http://localhost:$(INGRESS_PORT)/v1/uuid; echo
	@echo "--- GET /v1/status/418"
	@curl -s -o /dev/null -w 'HTTP %{http_code}\n' -H 'Host: $(GATEWAY_HOST)' http://localhost:$(INGRESS_PORT)/v1/status/418
	@echo "--- GET /v1/customer/42 without a token (expect 401)"
	@curl -s -o /dev/null -w 'HTTP %{http_code}\n' -H 'Host: $(GATEWAY_HOST)' http://localhost:$(INGRESS_PORT)/v1/customer/42
	@echo "--- GET /v1/customer/42 with a bearer token (users-api + orders-api merged)"
	@curl -fsS -H 'Host: $(GATEWAY_HOST)' -H "Authorization: Bearer $$(./scripts/get-token.sh)" \
	http://localhost:$(INGRESS_PORT)/v1/customer/42; echo
	@echo "--- GET /v1/customer/42 with the token in a cookie (what the browser does)"
	@curl -s -o /dev/null -w 'HTTP %{http_code}\n' -H 'Host: $(GATEWAY_HOST)' \
	--cookie "access_token=$$(./scripts/get-token.sh)" \
	http://localhost:$(INGRESS_PORT)/v1/customer/42
	@echo "--- GET /v1/profile (two backends aggregated into one response)"
	@curl -fsS -H 'Host: $(GATEWAY_HOST)' http://localhost:$(INGRESS_PORT)/v1/profile; echo
	@echo "--- GET /v1/protected without a token (expect 401)"
	@curl -s -o /dev/null -w 'HTTP %{http_code}\n' -H 'Host: $(GATEWAY_HOST)' http://localhost:$(INGRESS_PORT)/v1/protected
	@echo "--- GET /v1/protected with a Keycloak token (expect 200)"
	@curl -s -o /dev/null -w 'HTTP %{http_code}\n' -H 'Host: $(GATEWAY_HOST)' \
	-H "Authorization: Bearer $$(./scripts/get-token.sh)" \
	http://localhost:$(INGRESS_PORT)/v1/protected

.PHONY: lint
lint: ## Render everything locally (no cluster needed)
	@$(TOFU) -chdir=$(INFRA) fmt -check && echo "infra/              fmt OK"
	@$(TOFU) -chdir=$(INFRA) validate >/dev/null && echo "infra/              validate OK"
	@helm template root clusters/poc --set repoURL=https://example.com/repo.git >/dev/null && echo "clusters/poc        OK"
	@helm template httpbin apps/httpbin >/dev/null && echo "apps/httpbin        OK"
	@helm template portal apps/portal >/dev/null && echo "apps/portal         OK"
	@helm template users-api apps/demo-api -f apps/demo-api/values-users.yaml >/dev/null \
	&& helm template orders-api apps/demo-api -f apps/demo-api/values-orders.yaml >/dev/null \
	&& echo "apps/demo-api       OK"
	@helm dependency build apps/keycloak >/dev/null 2>&1 || true
	@helm template keycloak apps/keycloak >/dev/null && echo "apps/keycloak       OK"
	@for f in apps/krakend/config/service.json apps/krakend/config/endpoints/*.json; do \
	python3 -c "import json,sys;json.load(open(sys.argv[1]))" "$$f" || exit 1; done \
	&& echo "krakend config      every source file is valid JSON"
	@mkdir -p $(RENDER_DIR)
	@./scripts/render-krakend-config.sh > $(RENDER_DIR)/krakend.json
	@docker run --rm -v "$(PWD)/$(RENDER_DIR):/etc/krakend:ro" \
	$(KRAKEND_IMAGE) check -c /etc/krakend/krakend.json >/dev/null 2>&1 \
	&& echo "krakend config      krakend check OK on the assembled file" \
	|| echo "krakend config      krakend check SKIPPED (docker unavailable)"
	@helm template krakend apps/krakend >/dev/null && echo "apps/krakend        OK"
	@helm template argocd argo/argo-cd --values platform/argocd/values.yaml >/dev/null && echo "platform/argocd     OK"
