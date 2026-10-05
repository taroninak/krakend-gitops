// demo-api — the upstream services behind the KrakenD gateway, in one small
// Express app. Every route the gateway calls is listed here:
//
//   route                               code                data
//   GET /customers                      routes/users.js     data/users.json + orders.json
//   GET /users/:id                      routes/users.js     data/users.json
//   GET /users?ids=42,43                routes/users.js     data/users.json
//   GET /orders/:orderId                routes/orders.js    data/orders.json
//   GET /customers/:customerId/orders   routes/orders.js    data/orders.json
//   GET /events?order_id=A-1006,A-1008  routes/events.js    data/events.json
//   GET /events/:id                     routes/events.js    data/events.json
//
// Each request is logged with its status and duration, so
// `kubectl -n demo logs deploy/demo-api` shows every call a gateway request
// turned into, in order.
"use strict";

const express = require("express");
const usersRouter = require("./routes/users");
const ordersRouter = require("./routes/orders");
const eventsRouter = require("./routes/events");

const PORT = Number(process.env.PORT || 8080);
const app = express();

app.use((req, res, next) => {
  const started = process.hrtime.bigint();
  res.on("finish", () => {
    const ms = Number(process.hrtime.bigint() - started) / 1e6;
    console.log(`${req.method} ${req.originalUrl} -> ${res.statusCode} (${ms.toFixed(1)}ms)`);
  });
  next();
});

// Read-only API: say so plainly rather than falling through to a 404.
app.use((req, res, next) => {
  if (req.method === "GET" || req.method === "HEAD") return next();
  res.set("Allow", "GET").status(405).json({ error: "method not allowed", method: req.method });
});

app.get("/healthz", (req, res) => {
  res.json({ status: "ok" });
});

app.use(usersRouter);
app.use(ordersRouter);
app.use(eventsRouter);

// Express answers unknown paths with an HTML page by default; keep it JSON.
app.use((req, res) => {
  res.status(404).json({ error: "no such path", path: req.path });
});

// Same for failures: if a handler throws — say its data file is unreadable —
// Express 5 routes the rejected promise here, and the caller still gets JSON.
app.use((err, req, res, next) => {
  console.error(`${req.method} ${req.originalUrl} failed:`, err.message);
  res.status(500).json({ error: "internal error" });
});

const server = app.listen(PORT, () => {
  console.log(`demo-api listening on :${PORT}`);
});

// As PID 1 in a container Node gets no default SIGTERM handling, so without
// this every rollout would wait out the full termination grace period.
process.on("SIGTERM", () => server.close(() => process.exit(0)));
