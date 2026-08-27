# KrakenD on Kubernetes, delivered by Argo CD

A self-contained proof of concept: a disposable Kubernetes cluster, Argo CD, and the
KrakenD API gateway — all described as code, all delivered by GitOps.

Nothing is installed by hand except Argo CD itself, and even that is handed back to
Git immediately afterwards (Argo CD manages its own installation from
`platform/argocd/values.yaml`).

```
                       git push
  you ──► GitHub repo ──────────► Argo CD ──► k3d cluster
                                     │
                                     ├── argocd    (manages itself)
                                     ├── krakend   (Helm chart + values from this repo)
                                     └── httpbin   (stand-in upstream API)
```

## Layout

| Path | What it is |
|------|------------|
| `bootstrap/k3d/cluster.yaml` | The cluster itself: k3s version, node count, published ports |
| `bootstrap/root-app.yaml` | The single `kubectl apply` of the whole POC — the "app of apps" |
| `clusters/poc/` | One Argo CD `Application` per workload, plus the `AppProject` |
| `platform/argocd/values.yaml` | Argo CD's own Helm values (used by the bootstrap **and** by Argo CD itself) |
| `apps/krakend/values.yaml` | KrakenD Helm values **and** the gateway configuration (routes, backends, rate limits) |
| `apps/httpbin/` | Plain manifests (Kustomize) for the demo upstream API |
| `scripts/set-repo-url.sh` | Rewrites the Git URL across the Applications |

Everything under `clusters/poc/` is discovered recursively by the root Application, so
adding a workload means adding one file there — no further `kubectl` involved.

## Prerequisites

`docker`, `k3d`, `kubectl`, `helm` (and optionally the `argocd` CLI):

```bash
brew install k3d kubernetes-cli helm argocd
```

## Run it

```bash
make repo-url REPO_URL=https://github.com/YOUR-ORG/krakend-gitops.git
git commit -am "point at my repo" && git push
make up
```

`make up` creates the cluster, installs Argo CD, and applies the root Application.
From that point Argo CD pulls everything else from Git.

```bash
make status     # what Argo CD thinks of the world
make password   # initial admin password (user: admin)
make ui         # http://argocd.localhost:8080
make smoke      # call the gateway through the ingress
make down       # delete the cluster
```

The ingress hostnames resolve to `127.0.0.1` on macOS by default. If your resolver
disagrees, add them to `/etc/hosts`:

```
127.0.0.1 argocd.localhost api.localhost
```

## The gateway

`apps/krakend/values.yaml` holds both the Helm values and the KrakenD configuration.
Two endpoints are exposed:

| Endpoint | Behaviour |
|----------|-----------|
| `GET /v1/uuid` | Straight proxy to the upstream `/uuid` |
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

`make lint` renders every manifest locally — including the pinned upstream chart — so
a bad change fails before it reaches the cluster.

## Notes for going beyond the POC

- **Chart pinning.** The KrakenD chart is community-maintained and consumed straight
  from Git at a fixed commit (`clusters/poc/krakend.yaml`), so upstream changes can
  never reach the cluster unreviewed. Bump the SHA in a pull request.
- **Secrets.** Nothing here needs one. Real gateways do (upstream credentials, JWT
  keys) — add Sealed Secrets or External Secrets before you put any in Git.
- **TLS.** Argo CD runs with `server.insecure: true` behind a plain HTTP ingress.
  Terminate TLS properly (cert-manager) for anything shared.
- **Multiple environments.** Copy `clusters/poc/` to `clusters/staging/`, give it its
  own settings file, and point a second root Application at it — or replace both with
  an `ApplicationSet`.
