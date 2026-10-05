// orders routes — data/orders.json
//
//   GET /orders/:orderId                one order, including whose it is
//   GET /customers/:customerId/orders   a customer's orders, with a count and total
//
// orders.json is one row per order, each with a customer_id, like a database
// table. Each handler reads it when the request arrives and picks the rows it
// needs — by order id, or WHERE customer_id = :customerId.
"use strict";

const express = require("express");
const { readData } = require("../data");

const router = express.Router();

router.get("/orders/:orderId", async (req, res) => {
  const { orders } = await readData("orders.json");
  const order = orders.find((o) => o.id === req.params.orderId);

  if (!order) {
    return res.status(404).json({ error: "no such order", id: req.params.orderId });
  }
  res.json(order);
});

// A customer with no orders gets an empty list, not a 404: this service knows
// orders, not customers, so "no orders" is a valid answer.
router.get("/customers/:customerId/orders", async (req, res) => {
  const { orders } = await readData("orders.json");
  const customerOrders = orders.filter((order) => order.customer_id === req.params.customerId);

  const total = customerOrders.reduce((sum, order) => sum + order.total, 0);

  res.json({
    order_count: customerOrders.length,
    // Rounded to cents: summing prices in floating point drifts — 0.1 + 0.2 is
    // 0.30000000000000004 — and a total should read like money.
    lifetime_value: Math.round(total * 100) / 100,
    orders: customerOrders,
  });
});

module.exports = router;
