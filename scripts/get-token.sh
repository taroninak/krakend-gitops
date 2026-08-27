#!/usr/bin/env bash
# Prints an access token for the krakend-demo service client in the poc realm.
#
# Nothing secret is stored in Git: the admin password comes from the Secret
# OpenTofu created, and the client secret is read from Keycloak's admin API.
set -euo pipefail

KC_URL="${KC_URL:-http://keycloak.localhost:8080}"
REALM="${REALM:-poc}"
CLIENT_ID="${CLIENT_ID:-krakend-demo}"
IAM_NS="${IAM_NS:-iam}"

admin_user=$(kubectl -n "$IAM_NS" get secret keycloak-admin \
  -o jsonpath='{.data.KC_BOOTSTRAP_ADMIN_USERNAME}' | base64 -d)
admin_pass=$(kubectl -n "$IAM_NS" get secret keycloak-admin \
  -o jsonpath='{.data.KC_BOOTSTRAP_ADMIN_PASSWORD}' | base64 -d)

admin_token=$(curl -fsS -X POST \
  "$KC_URL/realms/master/protocol/openid-connect/token" \
  -d "client_id=admin-cli" \
  -d "username=$admin_user" \
  -d "password=$admin_pass" \
  -d "grant_type=password" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')

client_uuid=$(curl -fsS \
  -H "Authorization: Bearer $admin_token" \
  "$KC_URL/admin/realms/$REALM/clients?clientId=$CLIENT_ID" \
  | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -1)

if [[ -z "$client_uuid" ]]; then
  echo "client $CLIENT_ID not found in realm $REALM" >&2
  exit 1
fi

client_secret=$(curl -fsS \
  -H "Authorization: Bearer $admin_token" \
  "$KC_URL/admin/realms/$REALM/clients/$client_uuid/client-secret" \
  | sed -n 's/.*"value":"\([^"]*\)".*/\1/p')

curl -fsS -X POST \
  "$KC_URL/realms/$REALM/protocol/openid-connect/token" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$client_secret" \
  -d "grant_type=client_credentials" \
  | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p'
