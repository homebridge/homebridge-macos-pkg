#!/usr/bin/env node

/**
 * Checks if the provided file is valid JSON
 * This script is in place of using `jq` on macOS
 * is-valid-json.js /path/to/file.json
 */

const fs = require('fs');

try {
  const config = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
  if (typeof config === 'object') {
    process.exit(0);
  } else {
    process.exit(1);
  }
} catch (e) {
  process.exit(1);
}
