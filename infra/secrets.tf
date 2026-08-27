# Bootstrap credentials for Keycloak.
#
# These are the one thing that cannot live in Git. OpenTofu generates them and
# writes them into the cluster; the Helm values in apps/keycloak/values.yaml
# reference the Secrets by name only.
#
# For anything shared, replace this with Sealed Secrets / External Secrets and
# let Argo CD deliver them like everything else.

resource "kubernetes_namespace" "iam" {
  metadata {
    name = var.iam_namespace
  }
}

resource "random_password" "keycloak_admin" {
  length  = 24
  special = false
}

resource "kubernetes_secret" "keycloak_admin" {
  metadata {
    name      = "keycloak-admin"
    namespace = kubernetes_namespace.iam.metadata[0].name
  }

  data = {
    KC_BOOTSTRAP_ADMIN_USERNAME = "admin"
    KC_BOOTSTRAP_ADMIN_PASSWORD = random_password.keycloak_admin.result
  }
}

resource "random_password" "keycloak_db" {
  length  = 32
  special = false
}

resource "kubernetes_secret" "keycloak_db" {
  metadata {
    name      = "keycloak-db"
    namespace = kubernetes_namespace.iam.metadata[0].name
  }

  data = {
    password = random_password.keycloak_db.result
  }
}
