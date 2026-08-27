variable "cluster_name" {
  description = "Name of the local kind cluster"
  type        = string
  default     = "krakend-poc"
}

variable "node_image" {
  description = "kind node image, pinned so every engineer gets the same Kubernetes"
  type        = string
  default     = "kindest/node:v1.35.8@sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0"
}

variable "http_port" {
  description = "Host port forwarded to the ingress controller (HTTP)"
  type        = number
  default     = 8080
}

variable "https_port" {
  description = "Host port forwarded to the ingress controller (HTTPS)"
  type        = number
  default     = 8443
}

variable "gitops_repo_url" {
  description = "Git repository Argo CD pulls everything else from"
  type        = string
}

variable "gitops_revision" {
  description = "Branch, tag or commit Argo CD tracks"
  type        = string
  default     = "main"
}

variable "gitops_path" {
  description = "Path in the repository holding the app-of-apps chart"
  type        = string
  default     = "clusters/poc"
}

variable "argocd_namespace" {
  description = "Namespace Argo CD is installed into"
  type        = string
  default     = "argocd"
}

variable "argocd_chart_version" {
  description = "argo-cd Helm chart version (keep in sync with clusters/poc/values.yaml)"
  type        = string
  default     = "10.4.0"
}

variable "ingress_nginx_chart_version" {
  description = "ingress-nginx Helm chart version"
  type        = string
  default     = "4.15.1"
}

variable "iam_namespace" {
  description = "Namespace Keycloak and its database run in"
  type        = string
  default     = "iam"
}
