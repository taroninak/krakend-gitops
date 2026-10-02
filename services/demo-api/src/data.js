// readData("users.json") — stands in for a database query.
//
// The JSON files in data/ play the part of the database. Handlers call this on
// every request instead of loading everything at startup, so each route shows,
// right where it uses the data, which file it comes from.
"use strict";

const fs = require("node:fs/promises");
const path = require("node:path");

const DATA_DIR = path.join(__dirname, "..", "data");

async function readData(file) {
  return JSON.parse(await fs.readFile(path.join(DATA_DIR, file), "utf8"));
}

module.exports = { readData };
