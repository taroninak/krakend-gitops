// events routes — data/events.json
//
//   GET /events?order_id=A-1006   every event for one order
//   GET /events/:id               an event: its participants by id, and the order it is about
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

// WHERE order_id = :order_id. Combining the participants of these events is the
// gateway's job — /v1/orders/{id} does it in KrakenD config, not here.
router.get("/events", async (req, res) => {
  const { events } = await readData("events.json");
  res.json({ events: events.filter((e) => e.order_id === req.query.order_id) });
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
