// events routes — data/events.json
//
//   GET /events/:id   an event, referring to people by id only
//
// Turning those ids into user objects is the gateway's job: /v1/events/{id}
// reads participant_ids and customer_ids from here and resolves each list with
// a single GET /users?ids=... batch call. The handler reads its data when the
// request arrives, the way it would query a database.
"use strict";

const express = require("express");
const { readData } = require("../data");

const router = express.Router();

router.get("/events/:id", async (req, res) => {
  const { events } = await readData("events.json");
  const event = events.find((e) => e.event_id === req.params.id);

  if (!event) {
    return res.status(404).json({ error: "no such event", event_id: req.params.id });
  }
  res.json(event);
});

module.exports = router;
