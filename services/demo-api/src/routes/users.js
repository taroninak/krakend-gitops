// users routes — data/users.json
//
//   GET /customers           users with at least one order (joins orders.json)
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

// A customer is a user with at least one order: a join of users and orders.
// That is a database question, so it is answered here, not in the gateway.
router.get("/customers", async (req, res) => {
  const { users } = await readData("users.json");
  const { orders } = await readData("orders.json");

  const hasOrders = new Set(orders.map((order) => order.customer_id));
  res.json({ customers: users.filter((user) => hasOrders.has(user.customer_id)) });
});

router.get("/users", async (req, res) => {
  const { users } = await readData("users.json");

  // No ids parameter at all: every user.
  if (req.query.ids === undefined) {
    return res.json({ customers: users });
  }

  // Like WHERE customer_id IN (...): each matching user comes back once, however
  // often its id was asked for, and an empty list matches nobody. Accepts
  // ?ids=42,43 and ?ids=42&ids=43 alike, and tolerates stray spaces.
  const requested = new Set(
    [req.query.ids]
      .flat()
      .flatMap((value) => String(value).split(","))
      .map((id) => id.trim())
      .filter(Boolean),
  );

  const found = users.filter((user) => requested.has(user.customer_id));
  const missing = [...requested].filter((id) => !found.some((user) => user.customer_id === id));

  res.json({
    customers: found,
    requested: requested.size,
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
