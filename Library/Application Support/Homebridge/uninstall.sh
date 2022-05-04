#!/bin/sh

set -e

if [ -f "/Library/LaunchDaemons/io.homebridge.server.plist" ]; then
  launchctl unload -w "/Library/LaunchDaemons/io.homebridge.server.plist" &>/dev/null || true
fi

launchctl remove io.homebridge.server &>/dev/null || true

rm -rf "/Library/LaunchDaemons/io.homebridge.server.plist"
rm -rf "/Applications/Homebridge"
rm -rf "/Library/Application Support/Homebridge"
rm -rf "/Users/Shared/Homebridge"
rm -rf "/usr/local/bin/hb-shell"
rm -rf "/usr/local/bin/hb-service"
