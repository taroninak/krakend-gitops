// Loads one of the JSON documents in data/.
//
// The data ships inside the image, right next to the code that serves it:
// changing what demo-api returns is a change to demo-api, released like any
// other — bump the version and let CI build it.
"use strict";

const fs = require("node:fs");
const path = require("node:path");

const DATA_DIR = path.join(__dirname, "..", "data");

function loadData(name) {
  return JSON.parse(fs.readFileSync(path.join(DATA_DIR, `${name}.json`), "utf8"));
}

module.exports = { loadData };
