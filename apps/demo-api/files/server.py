"""A demo API small enough to read in one sitting.

Serves two kinds of thing, both described in the chart's values:

  routes   fixed JSON documents at fixed paths
  records  id-addressable objects, available one at a time (/users/42) or
           several at once (/users?ids=42,43,44)

The batch form is the point: it lets a gateway fetch any number of records in a
single call instead of one call per id. Standard library only, so the chart can
mount this beside a stock python image with nothing to build.
"""
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

PORT = int(os.environ.get("PORT", "8080"))
with open(os.environ.get("DATA_FILE", "/config/data.json")) as fh:
    DATA = json.load(fh)

ROUTES = DATA.get("routes", [])
RECORDS = DATA.get("records") or {}
ITEMS = RECORDS.get("items", [])
ID_KEY = RECORDS.get("key", "id")
COLLECTION_KEY = RECORDS.get("collectionKey", "items")
BY_ID = {str(item[ID_KEY]): item for item in ITEMS}


def resolve(path, query):
    if path == "/healthz":
        return 200, {"status": "ok", "records": len(BY_ID)}

    for route in ROUTES:
        if route.get("exact"):
            if path == route["path"]:
                return 200, route["response"]
        elif path.startswith(route["path"]):
            return 200, route["response"]

    if RECORDS:
        base = RECORDS["path"]

        # /users?ids=42,43,44 — every requested record in one response.
        if path == base:
            raw = query.get("ids", [""])[0]
            wanted = [i for i in (p.strip() for p in raw.split(",")) if i]
            if not wanted:
                return 200, {COLLECTION_KEY: list(ITEMS)}
            found = [BY_ID[i] for i in wanted if i in BY_ID]
            missing = [i for i in wanted if i not in BY_ID]
            body = {COLLECTION_KEY: found, "requested": len(wanted), "returned": len(found)}
            if missing:
                body["missing"] = missing
            return 200, body

        # /users/42 — one record.
        if path.startswith(base + "/"):
            key = path[len(base) + 1:]
            if key in BY_ID:
                return 200, BY_ID[key]
            return 404, {"error": "no such record", ID_KEY: key}

    return 404, {"error": "no such path", "path": path}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        parsed = urlparse(self.path)
        status, body = resolve(parsed.path, parse_qs(parsed.query))
        payload = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, fmt, *args):
        # One line per upstream call, so `kubectl logs` shows how many calls the
        # gateway actually made.
        print("%s %s" % (self.command, self.path), flush=True)


if __name__ == "__main__":
    print("serving %d records and %d routes on :%d" % (len(BY_ID), len(ROUTES), PORT), flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
