#!/usr/bin/env bash
# Usage: assert-rate-limit.sh <url> <requests> [curl args...]
#
# Sends <requests> requests as fast as possible and fails unless at least one
# is rejected with 429. Used by make smoke for the per-organization limit on
# /v1/orders/{id}: 10 a minute per organization, counted separately by each
# KrakenD replica — with 2 replicas at most 20 pass, so 21 must hit the limit
# whichever replica serves each request.
set -euo pipefail
url=$1; count=$2; shift 2

ok=0; limited=0; other=0
for _ in $(seq 1 "$count"); do
  case "$(curl -s -o /dev/null -w '%{http_code}' "$@" "$url")" in
    200) ok=$((ok + 1)) ;;
    429) limited=$((limited + 1)) ;;
    *)   other=$((other + 1)) ;;
  esac
done

summary="$count requests: $ok x 200, $limited x 429, $other other"
if [ "$limited" -ge 1 ] && [ "$other" -eq 0 ]; then
  echo "OK  $summary"
else
  echo "FAIL: expected at least one 429 and nothing but 200/429 — $summary"
  exit 1
fi
