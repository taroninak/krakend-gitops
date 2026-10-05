#!/usr/bin/env python3
"""Fail loudly if a gateway response is not what make smoke expects.

Usage: curl ... | assert-json.py participants=4 customer.customer_id==45

  key=N           key holds a list of N items
  a.b.c==value    the value at that path equals value (compared as text)

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

def at(path):
    node = body
    for part in path.split("."):
        node = node.get(part) if isinstance(node, dict) else None
    return node


failures = []
for spec in sys.argv[1:]:
    if "==" in spec:
        path, want = spec.split("==", 1)
        got = at(path)
        if str(got) != want:
            failures.append("%s: expected %s, got %r" % (path, want, got))
    else:
        key, want = spec.split("=", 1)
        got = body.get(key)
        size = len(got) if isinstance(got, list) else None
        if size != int(want):
            failures.append("%s: expected a list of %s, got %r" % (key, want, got if size is None else size))

if failures:
    sys.exit("FAIL: " + "; ".join(failures))

print("OK  " + "  ".join(sys.argv[1:]))
