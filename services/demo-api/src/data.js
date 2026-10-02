// Loads the JSON document this instance serves.
//
// The data lives next to the Helm chart (apps/demo-api/data/*.json) and is
// mounted from a ConfigMap, so changing it is an ordinary Argo CD sync — no new
// image. Only code changes need a rebuild.
"use strict";

const fs = require("node:fs");

function loadData(file) {
  if (!file) throw new Error("DATA_FILE is not set");
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

module.exports = { loadData };
