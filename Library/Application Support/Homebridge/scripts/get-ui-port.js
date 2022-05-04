#!/usr/bin/env node

const fs = require('fs');

try {
  const configFile = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
  const port = configFile.platforms.find(x => x.platform === 'config').port;
  process.stdout.write(port.toString());
} catch (e) {
  process.exit(1);
}
