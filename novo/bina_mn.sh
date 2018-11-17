#!/bin/bash

# Make by @Alibaba on BIN discord I just adapted.

TMP_FOLDER=$(mktemp -d)
CONFIG_FILE='binarium.conf'
CONFIGFOLDER='/root/.binariumcore'
COIN_DAEMON='binariumd'
COIN_CLI='binarium-cli'
COIN_PATH='/root/binarium/'
#COIN_REPO='Place Holder'
COIN_TGZ=$(curl -s https://api.github.com/repos/binariumpay/binarium/releases/latest | grep 'browser_' | grep linux_64 | cut -d\" -f4)
COIN_ZIP=$(echo $COIN_TGZ | awk -F'/' '{print $NF}')
#COIN_ZIP='https://github.com/binariumpay/binarium/releases/download/0.12.7/binarium_linux_64.7z'
SENTINEL_REPO='https://github.com/binariumpay/sentinel.git'
COIN_NAME='Binarium'
COIN_PORT=8884
RPC_PORT=8887
LOCAL_IP=`ifconfig eth0 | grep "inet addr" | cut -d: -f2 | awk '{print $1}'`

NODEIP=$(curl -s4 icanhazip.com)

BLUE="\033[0;34m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
PURPLE="\033[0;35m"
RED='\033[0;31m'
GREEN="\033[0;32m"
NC='\033[0m'
MAG='\e[1;35m'

# Delay script execution for N seconds
function delay { echo -e "${GREEN}Wait for $1 seconds...${NC}"; sleep "$1"; }

# Removing old wallet if exist
function purge_old_installation() {
  echo -e "Searching and removing old ${GREEN}$COIN_NAME${NC} files and configurations."
  # kill wallet daemon
  systemctl stop $COIN_NAME.service > /dev/null 2>&1
  killall $COIN_DAEMON > /dev/null 2>&1
  # remove old ufw port allow
  ufw delete allow $COIN_PORT/tcp > /dev/null 2>&1
  ufw delete allow $RPC_PORT/tcp > /dev/null 2>&1
  # remove old files
        cd /usr/local/bin && rm $COIN_CLI $COIN_DAEMON > /dev/null 2>&1 && cd
  cd /usr/bin && rm $COIN_CLI $COIN_DAEMON > /dev/null 2>&1 && cd
  sudo rm -rf $CONFIGFOLDER > /dev/null 2>&1
  # remove binaries and utilities
  cd ~ >/dev/null 2>&1
  rm $COIN_PATH > /dev/null 2>&1
  echo -e "${GREEN}* Done${NC}"
}

function download_node() {
  echo -e "Downloading and Installing ${GREEN}$COIN_NAME Wallet.${NC}"
  cd $TMP_FOLDER >/dev/null 2>&1
  wget -q $COIN_TGZ
  compile_error
  #  7z x $COIN_ZIP -o$COIN_PATH >/dev/null 2>&1
  #  cd $COIN_PATH >/dev/null 2>&1
  7z x $COIN_ZIP >/dev/null 2>&1
  chmod +x $COIN_DAEMON $COIN_CLI
  compile_error
  mkdir $COIN_PATH >/dev/null 2>&1
  cp $COIN_DAEMON $COIN_CLI $COIN_PATH
  cd ~ >/dev/null 2>&1
  rm -rf $TMP_FOLDER >/dev/null 2>&1
  clear
}

function configure_systemd() {
  cat << EOF > /etc/systemd/system/$COIN_NAME.service
[Unit]
Description=$COIN_NAME service
After=network.target

[Service]
User=root
Group=root

Type=forking
#PIDFile=$CONFIGFOLDER/$COIN_NAME.pid

ExecStart=$COIN_PATH$COIN_DAEMON -daemon -conf=$CONFIGFOLDER/$CONFIG_FILE -datadir=$CONFIGFOLDER
ExecStop=$COIN_PATH$COIN_CLI -conf=$CONFIGFOLDER/$CONFIG_FILE -datadir=$CONFIGFOLDER stop

Restart=always
PrivateTmp=true
TimeoutStopSec=60s
TimeoutStartSec=10s
StartLimitInterval=120s
StartLimitBurst=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  sleep 3
  systemctl start $COIN_NAME.service
  systemctl enable $COIN_NAME.service >/dev/null 2>&1

  if [[ -z "$(ps axo cmd:100 | egrep $COIN_DAEMON)" ]]; then
    echo -e "${MAG}$COIN_NAME is not running${NC}, please investigate. You should start by running the following commands as root:"
    echo -e "${GREEN}systemctl start $COIN_NAME.service"
    echo -e "systemctl status $COIN_NAME.service"
    echo -e "less /var/log/syslog${NC}"
    exit 1
  fi
}

function create_config() {
  mkdir $CONFIGFOLDER >/dev/null 2>&1
  RPCUSER=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)
  RPCPASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 20 | head -n 1)
  #  Replace by hardcoded user-pass for localhost only, please uncomment if issues with Sentinel
  #  RPCUSER=sentinel
  #  RPCPASSWORD=sentinel
  cat << EOF > $CONFIGFOLDER/$CONFIG_FILE
rpcuser=$RPCUSER
rpcpassword=$RPCPASSWORD
rpcallowip=127.0.0.1
rpcport=$RPC_PORT
listen=1
server=1
daemon=1
gen=0
datadir=/root/.binariumcore
printtoconsole=1
irc=0
port=$COIN_PORT
bind=$LOCAL_IP:$COIN_PORT
EOF
}

function create_key() {
  echo -e "Enter your ${MAG}$COIN_NAME Masternode Private Key${NC}. Leave it blank to generate a new ${MAG}Masternode Private Key${NC} for you:"
  read -e COINKEY
  if [[ -z "$COINKEY" ]]; then
  echo -e "${GREEN}Loading Wallet to generate the Private Key.${NC}"
  $COIN_PATH$COIN_DAEMON -daemon >/dev/null 2>&1
  delay 60
  if [ -z "$(ps axo cmd:100 | grep $COIN_DAEMON)" ]; then
   echo -e "${RED}$COIN_NAME server couldn not start. Check /var/log/syslog for errors{$NC}"
   exit 1
  fi
  COINKEY=$($COIN_PATH$COIN_CLI masternode genkey) >/dev/null 2>&1
  if [ "$?" -gt "0" ];
    then
    echo -e "${RED}Wallet not fully loaded. Let us wait and try again to generate the Private Key.${NC}"
    delay 60
    COINKEY=$($COIN_PATH$$COIN_CLI masternode genkey)
  fi
   $COIN_PATH$COIN_CLI stop >/dev/null 2>&1
   echo -e "${GREEN}Key generated, stopping Wallet.${NC}"
   delay 5
fi
clear
}

function update_config() {
  sed -i 's/daemon=1/daemon=0/' $CONFIGFOLDER/$CONFIG_FILE
  cat << EOF >> $CONFIGFOLDER/$CONFIG_FILE
logtimestamps=1
maxconnections=16
blocksonly=1
maxorphantx=1
maxuploadtarget=400
masternode=1
externalip=$NODEIP:$COIN_PORT
masternodeaddr=$NODEIP:$COIN_PORT
masternodeprivkey=$COINKEY

EOF
}

function ask_firewall() {
 echo -e "Protect this server with a firewall and limit connection to SSH and $COIN_NAME Port${NC} only"
 echo -e "Please confirm ${MAG}[Y/N]${NC} if you want to enable the firewall:"
 read -e UFW
}

function enable_firewall() {
  echo -e "Please enter alternative ${MAG}SSH Port Number${NC} if you use this or type ${GREEN}22${NC} to leave the default SSH Port"
  read -e SSH_ALT
  echo -e "Installing and setting up firewall to allow ingress on port ${GREEN}$COIN_PORT${NC}"
  ufw allow $COIN_PORT/tcp comment "$COIN_NAME MN port" >/dev/null
  # RPC port is closed for external IPs by default for Masternode, uncomment if needed
  # ufw allow $RPCPORT/tcp comment "$COIN_NAME RPC port" >/dev/null
  ufw allow $SSH_ALT comment "SSH_Alternative" >/dev/null 2>&1
  ufw allow ssh comment "SSH" >/dev/null 2>&1
  ufw limit ssh/tcp >/dev/null 2>&1
  ufw default allow outgoing >/dev/null 2>&1
  echo "y" | ufw enable >/dev/null 2>&1
}

function get_ip() {
  declare -a NODE_IPS
  for ips in $(netstat -i | awk '!/Kernel|Iface|lo/ {print $1," "}')
  do
    NODE_IPS+=($(curl --interface $ips --connect-timeout 2 -s4 icanhazip.com))
  done

  if [ ${#NODE_IPS[@]} -gt 1 ]
    then
      echo -e "${GREEN}More than one IP. Please type 0 to use the first IP, 1 for the second and so on...${NC}"
      INDEX=0
      for ip in "${NODE_IPS[@]}"
      do
        echo ${INDEX} $ip
        let INDEX=${INDEX}+1
      done
      read -e choose_ip
      NODEIP=${NODE_IPS[$choose_ip]}
  else
    NODEIP=${NODE_IPS[0]}
  fi
}

function compile_error() {
if [ "$?" -gt "0" ];
 then
  echo -e "${RED}Failed to compile $COIN_NAME. Please investigate.${NC}"
  exit 1
fi
}

function checks() {
if [[ $(lsb_release -d) != *16.04* ]]; then
  echo -e "${RED}You are not running Ubuntu 16.04. Installation is cancelled.${NC}"
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}$0 must be run as root.${NC}"
   exit 1
fi

if [ -n "$(pidof $COIN_DAEMON)" ] || [ -e "$COIN_DAEMOM" ] ; then
  echo -e "${MAG}$COIN_NAME is already installed.${NC}"
  echo -e "Please enter ${MAG}[Y/N]${NC} if you want to reinstall Masternode:"
  read -e REINSTALL
  if [[ ("$REINSTALL" != "Y" || "$NEW_PENTA" != "y") ]]; then
    exit 1
  fi
  clear
fi
}

function prepare_system() {
echo -e "Preparing the system to install ${GREEN}$COIN_NAME${NC} Masternode"
apt-get -y update >/dev/null 2>&1
echo -e "${GREEN}* Upgrading system packages. Wait up to 10-15 minutes on slow servers.${NC}"
apt-get -y autoremove >/dev/null 2>&1
#DEBIAN_FRONTEND=noninteractive apt-get update > /dev/null 2>&1
#DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y -qq upgrade >/dev/null 2>&1
apt install -y software-properties-common >/dev/null 2>&1
echo -e "${GREEN}* Adding bitcoin PPA repository.${NC}"
#apt-add-repository -y ppa:bitcoin/bitcoin >/dev/null 2>&1
echo -e "${GREEN}* Installing required packages, this may take some time to finish.${NC}"
apt-get update >/dev/null 2>&1
#apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" make software-properties-common \
#build-essential libtool autoconf libssl-dev libboost-dev libboost-chrono-dev libboost-filesystem-dev libboost-program-options-dev \
#libboost-system-dev libboost-test-dev libboost-thread-dev sudo automake git wget htop pwgen curl libdb4.8-dev bsdmainutils libdb4.8++-dev \
#libminiupnpc-dev libgmp3-dev fail2ban ufw pkg-config libevent-dev libdb5.3++ libzmq5 unzip p7zip-full >/dev/null 2>&1
#service fail2ban restart >/dev/null 2>&1
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" make software-properties-common \
build-essential libtool autoconf automake git wget htop pwgen curl bsdmainutils unzip p7zip-full libcurl4-openssl-dev vnstat slurm \
bash-completion >/dev/null 2>&1

if [ "$?" -gt "0" ];
  then
    echo -e "${RED}Not all required packages were installed properly. Try to install them manually by running the following commands:${NC}\n"
    echo "apt-get update"
#    echo "apt -y install software-properties-common"
#    echo "apt-add-repository -y ppa:bitcoin/bitcoin"
    echo "apt-get update"
#    echo "apt-get install -y make build-essential libtool software-properties-common autoconf libssl-dev libboost-dev libboost-chrono-dev libboost-filesystem-dev \
#libboost-program-options-dev libboost-system-dev libboost-test-dev libboost-thread-dev sudo automake git wget htop pwgen curl libdb4.8-dev \
#bsdmainutils libdb4.8++-dev libminiupnpc-dev libgmp3-dev ufw fail2ban pkg-config libevent-dev libzmq5 unzip p7zip-full${NC}"
 exit 1
fi
clear
}

function check_swap() {
echo -e "Checking if swap space is needed."
PHYMEM=$(free -g|awk '/^Mem:/{print $2}')
SWAP=$(swapon -s)
if [[ "$PHYMEM" -lt "1" && -z "$SWAP" ]];
  then
    echo -e "${GREEN}Server is running with less than 1G of RAM, creating 1G swap file is reccommended.${NC}"
    echo -e "${GREEN}Please enter ${MAG}[Y/N]${GREEN} if you want to create the swap:${NC}"
    read -e SWAPQ
    if [[ ("$SWAPQ" == "Y" || "$SWAPQ" == "y") ]]; then
      dd if=/dev/zero of=/swapfile bs=2048 count=1M
      chmod 600 /swapfile
      mkswap /swapfile
      swapon -a /swapfile
	  echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
	  echo "iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --set --name SSH -j ACCEPT" >> /etc/rc.local
	  echo "iptables -A INPUT -p tcp --dport 22 -m recent --update --seconds 600 --hitcount 3 --rttl --name SSH -j DROP" >> /etc/rc.local
	  echo "ip6tables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --set --name SSH -j ACCEPT" >> /etc/rc.local
	  echo "ip6tables -A INPUT -p tcp --dport 22 -m recent --update --seconds 600 --hitcount 3 --rttl --name SSH -j DROP" >> /etc/rc.local
	  iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --set --name SSH -j ACCEPT
	  iptables -A INPUT -p tcp --dport 22 -m recent --update --seconds 600 --hitcount 3 --rttl --name SSH -j DROP
	  ip6tables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --set --name SSH -j ACCEPT
	  ip6tables -A INPUT -p tcp --dport 22 -m recent --update --seconds 600 --hitcount 3 --rttl --name SSH -j DROP
	  echo "iface eth0 inet6 dhcp" > /etc/network/interfaces.d/60-default-with-ipv6.cfg 
    fi
else
  echo -e "${GREEN}The server running with at least 1G of RAM, or SWAP exists.${NC}"
fi
clear
}

function install_sentinel() {
  echo -e "Installing sentinel"
  apt-get -y install python-virtualenv virtualenv >/dev/null 2>&1
  git clone $SENTINEL_REPO $CONFIGFOLDER/sentinel >/dev/null 2>&1
  cd $CONFIGFOLDER/sentinel >/dev/null 2>&1
  virtualenv ./venv >/dev/null 2>&1
  ./venv/bin/pip install -r requirements.txt >/dev/null 2>&1
  # setup config
  echo "dash_conf=$CONFIGFOLDER/$CONFIG_FILE" >> $CONFIGFOLDER/sentinel/sentinel.conf
  # setup cron
  echo -e "Checking sentinel crontab"
#  crontab -l  | grep '$CONFIGFOLDER/sentinel && ./venv/bin/python bin/sentinel.py' >> /dev/null 2>&1 || (crontab -l 2>/dev/null; echo "*/5 * * * * cd $CONFIGFOLDER/sentinel && ./venv/bin/python bin/sentinel.py 2>&1 >> $CONFIGFOLDER/sentinel-cron.log") | crontab -
  crontab -l | grep '$CONFIGFOLDER/sentinel-cron.log' || (crontab -l 2>/dev/null; echo "*/5 * * * * cd $CONFIGFOLDER/sentinel && ./venv/bin/python bin/sentinel.py 2>&1 >> $CONFIGFOLDER/sentinel-cron.log") | crontab -
  echo -e "Done"
  clear
}

function important_information() {
 echo
 echo -e "========================================================================================================================"
 echo -e "$COIN_NAME Masternode is up and running listening on port ${GREEN}$COIN_PORT${NC}"
 echo -e "Configuration file is: ${GREEN}$CONFIGFOLDER/$CONFIG_FILE${NC}"
 echo -e "Start: ${GREEN}systemctl start $COIN_NAME.service${NC}"
 echo -e "Stop: ${GREEN}systemctl stop $COIN_NAME.service${NC}"
 echo -e "VPS_IP:PORT ${GREEN}$NODEIP:$COIN_PORT${NC}"
 echo -e "MASTERNODE PRIVATEKEY is: ${PURPLE}$COINKEY${NC}"
 if [[ -n $SENTINEL_REPO  ]]; then
 echo -e "Sentinel is installed in ${GREEN}$CONFIGFOLDER/sentinel${NC}"
 echo -e "Sentinel log is: ${GREEN}$CONFIGFOLDER/sentinel/sentinel-cron.log${NC}"
 fi
 echo -e "Please check ${GREEN}$COIN_NAME${NC} is running with the following command: ${GREEN}systemctl status $COIN_NAME.service${NC}"
 echo -e "========================================================================================================================"
 echo -e "${CYAN}Ensure Node is fully SYNCED with the BLOCKCHAIN${NC}"
 echo -e "${CYAN}Add the Node to your main Wallet by editing ${GREEN}masternode.conf ${CYAN}file:${NC}"
 echo -e "${CYAN}Masternode_01 $NODEIP:$COIN_PORT$:$ $COINKEY [MN Transaction Number] [Transaction ID]{NC}"
 echo -e "========================================================================================================================"
 echo -e "Masternode & Wallet Commands:"
 echo -e "${GREEN}$COIN_PATH$COIN_CLI masternode status${NC}"
 echo -e "${GREEN}$COIN_PATH$COIN_CLI getinfo${NC}"
 echo -e "Check your crontab for Sentinel job:"
 echo -e "${GREEN}crontab -e${NC}"
 echo -e "========================================================================================================================"
 echo -e "${YELLOW}Donations are always accepted gratefully${NC}"
 echo -e "========================================================================================================================"
 echo -e "${YELLOW}BIN: Xxx6rjryLoHKKes4BruFdkRsvtVYNsj7sx${NC}"
 echo -e "========================================================================================================================"
}

function setup_node() {
  get_ip
  create_config
  create_key
  update_config
  ask_firewall
  if [[ ("$UFW" == "Y" || "$UFW" == "y") ]]; then
    enable_firewall
  fi
  install_sentinel
  important_information
  configure_systemd
}

##### Main #####
clear

checks
prepare_system
check_swap
purge_old_installation
download_node
setup_node
