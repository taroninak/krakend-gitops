// demo-api: one small Express app that plays any of the upstream services
// behind the gateway. SERVICE picks which routes to mount and which file in
// data/ they serve.
//
//   SERVICE=users node src/server.js
"use strict";

const express = require("express");
const { loadData } = require("./data");

const services = {
  users: require("./routes/users"),
  orders: require("./routes/orders"),
  events: require("./routes/events"),
};

const SERVICE = process.env.SERVICE;
const PORT = Number(process.env.PORT || 8080);

if (!services[SERVICE]) {
  console.error(`SERVICE must be one of: ${Object.keys(services).join(", ")} (got "${SERVICE}")`);
  process.exit(1);
}

const data = loadData(SERVICE);
const app = express();

// One line per request, so `kubectl logs` shows exactly how many calls the
// gateway made.
app.use((req, res, next) => {
  console.log(`${req.method} ${req.originalUrl}`);
  next();
});

// Read-only API: say so plainly rather than falling through to a 404.
app.use((req, res, next) => {
  if (req.method === "GET" || req.method === "HEAD") return next();
  res.set("Allow", "GET").status(405).json({ error: "method not allowed", method: req.method });
});

app.get("/healthz", (req, res) => {
  res.json({ status: "ok", service: SERVICE });
});

app.use(services[SERVICE](data));

// Express answers unknown paths with an HTML page by default; keep it JSON.
app.use((req, res) => {
  res.status(404).json({ error: "no such path", path: req.path });
});

const server = app.listen(PORT, () => {
  console.log(`${SERVICE}-api listening on :${PORT}`);
});

// As PID 1 in a container Node gets no default SIGTERM handling, so without
// this every rollout would wait out the full termination grace period.
process.on("SIGTERM", () => server.close(() => process.exit(0)));
