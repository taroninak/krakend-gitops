// users-api
//
//   GET /customer-ids        the id list the gateway reads first
//   GET /users/:id           one user
//   GET /users?ids=42,43     several users in ONE call — this batch form is what
//                            lets the gateway avoid one request per id
"use strict";

const express = require("express");

module.exports = function usersRouter({ customerIds, users }) {
  const router = express.Router();
  const usersById = new Map(users.map((user) => [user.customer_id, user]));

  router.get("/customer-ids", (req, res) => {
    res.json(customerIds);
  });

  router.get("/users", (req, res) => {
    // Accepts ?ids=42,43 and ?ids=42&ids=43 alike, and tolerates stray spaces.
    const requested = [req.query.ids ?? []]
      .flat()
      .flatMap((value) => String(value).split(","))
      .map((id) => id.trim())
      .filter(Boolean);

    if (requested.length === 0) {
      return res.json({ customers: users });
    }

    const found = requested.filter((id) => usersById.has(id)).map((id) => usersById.get(id));
    const missing = requested.filter((id) => !usersById.has(id));

    res.json({
      customers: found,
      requested: requested.length,
      returned: found.length,
      // Only present when something was asked for that does not exist, so the
      // gateway can tell the caller instead of silently dropping it.
      ...(missing.length > 0 && { missing }),
    });
  });

  router.get("/users/:id", (req, res) => {
    const user = usersById.get(req.params.id);
    if (!user) {
      return res.status(404).json({ error: "no such record", customer_id: req.params.id });
    }
    res.json(user);
  });

  return router;
};
