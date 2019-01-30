# Let's ECDSA
Script for using ECDSA certificate with Let's Encrypt

## Install
First of all, install Let's Encrypt (certbot-auto).
```bash
git clone https://github.com/certbot/certbot /usr/local/bin/certbot
sudo su
/usr/local/bin/certbot/certbot-auto --os-packages-only
```

Follow the steps below.

```bash
git clone https://github.com/HimaJyun/letsecdsa && cd letsecdsa
cp -v example.conf your-site.conf
editor your-site.conf
chmod +x ./letsecdsa.sh
sudo ./letsecdsa.sh your-site.conf
```

## Automatic renewal
Just call the script again.  
Please refer to the attached systemd setting.
