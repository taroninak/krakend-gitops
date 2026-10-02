#!/usr/bin/env python3
"""Fail loudly if a gateway response does not have the expected list sizes.

Usage: curl ... | assert-json.py participants=4 customers=2

Exists because two gateway routes depend on KrakenD rendering a whole JSON array
as a comma-joined string inside a {resp0_...} placeholder. That is what 2.9.4
does, but it is not documented — so if an upgrade changes it, the batch calls
would silently return empty lists. This turns that into a failed smoke test.
"""
import json
import sys

raw = sys.stdin.read()
try:
    body = json.loads(raw)
except ValueError:
    sys.exit("FAIL: response is not JSON: %r" % raw[:200])

failures = []
for spec in sys.argv[1:]:
    key, want = spec.split("=")
    got = body.get(key)
    size = len(got) if isinstance(got, list) else None
    if size != int(want):
        failures.append("%s: expected a list of %s, got %r" % (key, want, got if size is None else size))

if failures:
    sys.exit("FAIL: " + "; ".join(failures))

print("OK  " + "  ".join("%s=%s" % tuple(s.split("=")) for s in sys.argv[1:]))
