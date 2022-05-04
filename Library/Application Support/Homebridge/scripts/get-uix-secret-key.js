#!/usr/bin/env node

const fs = require('fs');

try {
  const secretFile = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
  process.stdout.write(secretFile.secretKey);
  process.exit(0);
} catch (e) {
  process.exit(1);
}
