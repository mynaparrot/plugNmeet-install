# Plug-N-Meet easy install

This script will install all the components needed to set up your Plug-N-Meet server.

## The components listed below will be installed:

1) [Docker](https://docs.docker.com/engine/install/ubuntu/)
2) [HAProxy](https://www.haproxy.org/)
3) [certbot](https://certbot.eff.org/) (for let's encrypt)
4) [Redis](https://hub.docker.com/_/redis) (inside docker)
5) [Mariadb](https://hub.docker.com/_/mariadb) (inside docker)
6) [LiveKit Server](https://github.com/livekit/livekit-server) (inside docker)
7) [Etherpad-lite](https://github.com/ether/etherpad-lite) (inside docker)
8) [Plug-N-Meet Server](https://github.com/mynaparrot/plugNmeet-server) (inside docker)
9) [Plug-N-Meet Client](https://github.com/mynaparrot/plugNmeet-client)
10) Optional, [Plug-N-Meet Recorder](https://github.com/mynaparrot/plugNmeet-recorder) (with all require pieces of
    software e.g nodejs, xvfb, ffmpeg, google chrome)
11) Optional, [UFW firewall](https://help.ubuntu.com/community/UFW)

The script will create a new directory `plugNmeet` inside `/opt`. All the configuration files will be located there.

## Requirements

You'll need a clean Ubuntu server with a **public IP address**. If you have a firewall, the following ports must be
opened:

```
80/tcp
443/tcp
7881/tcp
443/udp
50000:60000/udp
```

Make sure your Ubuntu server does not come pre-installed with apache or nginx, or else the installation will fail.

You'll need three subdomains that point to the public IP address of this Ubuntu server.
Example: ```plugnmeet.example.com, livekit.example.com, turn.example.com```. A valid email address is also required to
generate a [Let's Encrypt](https://letsencrypt.org/) SSL certificate.

***Note:*** If DNS fails for those three domains, the installation will be aborted.

## Usage

Using SSH, connect to your Ubuntu server. Download and run the installation script as the root user.

```
wget https://raw.githubusercontent.com/mynaparrot/plugNmeet-install/main/install.sh
sudo bash install.sh

OR

sudo su -c "bash <(wget -qO- https://raw.githubusercontent.com/mynaparrot/plugNmeet-install/main/install.sh)" root
```

Now, follow the steps in terminal. It will ask you to enter information when necessary. You'll receive the relevant
information at the end of the installation.

***Note:*** If you get a 404 error or the recorder stops working, you can restart service
by `systemctl restart plugnmeet && systemctl restart plugnmeet-recorder`.

#### Fonts installation for Etherpad (Shared notepad)
By default `Etherpad` docker container does not install any additional fonts. When exporting or importing Microsoft Word files that contain characters other than English, you may run into issues. The installation script won't install any additional fonts automatically for you. You may install fonts in the Ubuntu server using the commands below, and docker will share fonts with the etherpad container.

```
sudo apt update && sudo apt -y install --no-install-recommends \
fonts-arkpandora \
fonts-crosextra-carlito \
fonts-crosextra-caladea \
fonts-noto \
fonts-noto-cjk \
fonts-liberation \
fontconfig \
ttf-mscorefonts-installer
```