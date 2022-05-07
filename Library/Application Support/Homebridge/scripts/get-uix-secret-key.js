#!/usr/bin/env node

/**
 * Get the jwt secret from the .uix-secrets file and return to stdout
 * This script is in place of using `jq` on macOS
 * get-uix-secret.js /path/to/.uix-secrets
 */

const fs = require('fs');

try {
  const secretFile = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
  process.stdout.write(secretFile.secretKey);
  process.exit(0);
} catch (e) {
  process.exit(1);
}
