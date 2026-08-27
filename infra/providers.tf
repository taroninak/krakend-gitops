provider "kind" {}

# The Helm provider talks to the cluster created above using the credentials the
# kind provider exports — no kubeconfig file involved, so a fresh clone works.
provider "helm" {
  kubernetes = {
    host                   = kind_cluster.this.endpoint
    client_certificate     = kind_cluster.this.client_certificate
    client_key             = kind_cluster.this.client_key
    cluster_ca_certificate = kind_cluster.this.cluster_ca_certificate
  }
}
