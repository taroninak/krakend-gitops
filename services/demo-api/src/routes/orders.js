// orders routes — data/orders.json
//
//   GET /orders/:customerId   the customer's order summary
//
// Every customer has the same order history in this demo; what matters is that
// the gateway fetches it separately from the user record and merges the two.
// The handler reads its data when the request arrives, the way it would query
// a database.
"use strict";

const express = require("express");
const { readData } = require("../data");

const router = express.Router();

router.get("/orders/:customerId", async (req, res) => {
  const { orders } = await readData("orders.json");
  res.json(orders);
});

module.exports = router;
