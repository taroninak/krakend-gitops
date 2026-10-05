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
KRAKEND_IMAGE ?= krakend:3.0.0
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

.PHONY: dev
dev: ## Run local demo-api code and gateway config in the cluster, no release (undo: make dev-off)
	@./scripts/dev.sh

.PHONY: dev-off
dev-off: ## Hand demo-api and the gateway back to Git, undoing make dev
	@./scripts/dev-off.sh

.PHONY: status
status: ## Show what Argo CD thinks of the world
	@[ -n "$$(kubectl -n $(ARGOCD_NS) get application root -o jsonpath='{.spec.syncPolicy.automated}' 2>/dev/null)" ] \
	|| echo "!! DEV MODE: demo-api and krakend run your working copy, not Git. Undo with: make dev-off"
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

.PHONY: logout
logout: ## Open the sign-out page (clears the cookie and the Keycloak session)
	@open http://$(GATEWAY_HOST):$(INGRESS_PORT)/logout || true

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
	@echo "--- GET /v1/users/42 (demo-api /users/42)"
	@curl -fsS -H 'Host: $(GATEWAY_HOST)' http://localhost:$(INGRESS_PORT)/v1/users/42; echo
	@echo "--- GET /v1/customers/45/orders (each order with its own participants)"
	@curl -fsS -H 'Host: $(GATEWAY_HOST)' http://localhost:$(INGRESS_PORT)/v1/customers/45/orders \
	| ./scripts/assert-json.py orders=2 orders.0.id==A-1006 orders.0.participants=5 orders.1.id==A-1008 orders.1.participants=2
	@echo "--- GET /v1/customers/43/orders (only customer 43's orders)"
	@curl -fsS -H 'Host: $(GATEWAY_HOST)' http://localhost:$(INGRESS_PORT)/v1/customers/43/orders \
	| ./scripts/assert-json.py orders=3
	@echo "--- GET /v1/customers/46/orders (a customer with no orders gets an empty list)"
	@curl -fsS -H 'Host: $(GATEWAY_HOST)' http://localhost:$(INGRESS_PORT)/v1/customers/46/orders \
	| ./scripts/assert-json.py orders=0
	@echo "--- GET /v1/customers/42 without a token (expect 401)"
	@curl -s -o /dev/null -w 'HTTP %{http_code}\n' -H 'Host: $(GATEWAY_HOST)' http://localhost:$(INGRESS_PORT)/v1/customers/42
	@echo "--- GET /v1/customers/43 with a bearer token (user + their own orders, merged flat)"
	@curl -fsS -H 'Host: $(GATEWAY_HOST)' -H "Authorization: Bearer $$(./scripts/get-token.sh)" \
	http://localhost:$(INGRESS_PORT)/v1/customers/43 | ./scripts/assert-json.py orders=3
	@echo "--- GET /v1/customers/42 with the token in a cookie (what the browser does)"
	@curl -s -o /dev/null -w 'HTTP %{http_code}\n' -H 'Host: $(GATEWAY_HOST)' \
	--cookie "access_token=$$(./scripts/get-token.sh)" \
	http://localhost:$(INGRESS_PORT)/v1/customers/42
	@echo "--- GET /v1/customers (id list, then ONE batch call for all of them)"
	@curl -fsS -H 'Host: $(GATEWAY_HOST)' http://localhost:$(INGRESS_PORT)/v1/customers \
	| ./scripts/assert-json.py customers=4
	@echo "--- GET /v1/events/1001 (participants in one batch call; customer via the event's order)"
	@curl -fsS -H 'Host: $(GATEWAY_HOST)' http://localhost:$(INGRESS_PORT)/v1/events/1001 \
	| ./scripts/assert-json.py participants=4 customer.customer_id==45
	@echo "--- GET /v1/events/1002 (an id with no user is reported, not dropped)"
	@curl -fsS -H 'Host: $(GATEWAY_HOST)' http://localhost:$(INGRESS_PORT)/v1/events/1002 \
	| ./scripts/assert-json.py participants=1 participants_missing=1 customer.customer_id==42
	@echo "--- GET /v1/orders/A-1006 (customer + participants of both its events, combined in KrakenD)"
	@curl -fsS -H 'Host: $(GATEWAY_HOST)' http://localhost:$(INGRESS_PORT)/v1/orders/A-1006 \
	| ./scripts/assert-json.py events=2 participants=5 customer.customer_id==45
	@echo "--- GET /v1/orders/A-1001 (an invited user who does not exist is reported)"
	@curl -fsS -H 'Host: $(GATEWAY_HOST)' http://localhost:$(INGRESS_PORT)/v1/orders/A-1001 \
	| ./scripts/assert-json.py participants=1 participants_missing=1
	@echo "--- GET /v1/orders/A-1003 (an order with no events has no participants)"
	@curl -fsS -H 'Host: $(GATEWAY_HOST)' http://localhost:$(INGRESS_PORT)/v1/orders/A-1003 \
	| ./scripts/assert-json.py events=0 participants=0 customer.customer_id==43
	@echo "--- GET /v1/profile/42 (same two calls, kept nested under groups)"
	@curl -fsS -H 'Host: $(GATEWAY_HOST)' http://localhost:$(INGRESS_PORT)/v1/profile/42; echo
	@echo "--- GET /v1/protected without a token (expect 401)"
	@curl -s -o /dev/null -w 'HTTP %{http_code}\n' -H 'Host: $(GATEWAY_HOST)' http://localhost:$(INGRESS_PORT)/v1/protected
	@echo "--- GET /v1/protected with a Keycloak token (expect 200)"
	@curl -s -o /dev/null -w 'HTTP %{http_code}\n' -H 'Host: $(GATEWAY_HOST)' \
	-H "Authorization: Bearer $$(./scripts/get-token.sh)" \
	http://localhost:$(INGRESS_PORT)/v1/protected

.PHONY: lint-demo-api
lint-demo-api: ## Check demo-api's code, data and chart
	@for f in services/demo-api/data/*.json; do \
	python3 -c "import json,sys;json.load(open(sys.argv[1]))" "$$f" || exit 1; done \
	&& echo "demo-api data        every data file is valid JSON"
	@for f in services/demo-api/src/*.js services/demo-api/src/routes/*.js; do node --check "$$f" || exit 1; done \
	&& echo "demo-api code        every module parses"
	@helm template demo-api apps/demo-api >/dev/null \
	&& echo "apps/demo-api       OK"

.PHONY: lint-krakend
lint-krakend: ## Check the gateway config and Lua, as KrakenD will load them
	@for f in apps/krakend/config/service.json apps/krakend/config/endpoints/*.json; do \
	python3 -c "import json,sys;json.load(open(sys.argv[1]))" "$$f" || exit 1; done \
	&& echo "krakend config      every source file is valid JSON"
	@mkdir -p $(RENDER_DIR)
	@./scripts/render-krakend-config.sh > $(RENDER_DIR)/krakend.json
	@cp apps/krakend/config/lua/*.lua $(RENDER_DIR)/
	@# KrakenD loads Lua lazily: a broken script passes krakend check AND startup,
	@# and only fails on the first request. KrakenD's Lua is 5.1, so parse with that.
	@if ! docker info >/dev/null 2>&1; then \
	echo "krakend config      Lua check and krakend check SKIPPED (docker unavailable)"; \
	else \
	docker run --rm -v "$(PWD)/apps/krakend/config/lua:/lua:ro" alpine:3 \
	sh -c 'apk add -q lua5.1 >/dev/null && luac5.1 -p /lua/*.lua' \
	|| { echo "krakend config      Lua syntax error (see above)"; exit 1; }; \
	echo "krakend config      every Lua script parses"; \
	docker run --rm -v "$(PWD)/$(RENDER_DIR):/etc/krakend:ro" \
	$(KRAKEND_IMAGE) check -c /etc/krakend/krakend.json \
	|| { echo "krakend config      krakend check FAILED (see above)"; exit 1; }; \
	echo "krakend config      krakend check OK on the assembled file"; \
	fi
	@helm template krakend apps/krakend >/dev/null && echo "apps/krakend        OK"

.PHONY: lint
lint: ## Render everything locally (no cluster needed)
	@$(TOFU) -chdir=$(INFRA) fmt -check && echo "infra/              fmt OK"
	@$(TOFU) -chdir=$(INFRA) validate >/dev/null && echo "infra/              validate OK"
	@helm template root clusters/poc --set repoURL=https://example.com/repo.git >/dev/null && echo "clusters/poc        OK"
	@helm template portal apps/portal >/dev/null && echo "apps/portal         OK"
	@$(MAKE) -s lint-demo-api
	@helm dependency build apps/keycloak >/dev/null 2>&1 || true
	@helm template keycloak apps/keycloak >/dev/null && echo "apps/keycloak       OK"
	@$(MAKE) -s lint-krakend
	@helm template argocd argo/argo-cd --values platform/argocd/values.yaml >/dev/null && echo "platform/argocd     OK"
