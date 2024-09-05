#!/bin/bash -e

WORK_DIR=/opt/plugNmeet

## https://raw.githubusercontent.com/mynaparrot/plugNmeet-install/main/install-files
CONFIG_DOWNLOAD_URL="https://raw.githubusercontent.com/mynaparrot/plugNmeet-install/main/install-files"

## https://github.com/mynaparrot/plugNmeet-client/releases/latest/download/client.zip
CLIENT_DOWNLOAD_URL="https://github.com/mynaparrot/plugNmeet-client/releases/latest/download/client.zip"
RECORDER_DOWNLOAD_URL="https://github.com/mynaparrot/plugNmeet-recorder/releases/latest/download/recorder.zip"

## https://raw.githubusercontent.com/mynaparrot/plugNmeet-server/main/sql_dump/install.sql
SQL_DUMP_DOWNLOAD_URL="https://raw.githubusercontent.com/mynaparrot/plugNmeet-server/main/sql_dump/install.sql"

MARIADB_VERSION="11.4"
NODEJS_VERSION="20"
OS=$(lsb_release -si)
CODE_NAME=$(lsb_release -cs)
ARCH=$(dpkg --print-architecture)

main() {
  can_run

  PLUG_N_MEET_SERVER_DOMAIN=
  while [[ $PLUG_N_MEET_SERVER_DOMAIN == "" ]]; do
    echo -n "Please enter plugNmeet server domain (exmple: plugnmeet.example.com): "
    read -r PLUG_N_MEET_SERVER_DOMAIN
  done

  TURN_SERVER_DOMAIN=
  while [[ $TURN_SERVER_DOMAIN == "" ]]; do
    echo -n "Please enter turn server domain (exmple: turn.example.com): "
    read -r TURN_SERVER_DOMAIN
  done

  EMAIL_ADDRESS=
  while [[ $EMAIL_ADDRESS == "" ]]; do
    echo -n "Please enter valid email address: "
    read -r EMAIL_ADDRESS
  done

  echo -n "Do you want to install recorder? y/n: "
  read -r RECORDER_INSTALL
  echo -n "Do you want to configure firewall(ufw)? y/n: "
  read -r CONFIGURE_UFW

  mkdir -p ${WORK_DIR}
  cd ${WORK_DIR}

  if ! which docker >/dev/null; then
    install_docker
  fi

  get_public_ip
  install_redis
  install_mariadb
  prepare_nats
  install_haproxy
  prepare_server
  install_client
  prepare_etherpad
  install_fonts

  if [ "$RECORDER_INSTALL" == "y" ]; then
    install_recorder
  fi

  if [ "$CONFIGURE_UFW" == "y" ]; then
    enable_ufw
  fi

  printf "\\nFinalizing setup..\\n"
  start_services

  clear
  printf "Installation completed!\\n\\n"
  printf "plugNmeet server URL: %s\\n" "https://${PLUG_N_MEET_SERVER_DOMAIN}"
  printf "plugNmeet API KEY: %s\\n" "${PLUG_N_MEET_API_KEY}"
  printf "plugNmeet API SECRET: %s\\n" "${PLUG_N_MEET_SECRET}"

  printf "\\n\\nTo manage server: \\n"
  printf "systemctl stop plugnmeet or systemctl restart plugnmeet\\n"

  if [ "$RECORDER_INSTALL" == "y" ]; then
    printf "\\n\\nTo manage recorder: \\n"
    printf "systemctl stop plugnmeet-recorder or systemctl restart plugnmeet-recorder \\n\\n"
  fi

  printf "To test frontend: \\n"
  printf "%s\\n\\n" "https://${PLUG_N_MEET_SERVER_DOMAIN}/login.html"
}

install_docker() {
  apt -y install ca-certificates curl gnupg lsb-release

  if [ "$OS" == "Ubuntu" ]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo \
      "deb [arch=${ARCH} signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu ${CODE_NAME} stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
  elif [ "$OS" == "Debian" ]; then
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker.gpg
    echo \
      "deb [arch=${ARCH} signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/debian \
      ${CODE_NAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  fi

  apt update
  apt -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_haproxy() {
  if [ "$OS" == "Ubuntu" ]; then
    add-apt-repository ppa:vbernat/haproxy-3.0 -y
  elif [ "$OS" == "Debian" ]; then
    curl -fsSL https://haproxy.debian.net/bernat.debian.org.gpg |
      sudo gpg --dearmor -o /usr/share/keyrings/haproxy.debian.net.gpg
    echo deb "[signed-by=/usr/share/keyrings/haproxy.debian.net.gpg]" \
      http://haproxy.debian.net "${CODE_NAME}"-backports-3.0 main \
      >/etc/apt/sources.list.d/haproxy.list
  fi

  apt -y update && apt install -y haproxy
  service haproxy stop

  cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg_bk
  mkdir -p /etc/haproxy/ssl

  configure_lets_encrypt

  ln -s /etc/letsencrypt/live/"${PLUG_N_MEET_SERVER_DOMAIN}"/fullchain.pem /etc/haproxy/ssl/"${PLUG_N_MEET_SERVER_DOMAIN}".pem
  ln -s /etc/letsencrypt/live/"${PLUG_N_MEET_SERVER_DOMAIN}"/privkey.pem /etc/haproxy/ssl/"${PLUG_N_MEET_SERVER_DOMAIN}".pem.key

  # generate the custom DH parameters
  openssl dhparam -out /etc/haproxy/dhparams-2048.pem 2048

  wget ${CONFIG_DOWNLOAD_URL}/haproxy_main.cfg -O /etc/haproxy/haproxy.cfg
  sed -i "s/TURN_SERVER_DOMAIN/$TURN_SERVER_DOMAIN/g" /etc/haproxy/haproxy.cfg
  sed -i "s/MACHINE_IP/$MACHINE_IP/g" /etc/haproxy/haproxy.cfg

  wget ${CONFIG_DOWNLOAD_URL}/001-restart-haproxy -O /etc/letsencrypt/renewal-hooks/post/001-restart-haproxy
  chmod +x /etc/letsencrypt/renewal-hooks/post/001-restart-haproxy

  service haproxy start
}

install_redis() {
  curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg > /dev/null 2>&1
  echo "deb [arch=${ARCH} signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb ${CODE_NAME} main" | sudo tee /etc/apt/sources.list.d/redis.list

  apt update && apt install -y redis

  update-rc.d redis-server defaults > /dev/null 2>&1
  systemctl -q enable redis-server 2> /dev/null
}

install_mariadb() {
  version="ubuntu"
  if [ "$OS" == "Debian" ]; then
    version="debian"
  fi

  curl -s https://mariadb.org/mariadb_release_signing_key.asc | gpg --dearmor | tee /usr/share/keyrings/mariadb-keyring.gpg > /dev/null 2>&1

  echo "deb [arch=${ARCH} signed-by=/usr/share/keyrings/mariadb-keyring.gpg] https://dlm.mariadb.com/repo/mariadb-server/${MARIADB_VERSION}/repo/${version} ${CODE_NAME} main" > /etc/apt/sources.list.d/mariadb.list

  apt update && DEBIAN_FRONTEND=noninteractive apt install -y mariadb-client mariadb-common mariadb-server

  # Run mysql_install_db
  mysql_install_db
  # Remove symbolic link
  rm -f /etc/mysql/my.cnf
  # temporary use hestiacp recommended settings
  wget https://raw.githubusercontent.com/hestiacp/hestiacp/main/install/deb/mysql/my-small.cnf -O /etc/mysql/my.cnf

  update-rc.d mariadb defaults > /dev/null 2>&1
	systemctl -q enable mariadb 2> /dev/null
	systemctl restart mariadb

	# check if database is up
  while ! nc -z localhost 3306; do
    printf "."
    sleep 1 # wait before check again
  done

  # We won't set root password. If needed then uncomment this lines
  # https://mariadb.com/kb/en/authentication-from-mariadb-104/#overview
  # DB_ROOT_PASSWORD=$(random_key 20)
  # echo -e "[client]\\npassword='${DB_ROOT_PASSWORD}'\\n" > /root/.my.cnf
  # chmod 600 /root/.my.cnf
  # mysql -uroot -e "SET password = password('${DB_ROOT_PASSWORD}'); FLUSH PRIVILEGES;"

  # Allow mysql access via socket for startup
  mysql -e "UPDATE mysql.global_priv SET priv=json_set(priv, '$.password_last_changed', UNIX_TIMESTAMP(), '$.plugin', 'mysql_native_password', '$.authentication_string', 'invalid', '$.auth_or', json_array(json_object(), json_object('plugin', 'unix_socket'))) WHERE User='root';"
  # Disable anonymous users
  mysql -e "DELETE FROM mysql.global_priv WHERE User='';"
  # Drop test database
  mysql -e "DROP DATABASE IF EXISTS test"
  mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%'"
  # Flush privileges
  mysql -e "FLUSH PRIVILEGES;"

  wget ${SQL_DUMP_DOWNLOAD_URL} -O install.sql
  mysql -u root < install.sql

  DB_PLUGNMEET_PASSWORD=$(random_key 20)
  mysql -u root -e "CREATE USER 'plugnmeet'@'localhost' IDENTIFIED BY '${DB_PLUGNMEET_PASSWORD}';GRANT ALL ON plugnmeet.* TO 'plugnmeet'@'localhost';FLUSH PRIVILEGES;"
}

prepare_nats() {
  wget ${CONFIG_DOWNLOAD_URL}/nats_server.conf -O ./nats_server.conf
  NATS_ACCOUNT="PNM"
  NATS_USER="auth"
  NATS_PASSWORD=$(random_key 36)
  NATS_PASSWORD_CRYPT=$(docker run --rm -it bitnami/natscli:latest server passwd -p "$NATS_PASSWORD")

  OUTPUT=$(docker run --rm -it natsio/nats-box:latest nsc generate nkey --account)
  readarray -t array < <(printf '%b\n' "$OUTPUT")

  NATS_CALLOUT_PUBLIC_KEY=${array[1]}
  NATS_CALLOUT_PRIVATE_KEY=${array[0]}

  sed -i "s/_NATS_ACCOUNT_/$NATS_ACCOUNT/g" nats_server.conf
  sed -i "s/_NATS_USER_/$NATS_USER/g" nats_server.conf
  sed -i "s/_NATS_PASSWORD_CRYPT_/$NATS_PASSWORD_CRYPT/g" nats_server.conf
  sed -i "s/_NATS_CALLOUT_PUBLIC_KEY_/$NATS_CALLOUT_PUBLIC_KEY/g" nats_server.conf
}

configure_lets_encrypt() {
  wget ${CONFIG_DOWNLOAD_URL}/haproxy_lets_encrypt.cfg -O /etc/haproxy/haproxy.cfg
  service haproxy start

  if ! which snap >/dev/null; then
    apt install -y snapd
  fi

  snap install core
  snap refresh core
  snap install --classic certbot
  ln -s /snap/bin/certbot /usr/bin/certbot

  if ! certbot certonly --standalone -d "${PLUG_N_MEET_SERVER_DOMAIN}" -d "${TURN_SERVER_DOMAIN}" \
    --non-interactive --agree-tos --email "${EMAIL_ADDRESS}" \
    --http-01-port=9080; then
    display_error "Let's Encrypt SSL request did not succeed - exiting"
  fi

  service haproxy stop
  rm /etc/haproxy/haproxy.cfg
}

prepare_server() {
  wget ${CONFIG_DOWNLOAD_URL}/config.yaml -O config.yaml
  wget ${CONFIG_DOWNLOAD_URL}/livekit.yaml -O livekit.yaml
  wget ${CONFIG_DOWNLOAD_URL}/ingress.yaml -O ingress.yaml
  wget ${CONFIG_DOWNLOAD_URL}/docker-compose.yaml -O docker-compose.yaml

  ## change livekit api & turn
  LIVEKIT_API_KEY=API$(random_key 11)
  LIVEKIT_SECRET=$(random_key 36)

  PLUG_N_MEET_API_KEY=API$(random_key 11)
  PLUG_N_MEET_SECRET=$(random_key 36)

  sed -i "s/PUBLIC_IP/$PUBLIC_IP/g" docker-compose.yaml

  # livekit
  sed -i "s/LIVEKIT_API_KEY/$LIVEKIT_API_KEY/g" livekit.yaml
  sed -i "s/LIVEKIT_SECRET/$LIVEKIT_SECRET/g" livekit.yaml
  sed -i "s/TURN_SERVER_DOMAIN/$TURN_SERVER_DOMAIN/g" livekit.yaml
  sed -i "s/PLUG_N_MEET_SERVER_DOMAIN/$PLUG_N_MEET_SERVER_DOMAIN/g" livekit.yaml

  # ingress
  sed -i "s/LIVEKIT_API_KEY/$LIVEKIT_API_KEY/g" ingress.yaml
  sed -i "s/LIVEKIT_SECRET/$LIVEKIT_SECRET/g" ingress.yaml
  sed -i "s/PLUG_N_MEET_SERVER_DOMAIN/$PLUG_N_MEET_SERVER_DOMAIN/g" ingress.yaml

  # nats
  sed -i "s/NATS_ACCOUNT/$NATS_ACCOUNT/g" config.yaml
  sed -i "s/NATS_USER/$NATS_USER/g" config.yaml
  sed -i "s/NATS_PASSWORD/$NATS_PASSWORD/g" config.yaml
  sed -i "s/NATS_CALLOUT_PRIVATE_KEY/$NATS_CALLOUT_PRIVATE_KEY/g" config.yaml
  sed -i "s/PLUG_N_MEET_SERVER_DOMAIN/$PLUG_N_MEET_SERVER_DOMAIN/g" config.yaml

  # plugNmeet
  sed -i "s/PLUG_N_MEET_SERVER_DOMAIN/$PLUG_N_MEET_SERVER_DOMAIN/g" config.yaml
  sed -i "s/LIVEKIT_API_KEY/$LIVEKIT_API_KEY/g" config.yaml
  sed -i "s/LIVEKIT_SECRET/$LIVEKIT_SECRET/g" config.yaml
  sed -i "s/PLUG_N_MEET_API_KEY/$PLUG_N_MEET_API_KEY/g" config.yaml
  sed -i "s/PLUG_N_MEET_SECRET/$PLUG_N_MEET_SECRET/g" config.yaml
  sed -i "s/DB_PLUGNMEET_PASSWORD/$DB_PLUGNMEET_PASSWORD/g" config.yaml

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

  rm client.zip
}

prepare_etherpad() {
  mkdir -p etherpad
  wget ${CONFIG_DOWNLOAD_URL}/settings.json -O etherpad/settings.json

  ETHERPAD_SECRET=$(random_key 40)

  sed -i "s/ETHERPAD_SECRET/$ETHERPAD_SECRET/g" config.yaml
  sed -i "s/ETHERPAD_SERVER_DOMAIN/https:\/\/$PLUG_N_MEET_SERVER_DOMAIN\/etherpad/g" config.yaml

  sed -i "s/ETHERPAD_SECRET/$ETHERPAD_SECRET/g" etherpad/settings.json
  # haproxy will remove path `/etherpad` during proxying
  # so, here we'll use the main domain name only
  sed -i "s/ETHERPAD_SERVER_DOMAIN/https:\/\/$PLUG_N_MEET_SERVER_DOMAIN/g" etherpad/settings.json
}

install_fonts() {
  apt update && apt -y install --no-install-recommends \
    fonts-arkpandora \
    fonts-crosextra-carlito \
    fonts-crosextra-caladea \
    fonts-noto \
    fonts-noto-cjk \
    fonts-noto-core \
    fonts-noto-mono \
    fonts-noto-ui-core \
    fonts-liberation \
    fonts-dejavu \
    fonts-dejavu-extra \
    fonts-liberation \
    fonts-liberation2 \
    fonts-linuxlibertine \
    fonts-sil-gentium \
    fonts-sil-gentium-basic \
    fontconfig
}

prepare_recorder() {
  ## prepare nodejs
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/nodesource.gpg
  echo "deb [arch=${ARCH} signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODEJS_VERSION.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list

  ## install require software
  apt -y update && apt -y install nodejs xvfb ffmpeg libnss3-dev
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
  sed -i "s/PLUG_N_MEET_SERVER_DOMAIN/\"https:\/\/$PLUG_N_MEET_SERVER_DOMAIN\"/g" recorder/config.yaml
  sed -i "s/PLUG_N_MEET_API_KEY/$PLUG_N_MEET_API_KEY/g" recorder/config.yaml
  sed -i "s/PLUG_N_MEET_SECRET/$PLUG_N_MEET_SECRET/g" recorder/config.yaml
  sed -i "s/WEBSOCKET_AUTH_TOKEN/$WEBSOCKET_AUTH_TOKEN/g" recorder/config.yaml
  sed -i "s/NATS_USER/$NATS_USER/g" recorder/config.yaml
  sed -i "s/NATS_PASSWORD/$NATS_PASSWORD/g" recorder/config.yaml

  prepare_recorder

  npm install --omit=dev -C recorder
  rm recorder.zip
}

can_run() {
  if [ $EUID != 0 ]; then display_error "You must run this script as root."; fi

  OS=$(lsb_release -si)
  if (("$OS" != "Ubuntu" && "$OS" != "Debian")); then display_error "This script will require Ubuntu or Debian server."; fi

  apt update && apt upgrade -y && apt dist-upgrade -y
  apt install -y --no-install-recommends software-properties-common unzip net-tools git dnsutils

  if ! which nc >/dev/null; then
    apt install -y --no-install-recommends netcat
  fi

  ## make sure directory is exist
  mkdir -p /usr/share/keyrings
  clear
}

random_key() {
  tr -dc A-Za-z0-9 </dev/urandom | dd bs="$1" count=1 2>/dev/null
}

display_error() {
  echo "$1" >&2
  exit 1
}

get_public_ip() {
  # best way to get ip using one of domain
  # turn server's domain can't be behind proxy
  PUBLIC_IP=$(dig +time=1 +tries=1 +retry=1 +short "${TURN_SERVER_DOMAIN}" "@resolver1.opendns.com")
  MACHINE_IP=$(ip route get 8.8.8.8 | awk -F "src " 'NR==1{split($2,a," ");print a[1]}')
}

enable_ufw() {
  if ! which ufw >/dev/null; then
    apt install -y ufw
  fi
  ## install fail2ban server too
  if ! which fail2ban-server >/dev/null; then
    apt-get install -y fail2ban
  fi

  SSH_PORT=$(echo "${SSH_CLIENT}" | cut -d' ' -f 3)

  ufw allow "${SSH_PORT}"/tcp
  ufw allow 22/tcp # for safety
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw allow 7881/tcp
  ufw allow 1935/tcp # for ingres RTMP
  ufw allow 443/udp
  ufw allow 50000:60000/udp

  ufw --force enable
}

start_services() {
  # start etherpad
  printf "\\nStarting etherpad..\\n"
  docker compose up -d etherpad
  # we'll check etherpad because it take most of the time
  while ! nc -z localhost 9001; do
    printf "."
    sleep 1 # wait before check again
  done

  # now start livekit & plugnmeet-api
  printf "\\nStarting livekit & plugNmeet..\\n"
  docker compose up -d livekit
  docker compose up -d plugnmeet
  # check if livekit is up
  while ! nc -z localhost 7880; do
    printf "."
    sleep 1 # wait before check again
  done

  # check if plugnmeet-api is up
  while ! nc -z localhost 8080; do
    printf "."
    sleep 1 # wait before check again
  done

  ## finally restart all service
  systemctl restart plugnmeet

  if [ "$RECORDER_INSTALL" == "y" ]; then
    printf "\\nStarting recorder..\\n"
    # wait for plugnmeet
    while ! nc -z localhost 8080; do
      printf "."
      sleep 1 # wait before check again
    done
    systemctl start plugnmeet-recorder
  fi
}

main "$@" || exit 1
