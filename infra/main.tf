# ─────────────────────────────────────────────────────────────────────────────
# 1. The cluster
# ─────────────────────────────────────────────────────────────────────────────
resource "kind_cluster" "this" {
  name           = var.cluster_name
  node_image     = var.node_image
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      # Marks the node as the one the ingress controller may bind host ports on.
      kubeadm_config_patches = [
        "kind: InitConfiguration\nnodeRegistration:\n  kubeletExtraArgs:\n    node-labels: \"ingress-ready=true\"\n"
      ]

      extra_port_mappings {
        container_port = 80
        host_port      = var.http_port
      }
      extra_port_mappings {
        container_port = 443
        host_port      = var.https_port
      }
    }

    node {
      role = "worker"
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. Ingress controller — kind has none of its own
# ─────────────────────────────────────────────────────────────────────────────
resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.ingress_nginx_chart_version
  namespace        = "ingress-nginx"
  create_namespace = true

  values = [file("${path.module}/values/ingress-nginx.yaml")]

  wait    = true
  timeout = 600
}

# ─────────────────────────────────────────────────────────────────────────────
# 3. Argo CD — the last thing Terraform installs into the cluster
#
# The values file is shared with clusters/poc/templates/argocd.yaml, the
# Application through which Argo CD manages its own installation afterwards.
# ─────────────────────────────────────────────────────────────────────────────
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = var.argocd_namespace
  create_namespace = true

  values = [file("${path.module}/../platform/argocd/values.yaml")]

  wait    = true
  timeout = 900

  depends_on = [helm_release.ingress_nginx]
}

# ─────────────────────────────────────────────────────────────────────────────
# 4. Hand over to Git
#
# A one-template chart holding the root Application. This is the last thing
# Terraform knows about: everything else is pulled from the repository below.
# ─────────────────────────────────────────────────────────────────────────────
resource "helm_release" "argocd_bootstrap" {
  name      = "argocd-bootstrap"
  chart     = "${path.module}/charts/argocd-bootstrap"
  namespace = var.argocd_namespace

  set = [
    {
      name  = "repoURL"
      value = var.gitops_repo_url
    },
    {
      name  = "targetRevision"
      value = var.gitops_revision
    },
    {
      name  = "path"
      value = var.gitops_path
    },
    {
      name  = "argocdNamespace"
      value = var.argocd_namespace
    },
  ]

  depends_on = [helm_release.argocd]
}
