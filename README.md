# Plug-N-Meet easy install

This script will install all the components needed to set up your Plug-N-Meet server.

## Requirements

You'll need a clean Ubuntu or Debian server with a **public IP address**. If you have a firewall, the following ports must be
opened:

```
80/tcp
443/tcp
7881/tcp
443/udp
50000:60000/udp
```

Make sure your Ubuntu/Debian server does not come pre-installed with apache or nginx, or else the installation will fail.

You'll need three subdomains that point to the public IP address of this Ubuntu/Debian server.
Example: ```plugnmeet.example.com, livekit.example.com, turn.example.com```. A valid email address is also required to
generate a [Let's Encrypt](https://letsencrypt.org/) SSL certificate.

***Note:*** If DNS fails for those three domains, the installation will be aborted.

## Usage

Using SSH, connect to your Ubuntu/Debian server. Download and run the installation script as the root user.

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

#### Fonts installation 
When exporting or importing Microsoft Word files that contain characters other than English, you may run into issues because of font missing. You may install additional fonts in the Ubuntu/Debian server using the commands below:

```
sudo apt update && sudo apt -y install --no-install-recommends \
culmus \
fonts-beng \
fonts-hosny-amiri \
fonts-lklug-sinhala \
fonts-lohit-guru \
fonts-lohit-knda \
fonts-samyak-gujr \
fonts-samyak-mlym \
fonts-samyak-taml \
fonts-sarai \
fonts-sil-abyssinica \
fonts-sil-padauk \
fonts-telu \
fonts-thai-tlwg \
ttf-wqy-zenhei \
fonts-arphic-ukai \
fonts-arphic-uming \
fonts-ipafont-mincho \
fonts-ipafont-gothic \
fonts-unfonts-core \
ttf-mscorefonts-installer
```
#### The components listed below will be installed:

1) [Docker](https://docs.docker.com/engine/install/ubuntu/)
2) [HAProxy](https://www.haproxy.org/)
3) [certbot](https://certbot.eff.org/) (for let's encrypt)
4) [Redis](https://hub.docker.com/_/redis) (inside docker)
5) [Mariadb](https://hub.docker.com/_/mariadb) (inside docker)
6) [LiveKit Server](https://github.com/livekit/livekit-server) (inside docker)
7) [Etherpad-lite](https://github.com/mynaparrot/plugNmeet-etherpad) (inside docker)
8) [Plug-N-Meet Server](https://github.com/mynaparrot/plugNmeet-server) (inside docker)
9) [Plug-N-Meet Client](https://github.com/mynaparrot/plugNmeet-client)
10) Optional, [Plug-N-Meet Recorder](https://github.com/mynaparrot/plugNmeet-recorder) (with all require pieces of
    software e.g nodejs, xvfb, ffmpeg, google chrome)
11) Optional, [UFW firewall](https://help.ubuntu.com/community/UFW)

The script will create a new directory `plugNmeet` inside `/opt`. All the configuration files will be located there.

## Update
To update you can use `update.sh` script. This will update all the docker images, client & recorder (if installed).

```
wget https://raw.githubusercontent.com/mynaparrot/plugNmeet-install/main/update.sh
sudo bash update.sh

OR

sudo su -c "bash <(wget -qO- https://raw.githubusercontent.com/mynaparrot/plugNmeet-install/main/update.sh)" root
```