#!/usr/bin/env node

/**
 * Get the port ui from the config.json and return to stdout
 * This script is in place of using `jq` on macOS
 * get-ui-port.js /path/to/config.json
 */

const fs = require('fs');

try {
  const configFile = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
  const port = configFile.platforms.find(x => x.platform === 'config').port;
  process.stdout.write(port.toString());
} catch (e) {
  process.exit(1);
}
