#!/usr/bin/env bash
# Deletes the poc realm and restarts Keycloak so `--import-realm` seeds it again
# from apps/keycloak/files/realm-poc.json.
#
# WHY THIS EXISTS: --import-realm only imports a realm the database does not
# already have, so a change to the realm JSON does not reach a running Keycloak.
# This is the blunt way to apply one. It DESTROYS everything in the realm —
# users you created in the console included. For continuous reconciliation of
# realm config from Git, add keycloak-config-cli as a sync hook instead.
set -euo pipefail

IAM_NS="${IAM_NS:-iam}"
KC_URL="${KC_URL:-http://keycloak.localhost:8080}"
REALM="${REALM:-poc}"

read -r -p "Delete realm '$REALM' and re-import it from Git? Users in it are lost. [y/N] " reply
[[ "$reply" == "y" || "$reply" == "Y" ]] || { echo "aborted"; exit 1; }

admin_user=$(kubectl -n "$IAM_NS" get secret keycloak-admin -o jsonpath='{.data.KC_BOOTSTRAP_ADMIN_USERNAME}' | base64 -d)
admin_pass=$(kubectl -n "$IAM_NS" get secret keycloak-admin -o jsonpath='{.data.KC_BOOTSTRAP_ADMIN_PASSWORD}' | base64 -d)

token=$(curl -fsS -X POST "$KC_URL/realms/master/protocol/openid-connect/token" \
  -d client_id=admin-cli -d "username=$admin_user" -d "password=$admin_pass" -d grant_type=password \
  | python3 -c "import json,sys;print(json.load(sys.stdin)['access_token'])")

echo "deleting realm $REALM..."
curl -fsS -X DELETE -H "Authorization: Bearer $token" "$KC_URL/admin/realms/$REALM" || true

echo "restarting Keycloak so the import runs..."
kubectl -n "$IAM_NS" delete pod -l app.kubernetes.io/name=keycloakx --wait=false
kubectl -n "$IAM_NS" rollout status statefulset/keycloak-keycloakx --timeout=300s

echo "waiting for the realm to come back..."
until curl -fsS -o /dev/null "$KC_URL/realms/$REALM/.well-known/openid-configuration"; do sleep 3; done
echo "realm $REALM re-imported"
