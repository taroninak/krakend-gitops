// orders routes (data/orders.json)
//
//   GET /orders/:customerId   the customer's order summary
//
// Every customer has the same order history in this demo; what matters here is
// that it comes from a different service than the user record.
"use strict";

const express = require("express");

module.exports = function ordersRouter({ orders }) {
  const router = express.Router();

  router.get("/orders/:customerId", (req, res) => {
    res.json(orders);
  });

  return router;
};
