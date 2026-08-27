# KrakenD on Kubernetes — IaC + GitOps proof of concept

A local, disposable stack that follows the standard split: **OpenTofu provisions**,
**Argo CD delivers**.

```
[ Local macOS ]
     │
     ├── OpenTofu / Terraform  (infra/)
     │      ├─ kind provider  ─▶ local Kubernetes cluster
     │      ├─ Helm provider  ─▶ ingress-nginx
     │      ├─ Helm provider  ─▶ Argo CD
     │      └─ Helm provider  ─▶ root Application  ──┐  (the hand-off)
     │                                               │
     └── Git repository (GitOps core) ◀──────────────┘
            └─ clusters/poc  (app-of-apps chart)
                   ├─ Argo CD    (manages its own installation)
                   ├─ KrakenD    (upstream Helm chart, pinned)
                   └─ httpbin    (app-services Helm chart)
```

Terraform stops at the root Application. Everything else — including Argo CD's own
upgrade path — is pulled from this repository.

## Layout

| Path | What it is |
|------|------------|
| `infra/` | OpenTofu: the cluster, ingress controller, Argo CD, and the root Application |
| `infra/charts/argocd-bootstrap/` | One-template chart holding the root Application (the hand-off point) |
| `infra/values/ingress-nginx.yaml` | Ingress controller values (kind-specific host ports) |
| `clusters/poc/` | App-of-apps **chart**: one Argo CD `Application` per workload, plus the `AppProject` |
| `platform/argocd/values.yaml` | Argo CD's own Helm values — used by the Terraform install **and** by Argo CD itself |
| `apps/krakend/values.yaml` | KrakenD Helm values **and** the gateway configuration (routes, backends, rate limits) |
| `apps/httpbin/` | Helm chart for the demo upstream API |

The Git URL is configured in exactly one place — `infra/terraform.tfvars`. Terraform
passes it to the root Application, which passes it down to every child Application as
a chart parameter.

## Prerequisites

```bash
brew install opentofu kind kubernetes-cli helm
```

Docker must be running.

## Run it

```bash
cp infra/terraform.tfvars.example infra/terraform.tfvars   # point it at your fork
make init
make up
```

`make up` creates the cluster, installs ingress-nginx and Argo CD, and creates the
root Application. Roughly two minutes later Argo CD has reconciled the rest.

```bash
make status     # what Argo CD thinks of the world
make password   # initial admin password (user: admin)
make ui         # http://argocd.localhost:8080
make smoke      # call the gateway through the ingress
make lint       # render everything locally, no cluster needed
make down       # destroy the cluster
```

`*.localhost` resolves to `127.0.0.1` on macOS. If your resolver disagrees, add:

```
127.0.0.1 argocd.localhost api.localhost
```

## The gateway

`apps/krakend/values.yaml` holds both the Helm values and the KrakenD configuration:

| Endpoint | Behaviour |
|----------|-----------|
| `GET /v1/uuid` | Straight proxy to the upstream `/uuid` |
| `GET /v1/status/{code}` | URL parameter forwarded to the upstream, response passed through untouched |
| `GET /v1/profile` | Aggregates two upstream calls (`/uuid` + `/headers`) into one JSON response, rate limited to 20 req/s |
| `GET /__health` | KrakenD's built-in health endpoint (used by the probes) |

```bash
curl -H 'Host: api.localhost' http://localhost:8080/v1/profile
```

Environment-specific values (backend host, timeouts) live in the `krakend.settings`
block as KrakenD *flexible configuration*, so the same gateway config can be promoted
across environments by swapping only that file.

### Changing a route

1. Edit `apps/krakend/values.yaml`
2. `git push`
3. Argo CD syncs within ~30s (`timeout.reconciliation`), the chart hashes the
   ConfigMaps into the pod annotations, and KrakenD rolls out with the new config.

No `kubectl`, no `helm`, no `tofu` — a route change is a pull request.

## Design notes

- **Why kind and not k3d.** The diagram allows either. The kind provider
  (`tehcyx/kind`) is actively maintained; every k3d provider on the registry had its
  last release in 2023 or earlier. kind ships no ingress controller, hence the
  explicit `ingress-nginx` release — which is arguably the better demonstration of the
  Helm provider anyway.
- **Why Terraform installs Argo CD at all.** Something has to create the thing that
  reads Git. Immediately afterwards `clusters/poc/templates/argocd.yaml` takes over,
  reading the *same* values file, so the two cannot drift.
- **Chart pinning.** The KrakenD chart is community-maintained and consumed straight
  from Git at a fixed commit (`clusters/poc/values.yaml`). Bump the SHA in a pull
  request; upstream changes can never reach the cluster unreviewed.
- **State.** The OpenTofu state is local (`infra/terraform.tfstate`, gitignored).
  A shared environment wants a remote backend — S3, GCS, or Terraform Cloud.
- **Secrets.** Nothing here needs one. Real gateways do (upstream credentials, JWT
  keys) — add Sealed Secrets or External Secrets before you put any in Git.
- **TLS.** Argo CD runs with `server.insecure: true` behind a plain HTTP ingress.
  Terminate TLS properly (cert-manager) for anything shared.
- **Multiple environments.** Copy `clusters/poc/` to `clusters/staging/`, give it its
  own values file, and point a second root Application at it — or replace both with
  an `ApplicationSet`.
