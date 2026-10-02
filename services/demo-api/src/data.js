// Loads the JSON document a service serves.
//
// The data ships inside the image (data/<service>.json), right next to the code
// that serves it: changing what a service returns is a change to the service,
// released like any other — bump the version and let CI build it.
"use strict";

const fs = require("node:fs");
const path = require("node:path");

const DATA_DIR = path.join(__dirname, "..", "data");

function loadData(service) {
  return JSON.parse(fs.readFileSync(path.join(DATA_DIR, `${service}.json`), "utf8"));
}

module.exports = { loadData };
