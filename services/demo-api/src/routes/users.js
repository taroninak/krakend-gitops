// users routes — data/users.json
//
//   GET /customer-ids        the id list the gateway reads first
//   GET /users/:id           one user
//   GET /users?ids=42,43     several users in ONE call — this batch form is what
//                            lets the gateway avoid one request per id
//
// Each handler reads its data when the request arrives, the way it would query
// a database. Nothing is loaded at startup or cached.
"use strict";

const express = require("express");
const { readData } = require("../data");

const router = express.Router();

router.get("/customer-ids", async (req, res) => {
  const { customerIds } = await readData("users.json");
  res.json(customerIds);
});

router.get("/users", async (req, res) => {
  // Accepts ?ids=42,43 and ?ids=42&ids=43 alike, and tolerates stray spaces.
  const requested = [req.query.ids ?? []]
    .flat()
    .flatMap((value) => String(value).split(","))
    .map((id) => id.trim())
    .filter(Boolean);

  const { users } = await readData("users.json");

  if (requested.length === 0) {
    return res.json({ customers: users });
  }

  const found = requested
    .map((id) => users.find((user) => user.customer_id === id))
    .filter(Boolean);
  const missing = requested.filter((id) => !users.some((user) => user.customer_id === id));

  res.json({
    customers: found,
    requested: requested.length,
    returned: found.length,
    // Only present when something was asked for that does not exist, so the
    // gateway can tell the caller instead of silently dropping it.
    ...(missing.length > 0 && { missing }),
  });
});

router.get("/users/:id", async (req, res) => {
  const { users } = await readData("users.json");
  const user = users.find((u) => u.customer_id === req.params.id);

  if (!user) {
    return res.status(404).json({ error: "no such record", customer_id: req.params.id });
  }
  res.json(user);
});

module.exports = router;
