// events routes — data/events.json
//
//   GET /events?order_id=A-1006,A-1008   every event for these orders
//   GET /events/:id                      an event: its participants by id, and the order it is about
//
// Resolving those references is the gateway's job. /v1/events/{id} reads this,
// fetches the participants with one GET /users?ids=... batch call, and follows
// order_id → GET /orders/:id → customer_id → GET /users/:id to the customer.
// The handler reads its data when the request arrives, the way it would query
// a database.
"use strict";

const express = require("express");
const { readData } = require("../data");

const router = express.Router();

// WHERE order_id IN (...): ?order_id=A-1006 or ?order_id=A-1006,A-1008, and an
// empty list matches nothing. Combining the participants of these events is the
// gateway's job, not this router's.
router.get("/events", async (req, res) => {
  const orderIds = new Set(
    String(req.query.order_id ?? "").split(",").map((id) => id.trim()).filter(Boolean),
  );
  const { events } = await readData("events.json");
  res.json({ events: events.filter((e) => orderIds.has(e.order_id)) });
});

router.get("/events/:id", async (req, res) => {
  const { events } = await readData("events.json");
  const event = events.find((e) => e.event_id === req.params.id);

  if (!event) {
    return res.status(404).json({ error: "no such event", event_id: req.params.id });
  }
  res.json(event);
});

module.exports = router;
