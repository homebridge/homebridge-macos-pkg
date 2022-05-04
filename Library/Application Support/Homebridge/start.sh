#!/bin/sh

. "/Library/Application Support/Homebridge/source.sh"

HB_SERVICE_NODE_EXEC_PATH="$NODE_BIN_PATH/node"
HB_SERVICE_EXEC_PATH="$HB_SERVICE_STORAGE_PATH/node_modules/homebridge-config-ui-x/dist/bin/hb-service.js"

# check for missing homebridge-config-ui-x
if [ ! -f "$HB_SERVICE_EXEC_PATH" ]; then
  echo "Re-installing homebridge-config-ui-x..."
  pnpm -C $HB_SERVICE_STORAGE_PATH install --save homebridge-config-ui-x@latest
fi

# check for missing homebridge
if [ ! -f "$HB_SERVICE_STORAGE_PATH/node_modules/homebridge/package.json" ]; then
  echo "Re-installing homebridge..."
  pnpm -C $HB_SERVICE_STORAGE_PATH install --save homebridge@latest
fi

exec "$HB_SERVICE_NODE_EXEC_PATH" "$HB_SERVICE_EXEC_PATH" run -I -U "$HB_SERVICE_STORAGE_PATH" -P "$HB_SERVICE_STORAGE_PATH/node_modules" --strict-plugin-resolution
