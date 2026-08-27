output "cluster_name" {
  description = "kind cluster name (kubectl context is kind-<name>)"
  value       = kind_cluster.this.name
}

output "kubectl_context" {
  value = "kind-${kind_cluster.this.name}"
}

output "argocd_url" {
  value = "http://argocd.localhost:${var.http_port}"
}

output "gateway_url" {
  value = "http://api.localhost:${var.http_port}"
}

output "argocd_password_command" {
  description = "How to read the initial admin password"
  value       = "kubectl -n ${var.argocd_namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

output "gitops_repo_url" {
  description = "Repository Argo CD pulls from; everything else lives there"
  value       = var.gitops_repo_url
}
