#!/bin/sh

export HB_APP_PATH="/Library/Application Support/Homebridge"
export HB_SERVICE_STORAGE_PATH="/Users/Shared/Homebridge"
export HOMEBRIDGE_PLIST_PATH="/Library/LaunchDaemons/io.homebridge.server.plist"

export HB_PKG_ARCH="$(uname -m)"
export NODE_BIN_PATH="$HB_APP_PATH/node-$HB_PKG_ARCH/bin"
export HB_BIN_PATH="$HB_SERVICE_STORAGE_PATH/node_modules/.bin"

export PATH="$HB_BIN_PATH:$NODE_BIN_PATH:$PATH"

export npm_config_global_style=true
export npm_config_audit=false
export npm_config_fund=false
export npm_config_update_notifier=false
export npm_config_store_dir="$HB_SERVICE_STORAGE_PATH/node_modules/.pnpm-store"
export npm_config_prefix="$HB_APP_PATH/node-$HB_PKG_ARCH"
export npm_config_global_pnpmfile="$HB_APP_PATH/global_pnpmfile.cjs"

export HOMEBRIDGE_MACOS_PACKAGE=1
export UIX_CUSTOM_PLUGIN_PATH=$HB_SERVICE_STORAGE_PATH/node_modules
export UIX_BASE_PATH_OVERRIDE=$HB_SERVICE_STORAGE_PATH/node_modules/homebridge-config-ui-x
export UIX_USE_PNPM=1
