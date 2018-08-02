# Auto Suspend / Power off when system is idle

## installation

```sh
sudo apt-get install bc

sudo cp autosuspend.sh /usr/local/sbin/
sudo cp autosuspend.conf /etc/

# setup cron, example of checking every 15 minutes
echo "*/15 * * * * root /usr/local/sbin/autosuspend.sh" | sudo tee -a /etc/crontab
```

* configuration in [/etc/autosuspend.conf](autosuspend.conf)

## troubleshooting

```sh
# check logs 
cat /var/log/syslog | grep AutoSuspend
```

## reference
- original from https://wiki.ubuntuusers.de/Skripte/AutoSuspend/