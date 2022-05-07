#!/bin/bash

#
# Restore the backup made pre-installation
#

. "/Library/Application Support/Homebridge/source.sh"
. "$HB_APP_PATH/scripts/functions.sh"

HB_BACKUP_PATH="/tmp/homebridge-macos-pkg"
HB_BACKUP_FILE_PATH="$HB_BACKUP_PATH/homebridge-macos-pkg-backup.tar.gz"

if [ ! -f $HB_BACKUP_FILE_PATH ]; then
  exit 0
fi

# wait for homebridge to start
retrymax=24f
retrycount=0

echo "Waiting for Homebridge to come online..."

PORT=8581

until $(curl --output /dev/null --silent --head --fail http://localhost:$PORT/api); do
  printf '.'
  let "retrycount++"
  if [ "$retrycount" = "$retrymax" ]; then
    echo
    >&2 echo "ERROR: Timed out waiting for Homebridge UI to come online.";
    exit 0;
  fi
  sleep 1
done

echo "Homebridge online!"
sleep 10

SECRET_KEY=$(node "$HB_APP_PATH/scripts/get-uix-secret-key.js" $HB_SERVICE_STORAGE_PATH/.uix-secrets)
TOKEN=$(hb_generate_auth_token $SECRET_KEY)

curl -fsS -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: multipart/form-data" \
  -F "file=@$HB_BACKUP_FILE_PATH" \
  "http://localhost:$PORT/api/backup/restore" 

if [ "$?" = "0" ]; then
  echo "Backup file uploaded";
fi

echo "Starting restore..."

curl -fSs -X PUT -H "Authorization: Bearer $TOKEN" "http://localhost:$PORT/api/backup/restore/trigger"

if [ "$?" = "0" ]; then
  echo "Backup restore complete";
fi

# move backup to user trash
chown $USER: "$HB_BACKUP_FILE_PATH"
mv "$HB_BACKUP_FILE_PATH" "$HOME/.Trash/"

# cleanup
rm -rf "$HB_BACKUP_PATH"

if [ "$?" != "0" ]; then
  echo "Failed to delete backup file";
fi

exit 0
