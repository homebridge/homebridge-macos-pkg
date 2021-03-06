#!/bin/sh

#
# Attempt to create a backup pre-installation that will automatically be restored to the new instance
#

. "/Library/Application Support/Homebridge/source.sh"
. "$HB_APP_PATH/scripts/functions.sh"

HB_BACKUP_PATH="/tmp/homebridge-macos-pkg"
HB_BACKUP_FILE_PATH="$HB_BACKUP_PATH/homebridge-macos-pkg-backup.tar.gz"

if [ ! -f $HOME/.homebridge/config.json ] || [ ! -f $HOME/.homebridge/.uix-secrets ]; then
  exit 0
fi

PORT=$(node "$HB_APP_PATH/scripts/get-ui-port.js" $HOME/.homebridge/config.json)
if [ "$?" != "0" ]; then
  >&2 echo "Cannot get port from config"
  exit 0
fi

SECRET_KEY=$(node "$HB_APP_PATH/scripts/get-uix-secret-key.js" $HOME/.homebridge/.uix-secrets)
if [ "$?" != "0" ]; then
  >&2 echo "Cannot get secret key"
  exit 0
fi

TOKEN=$(hb_generate_auth_token $SECRET_KEY)

mkdir -p $HB_BACKUP_PATH

for protocol in "http" "https"; do
  echo "Trying to get backup via $protocol..."
  curl -sSfk -H "Authorization: Bearer $TOKEN" -o "$HB_BACKUP_FILE_PATH" "$protocol://localhost:$PORT/api/backup/download"
  if [ "$?" = "0" ]; then
    echo "Backup saved to $HB_BACKUP_FILE_PATH"
    break
  fi
done

exit 0
