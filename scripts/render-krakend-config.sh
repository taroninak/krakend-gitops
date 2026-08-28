#!/usr/bin/env bash
# Prints the gateway configuration exactly as the chart assembles it — the
# equivalent of KrakenD's FC_OUT. Useful for eyeballing the final document and
# for feeding `krakend check` in `make lint`.
set -euo pipefail

cd "$(dirname "$0")/.."

helm template krakend apps/krakend | python3 -c '
import sys
lines = sys.stdin.read().splitlines()
i = next(n for n, l in enumerate(lines) if l.strip() == "krakend.json: |")
out = []
for l in lines[i + 1:]:
    if l.startswith("    "):
        out.append(l[4:])
    elif not l.strip():
        out.append("")
    else:
        break
print("\n".join(out).rstrip())
'
