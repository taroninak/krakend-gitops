// A demo API small enough to read in one sitting.
//
// Serves two kinds of thing, both described in the chart's values:
//
//   routes   fixed JSON documents at fixed paths
//   records  id-addressable objects, available one at a time (/users/42) or
//            several at once (/users?ids=42,43,44)
//
// The batch form is the point: it lets a gateway fetch any number of records in
// a single call instead of one call per id. Node's standard library only, so the
// chart can mount this beside a stock node image with nothing to build.
"use strict";

const fs = require("node:fs");
const http = require("node:http");

const PORT = Number(process.env.PORT || 8080);
const DATA = JSON.parse(fs.readFileSync(process.env.DATA_FILE || "/config/data.json", "utf8"));

const ROUTES = DATA.routes || [];
const RECORDS = DATA.records || {};
const ITEMS = RECORDS.items || [];
const ID_KEY = RECORDS.key || "id";
const COLLECTION_KEY = RECORDS.collectionKey || "items";
const BY_ID = new Map(ITEMS.map((item) => [String(item[ID_KEY]), item]));

function resolve(path, query) {
  if (path === "/healthz") {
    return [200, { status: "ok", records: BY_ID.size }];
  }

  for (const route of ROUTES) {
    if (route.exact ? path === route.path : path.startsWith(route.path)) {
      return [200, route.response];
    }
  }

  if (RECORDS.path) {
    const base = RECORDS.path;

    // /users?ids=42,43,44 — every requested record in one response.
    if (path === base) {
      const wanted = (query.get("ids") || "")
        .split(",")
        .map((id) => id.trim())
        .filter(Boolean);
      if (wanted.length === 0) {
        return [200, { [COLLECTION_KEY]: ITEMS }];
      }
      const found = wanted.filter((id) => BY_ID.has(id)).map((id) => BY_ID.get(id));
      const missing = wanted.filter((id) => !BY_ID.has(id));
      const body = { [COLLECTION_KEY]: found, requested: wanted.length, returned: found.length };
      if (missing.length) body.missing = missing;
      return [200, body];
    }

    // /users/42 — one record.
    if (path.startsWith(base + "/")) {
      const key = path.slice(base.length + 1);
      if (BY_ID.has(key)) return [200, BY_ID.get(key)];
      return [404, { error: "no such record", [ID_KEY]: key }];
    }
  }

  return [404, { error: "no such path", path }];
}

function send(res, status, body, extraHeaders = {}) {
  const payload = Buffer.from(JSON.stringify(body));
  res.writeHead(status, {
    "Content-Type": "application/json",
    "Content-Length": payload.length,
    ...extraHeaders,
  });
  res.end(payload);
}

const server = http.createServer((req, res) => {
  // One line per upstream call, so `kubectl logs` shows how many calls the
  // gateway actually made.
  console.log(`${req.method} ${req.url}`);

  if (req.method !== "GET") {
    return send(res, 405, { error: "method not allowed", method: req.method }, { Allow: "GET" });
  }

  const url = new URL(req.url, "http://localhost");
  const [status, body] = resolve(url.pathname, url.searchParams);
  send(res, status, body);
});

// Node ignores SIGTERM when it runs as PID 1 in a container, so without this the
// pod would sit out the whole termination grace period on every rollout.
process.on("SIGTERM", () => server.close(() => process.exit(0)));

server.listen(PORT, "0.0.0.0", () => {
  console.log(`serving ${BY_ID.size} records and ${ROUTES.length} routes on :${PORT}`);
});
