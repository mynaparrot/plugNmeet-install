#!/bin/bash -e

WORK_DIR=/opt/plugNmeet

## https://raw.githubusercontent.com/mynaparrot/plugNmeet-install/main/install-files
CONFIG_DOWNLOAD_URL="https://raw.githubusercontent.com/mynaparrot/plugNmeet-install/main/install-files"

## https://github.com/mynaparrot/plugNmeet-client/releases/latest/download/client.zip
CLIENT_DOWNLOAD_URL="https://github.com/mynaparrot/plugNmeet-client/releases/latest/download/client.zip"
RECORDER_DOWNLOAD_URL="https://github.com/mynaparrot/plugNmeet-recorder/releases/latest/download/recorder.zip"

## https://raw.githubusercontent.com/mynaparrot/plugNmeet-server/main/sql_dump/install.sql
SQL_DUMP_DOWNLOAD_URL="https://raw.githubusercontent.com/mynaparrot/plugNmeet-server/main/sql_dump/install.sql"

main() {
  can_run

  echo -n "Please enter plugNmeet server domain (exmple: plugnmeet.example.com): "
  read PLUG_N_MEET_SERVER_DOMAIN

  echo -n "Please enter livekit server domain (exmple: livekit.example.com): "
  read LIVEKIT_SERVER_DOMAIN

  echo -n "Please enter turn server domain (exmple: turn.example.com): "
  read TURN_SERVER_DOMAIN

  echo -n "Please enter valid email address: "
  read EMAIL_ADDRESS

  echo -n "Do you want to install recorder? y/n: "
  read RECORDER_INSTALL
  echo -n "Do you want to configure firewall(ufw)? y/n: "
  read CONFIGURE_UFW

  mkdir -p ${WORK_DIR}
  cd ${WORK_DIR}

  if ! which docker-compose > /dev/null; then
    install_docker
  fi

  install_haproxy
  prepare_server
  install_client

  if [ "$RECORDER_INSTALL" == "y" ]; then
    install_recorder
  fi

  if [ "$CONFIGURE_UFW" == "y" ]; then
    enable_ufw
  fi

  systemctl start plugnmeet
  ## database require little bit time
  echo ".."
  sleep 3
  echo "...."
  sleep 3
  echo "......"
  sleep 3
  echo "........"
  sleep 3
  echo "............"
  sleep 3

  ## need restart if mariadb took too much time to import
  systemctl restart plugnmeet
  
  if [ "$RECORDER_INSTALL" == "y" ]; then
    systemctl start plugnmeet-recorder
  fi

  clear
  printf "Installation completed!\n\n"
  printf "plugNmeet server URL: https://${PLUG_N_MEET_SERVER_DOMAIN}\n"
  printf "plugNmeet API KEY: ${PLUG_N_MEET_API_KEY}\n"
  printf "plugNmeet API SECRET: ${PLUG_N_MEET_SECRET}\n"
  printf "livekit server URL: https://${LIVEKIT_SERVER_DOMAIN}\n"
  
  printf "\n\nTo manage server: \n" 
  printf "systemctl stop plugnmeet or systemctl restart plugnmeet\n"
  
  if [ "$RECORDER_INSTALL" == "y" ]; then
    printf "\n\nTo manage recorder: \n"
    printf "systemctl stop plugnmeet-recorder or systemctl restart plugnmeet-recorder \n\n"
  fi

  printf "To test frontend: \n"
  printf "https://${PLUG_N_MEET_SERVER_DOMAIN}/login.html\n\n"

  printf "\nFor further performance tuning follow: \n" 
  printf "https://docs.livekit.io/deploy/test-monitor#kernel-parameters\n\n" 

}

random_key() {
  echo $(tr -dc A-Za-z0-9 < /dev/urandom | dd bs=$1 count=1 2>/dev/null)
}

install_docker() {
  apt -y install ca-certificates curl gnupg lsb-release

  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

  apt update
  apt -y install docker-ce docker-ce-cli containerd.io docker-compose
}

prepare_server() {
  wget ${CONFIG_DOWNLOAD_URL}/config.yaml -O config.yaml
  wget ${CONFIG_DOWNLOAD_URL}/livekit.yaml -O livekit.yaml
  wget ${CONFIG_DOWNLOAD_URL}/docker-compose.yaml -O docker-compose.yaml

  mkdir -p sql_dump
  wget ${SQL_DUMP_DOWNLOAD_URL} -O sql_dump/install.sql

  ## change livekit api & turn
  LIVEKIT_API_KEY=API$(random_key 11)
  LIVEKIT_SECRET=$(random_key 36)

  PLUG_N_MEET_API_KEY=API$(random_key 11)
  PLUG_N_MEET_SECRET=$(random_key 36)

  DB_ROOT_PASSWORD=$(random_key 20)
  sed -i "s/DB_ROOT_PASSWORD/$DB_ROOT_PASSWORD/g" docker-compose.yaml

  sed -i "s/LIVEKIT_API_KEY/$LIVEKIT_API_KEY/g" livekit.yaml
  sed -i "s/LIVEKIT_SECRET/$LIVEKIT_SECRET/g" livekit.yaml
  sed -i "s/TURN_SERVER_DOMAIN/$TURN_SERVER_DOMAIN/g" livekit.yaml

  sed -i "s/LIVEKIT_API_KEY/$LIVEKIT_API_KEY/g" config.yaml
  sed -i "s/LIVEKIT_SECRET/$LIVEKIT_SECRET/g" config.yaml
  sed -i "s/PLUG_N_MEET_API_KEY/$PLUG_N_MEET_API_KEY/g" config.yaml
  sed -i "s/PLUG_N_MEET_SECRET/$PLUG_N_MEET_SECRET/g" config.yaml
  sed -i "s/DB_ROOT_PASSWORD/$DB_ROOT_PASSWORD/g" config.yaml


  wget ${CONFIG_DOWNLOAD_URL}/plugnmeet.service -O /etc/systemd/system/plugnmeet.service
  systemctl daemon-reload
  systemctl enable plugnmeet
}

install_client() {
  wget $CLIENT_DOWNLOAD_URL -O client.zip
  unzip client.zip
  cp client/dist/assets/config_sample.js client/dist/assets/config.js

  sed -i "s/window.PLUG_N_MEET_SERVER_URL.*/window.PLUG_N_MEET_SERVER_URL = 'https:\/\/$PLUG_N_MEET_SERVER_DOMAIN'\;/g" \
      client/dist/assets/config.js
  sed -i "s/window.LIVEKIT_SERVER_URL.*/window.LIVEKIT_SERVER_URL = 'https:\/\/$LIVEKIT_SERVER_DOMAIN'\;/g" \
      client/dist/assets/config.js

  rm client.zip
}

prepare_recorder() {
  ## prepare chrome
  curl -sS -o - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add
  echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list

  ## prepare nodejs
  curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash -

  ## install require software
  apt -y update && apt -y install nodejs xvfb google-chrome-stable ffmpeg
}

install_recorder() {  
  wget $CONFIG_DOWNLOAD_URL/plugnmeet-recorder.service -O /etc/systemd/system/plugnmeet-recorder.service
  wget $CONFIG_DOWNLOAD_URL/plugnmeet-recorder@main.service -O /etc/systemd/system/plugnmeet-recorder@main.service
  wget $CONFIG_DOWNLOAD_URL/plugnmeet-recorder@websocket.service -O /etc/systemd/system/plugnmeet-recorder@websocket.service
  systemctl daemon-reload
  systemctl enable plugnmeet-recorder
  systemctl enable plugnmeet-recorder@main
  systemctl enable plugnmeet-recorder@websocket

  wget $RECORDER_DOWNLOAD_URL -O recorder.zip
  unzip recorder.zip
  cp recorder/config_sample.yaml recorder/config.yaml
  
  WEBSOCKET_AUTH_TOKEN=$(random_key 10)
  sed -i "s/join_host.*/join_host: \"https:\/\/$PLUG_N_MEET_SERVER_DOMAIN\/\?access_token=\"/g" recorder/config.yaml
  sed -i "s/WEBSOCKET_AUTH_TOKEN/$WEBSOCKET_AUTH_TOKEN/g" recorder/config.yaml

  prepare_recorder

  npm install -C recorder
  rm recorder.zip
}

install_haproxy() {
  add-apt-repository ppa:vbernat/haproxy-2.4 -y
  apt -y update && apt install -y haproxy
  service haproxy stop

  cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg_bk
  mkdir -p /etc/haproxy/ssl

  configure_lets_encrypt

  ln -s /etc/letsencrypt/live/${PLUG_N_MEET_SERVER_DOMAIN}/fullchain.pem /etc/haproxy/ssl/${PLUG_N_MEET_SERVER_DOMAIN}.pem
  ln -s /etc/letsencrypt/live/${PLUG_N_MEET_SERVER_DOMAIN}/privkey.pem /etc/haproxy/ssl/${PLUG_N_MEET_SERVER_DOMAIN}.pem.key

  wget ${CONFIG_DOWNLOAD_URL}/haproxy_main.cfg -O /etc/haproxy/haproxy.cfg

  sed -i "s/PLUG_N_MEET_SERVER_DOMAIN/$PLUG_N_MEET_SERVER_DOMAIN/g" /etc/haproxy/haproxy.cfg
  sed -i "s/LIVEKIT_SERVER_DOMAIN/$LIVEKIT_SERVER_DOMAIN/g" /etc/haproxy/haproxy.cfg
  sed -i "s/TURN_SERVER_DOMAIN/$TURN_SERVER_DOMAIN/g" /etc/haproxy/haproxy.cfg

  wget ${CONFIG_DOWNLOAD_URL}/001-restart-haproxy -O /etc/letsencrypt/renewal-hooks/post/001-restart-haproxy
  chmod +x /etc/letsencrypt/renewal-hooks/post/001-restart-haproxy

  service haproxy start
}

configure_lets_encrypt() {
  wget ${CONFIG_DOWNLOAD_URL}/haproxy_lets_encrypt.cfg -O /etc/haproxy/haproxy.cfg
  service haproxy start

  if ! which snap > /dev/null; then
    apt install -y snapd
  fi
  
  snap install core; snap refresh core; snap install --classic certbot
  ln -s /snap/bin/certbot /usr/bin/certbot

  if ! certbot certonly --standalone -d $PLUG_N_MEET_SERVER_DOMAIN -d $LIVEKIT_SERVER_DOMAIN -d $TURN_SERVER_DOMAIN \
    --non-interactive --agree-tos --email $EMAIL_ADDRESS \
    --http-01-port=9080; then
    display_error "Let's Encrypt SSL request did not succeed - exiting"
  fi

  service haproxy stop
  rm /etc/haproxy/haproxy.cfg
}

can_run() {
  if [ $EUID != 0 ]; then display_error "You must run this script as root."; fi

  OS=$(lsb_release -si)
  if [ "$OS" != "Ubuntu" ]; then display_error "This script will require Ubuntu server."; fi

  apt update && apt install -y --no-install-recommends software-properties-common unzip
  clear
}

display_error() {
  echo "$1" >&2
  exit 1
}

enable_ufw() {
  apt install -y ufw

  ufw allow ${SSH_CLIENT##* }/tcp
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw allow 7881/tcp
  ufw allow 3478/udp
  ufw allow 50000:60000/udp
  ufw allow from 172.20.0.0/24 # plugNmeet docker container

  ufw --force enable
}

main "$@" || exit 1
