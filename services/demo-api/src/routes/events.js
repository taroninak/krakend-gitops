// events routes (data/events.json)
//
//   GET /events/:id   an event, referring to people by id only
//
// Turning those ids into user objects is the gateway's job: /v1/events/{id}
// reads participant_ids and customer_ids from here and resolves each list with
// a single GET /users?ids=... batch call.
"use strict";

const express = require("express");

module.exports = function eventsRouter({ events }) {
  const router = express.Router();
  const eventsById = new Map(events.map((event) => [event.event_id, event]));

  router.get("/events/:id", (req, res) => {
    const event = eventsById.get(req.params.id);
    if (!event) {
      return res.status(404).json({ error: "no such event", event_id: req.params.id });
    }
    res.json(event);
  });

  return router;
};
