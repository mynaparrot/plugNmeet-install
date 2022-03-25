#!/bin/bash -e

if [ $EUID != 0 ]; then echo "You must run this script as root."; fi

WORK_DIR=/opt/plugNmeet

## https://github.com/mynaparrot/plugNmeet-client/releases/latest/download/client.zip
CLIENT_DOWNLOAD_URL="https://github.com/mynaparrot/plugNmeet-client/releases/latest/download/client.zip"
RECORDER_DOWNLOAD_URL="https://github.com/mynaparrot/plugNmeet-recorder/releases/latest/download/recorder.zip"

if [ ! -d "$WORK_DIR" ]; then
  echo "Didn't find working directory. exiting.."
  exit 1
fi

cd $WORK_DIR
apt update && apt upgrade -y && apt dist-upgrade -y
service plugnmeet stop

## update containers
## https://stackoverflow.com/a/61362893/1281864
printf "\nupdating docker images\n"
sleep 1
docker-compose pull
docker-compose up -d --remove-orphans
docker image prune -f

## client update
# let's take backup first
printf "\nupdating client\n"
sleep 1
mv -f client client_bk
wget $CLIENT_DOWNLOAD_URL -O client.zip
unzip -o client.zip

cp -f client_bk/dist/assets/config.js client/dist/assets/config.js
rm -rf client_bk client.zip

service plugnmeet restart

## recorder update
if [ -d "recorder" ]; then
  printf "\nupdating recorder\n"
  sleep 1
  service plugnmeet-recorder stop
  
  mv -f recorder recorder_bk
  wget $RECORDER_DOWNLOAD_URL -O recorder.zip
  unzip -o recorder.zip
  
  cp -f recorder_bk/config.yaml recorder/config.yaml
  npm install -C recorder
  rm -rf recorder_bk recorder.zip
  
  service plugnmeet-recorder start
fi

printf "\n\nupdate completed!\n"
