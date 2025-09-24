#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
# Treat unset variables as an error when substituting.
# The return value of a pipeline is the status of the last command to exit with a non-zero status.
set -euo pipefail

if [ "$EUID" -ne 0 ]; then echo "You must run this script as root."; exit 1; fi

WORK_DIR=/opt/plugNmeet
ARCH=$(dpkg --print-architecture)

## https://github.com/mynaparrot/plugNmeet-client/releases/latest/download/client.zip
CLIENT_DOWNLOAD_URL="https://github.com/mynaparrot/plugNmeet-client/releases/latest/download/client.zip"
RECORDER_DOWNLOAD_URL="https://github.com/mynaparrot/plugNmeet-recorder/releases/latest/download"

if [ ! -d "$WORK_DIR" ]; then
  echo "Working directory ${WORK_DIR} not found. Is plugNmeet installed?"
  exit 1
fi

cd $WORK_DIR
apt update && apt upgrade -y && apt dist-upgrade -y
systemctl stop plugnmeet

## update containers
## https://stackoverflow.com/a/61362893/1281864
printf "\nupdating docker images\n"
sleep 1
docker compose pull
docker compose up -d --remove-orphans

# Prune unused docker objects
printf "\npruning unused docker objects\n"
docker system prune -f

## client update
# let's take backup first
printf "\nupdating client\n"
sleep 1

BACKUP_DIR="client_bk"
printf "Backing up current client to %s\n" "${BACKUP_DIR}"
# remove previous backup
rm -rf "${BACKUP_DIR}"

# take backup
mv -f client "${BACKUP_DIR}"
wget $CLIENT_DOWNLOAD_URL -O client.zip
unzip -o client.zip

printf "Restoring client configuration\n"
cp -f "${BACKUP_DIR}/dist/assets/config.js" client/dist/assets/config.js
rm -rf client.zip

# wait until plugNmeet api ready
printf "Waiting for plugNmeet API to be ready..."
while ! nc -z localhost 8080; do
  printf "."
  sleep 3 # wait before check again
done

## now restart service
systemctl restart plugnmeet

## recorder update
if [ -d "recorder" ]; then
  printf "\nupdating recorder\n"
  sleep 1
  systemctl stop plugnmeet-recorder

  # take backup
  FILENAME="plugnmeet-recorder-linux-${ARCH}"
  wget "${RECORDER_DOWNLOAD_URL}/${FILENAME}.zip" -O recorder_new.zip
  unzip recorder_new.zip -d recorder_new && rm recorder_new.zip

  # remove previous backup first
  rm -f recorder/plugnmeet-recorder.bak
  # backup by renaming, then copy new file
  mv -f recorder/plugnmeet-recorder recorder/plugnmeet-recorder.bak
  cp -f "recorder_new/${FILENAME}" recorder/plugnmeet-recorder
  rm -rf recorder_new

  systemctl start plugnmeet-recorder
fi

printf "\n\nUpdate completed successfully!\n"
