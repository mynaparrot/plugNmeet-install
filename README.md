# Plug-N-Meet easy install

This script will install all the components needed to set up your Plug-N-Meet server.

## The components listed below will be installed:

1) Docker
2) HAProxy
3) certbot (for let's encrypt)
4) Redis (inside docker)
5) Mariadb (inside docker)
6) LiveKit Server (inside docker)
7) Plug-N-Meet Server (inside docker)
8) Plug-N-Meet Client
9) Optional, Plug-N-Meet Recorder (with all require pieces of software e.g nodejs, xvfb, ffmpeg, google chrome)
10) Optional, UFW firewall

The script will create a new directory `plugNmeet` inside `/opt`. All the configuration files will be located there.

## Requirements

You'll need a clean Ubuntu server with a public IP address. If you have a firewall, the following ports must be opened:

```
80/tcp, 443/tcp, 7881/tcp, 3478/udp, 50000:60000/udp
```

Make sure your Ubuntu server does not come pre-installed with apache or nginx, or else the installation will fail.

You'll need three subdomains that point to the public IP address of your Ubuntu server.
Example: ```plugnmeet.example.com, livekit.example.com, turn.example.com```. A valid email address is also required to
generate a Let's Encrypt SSL certificate.

***Note:*** If DNS fails for the three domains, the installation will be aborted.

## Start steps

Using SSH, connect to your Ubuntu server. Download and run the installation script as the root user.

```
wget https://raw.githubusercontent.com/mynaparrot/plugNmeet-dev/main/install.sh
sudo bash install.sh
```

Now, follow the steps. You'll receive the relevant information at the end of the installation.

***Note:*** If you get a 404 error or the recorder stops working, you can restart service
by `systemctl restart plugnmeet && systemctl restart plugnmeet-recorder`.
