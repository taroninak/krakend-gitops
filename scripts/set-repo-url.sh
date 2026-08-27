#!/usr/bin/env bash
# Rewrites the placeholder Git URL across the repository.
# Every Argo CD Application has to know where its manifests live, so the URL
# appears in several files — this keeps them consistent.
set -euo pipefail

PLACEHOLDER="https://github.com/YOUR-ORG/krakend-gitops.git"
NEW_URL="${1:-}"

if [[ -z "$NEW_URL" ]]; then
  echo "usage: $0 <git-repo-url>" >&2
  echo "example: $0 https://github.com/acme/krakend-gitops.git" >&2
  exit 1
fi

cd "$(dirname "$0")/.."

CURRENT=$(grep -rhoE 'https://github\.com/[^ ]+krakend-gitops\.git' bootstrap clusters 2>/dev/null | sort -u | head -1)
CURRENT="${CURRENT:-$PLACEHOLDER}"

if [[ "$CURRENT" == "$NEW_URL" ]]; then
  echo "Repo URL already set to $NEW_URL"
  exit 0
fi

FILES=$(grep -rl "$CURRENT" bootstrap clusters)
for f in $FILES; do
  sed -i '' -e "s|$CURRENT|$NEW_URL|g" "$f" 2>/dev/null || sed -i -e "s|$CURRENT|$NEW_URL|g" "$f"
  echo "updated $f"
done

echo
echo "Repo URL is now: $NEW_URL"
echo "Commit and push, then run: make bootstrap"
