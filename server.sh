#!/bin/bash
ERR_OK=0
ERR_APTGET1=1
ERR_DOCKER_GPG_KEY=2
ERR_CAT=3
ERR_APTGET2=4
ERR_INSTALL_DOCKER=5
ERR_START_DOCKER=6
ERR_ENABLE_DOCKER=7
ERR_APTGET3=8
ERR_WGET=9
ERR_COPY_MASTER=10
ERR_UNZIP=11
ERR_CD1=12
ERR_CD2=13
ERR_BUILD_DOCKER=14
ERR_RUN_DOCKER=15


SCRIPTNAME="$0"
DATE_FORMAT='--rfc-3339=seconds'


#=============================================================================
#  Function  debug_message (Message part, ...)
#=============================================================================
debug_message ()
{
  [ "$VERBOSE" ]  ||  return
  echo  "$(date "$DATE_FORMAT")  $SCRIPTNAME  DEBUG: " "$@"  > /dev/stderr
}


#=============================================================================
#  Function  info_message (Message part, ...)
#=============================================================================
info_message ()
{
  echo  "$(date "$DATE_FORMAT")  $SCRIPTNAME  INFO: " "$@"
}


#=============================================================================
#  Function  warning_message (Message part, ...)
#=============================================================================
warning_message ()
{
  echo  "$(date "$DATE_FORMAT")  $SCRIPTNAME  WARNING: " "$@"
}

#=============================================================================
#  Function  warning_message (Message part, ...)
#=============================================================================
fatal ()
{
    echo  "$(date "$DATE_FORMAT")  $SCRIPTNAME  FATAL : " "$@"
    exit 1
}





if [ -z "$1" ] ; then 
  fatal "Usage $0 [nb-clients]"
fi

currentDir=`pwd`
cd $(dirname $0)
ROOTDIR=`pwd`
cd $currentDir

MYLOOPSFILENAME="myloops"
MYLOOPSFILE=${ROOTDIR}/${MYLOOPSFILENAME}

if [ ! -r ${MYLOOPSFILE} ] ; then 
  fatal "Can't find ${MYLOOPSFILE}"
fi


amount_of_clients="$1"



apt-get -y update && apt-get -y upgrade && apt-get -y dist-upgrade
if [ $? -ne 0 ] ; then
    fatal "can't get the CNSMO archive"
fi

apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
if [ $? -ne 0 ] ; then
    fatal "can't add docker GPG key"
fi

cat <<EOF_SOURCEFILE > /etc/apt/sources.list.d/docker.list
deb https://apt.dockerproject.org/repo debian-jessie main
EOF_SOURCEFILE
if [ $? -ne 0 ] ; then
    fatal "can't write in /etc/apt/sources.list.d/docker.list"
fi

apt-get -y install apt-transport-https ca-certificates
if [ $? -ne 0 ] ; then
     fatal "can't install apt-transport-https or ca-certificates"
fi

apt-get -y update && apt-get -y install docker-engine
if [ $? -ne 0 ] ; then
    fatal "can't update or can't install docker-engine"
fi

systemctl start docker
if [ $? -ne 0 ] ; then
    fatal "can't start docker"
fi

systemctl enable docker
if [ $? -ne 0 ] ; then
    fatal "can't enable docker"
fi

apt-get -y install unzip apache2 openssl
if [ $? -ne 0 ] ; then
    fatal "can't install one of these packages: unzip OR apache2 OR openssl"
fi

rm -f master.zip*
wget https://github.com/dana-i2cat/cnsmo-net-services/archive/master.zip
if [ $? -ne 0 ] ; then
    fatal "can't download the CNSMO archive"
fi

cp master.zip /tmp/
if [ $? -ne 0 ] ; then
    fatal "can't copy the CNSMO archive to /tmp/"
fi

cd /tmp/
if [ $? -ne 0 ] ; then
    fatal "can't change directory to /tmp/"
fi

rm -Rf cnsmo-net-services-master
unzip master.zip
if [ $? -ne 0 ] ; then
    fatal "can't unzip the CNSMO archive"
fi

cd cnsmo-net-services-master/src/main/docker/vpn/server/
if [ $? -ne 0 ] ; then
    fatal "can't change directory to cnsmo-net-services-master/src/main/docker/vpn/server"
fi

cat <<EOF_SERVERCONFFILE > server.conf                                         
local 0.0.0.0
port 1194
;proto tcp
proto udp
;dev tap
dev tap
;dev-node MyTap
ca ca.crt
cert server.crt
key server.key
dh dh2048.pem
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt
;server-bridge 10.8.0.4 255.255.255.0 10.8.0.50 10.8.0.100
;push "route 192.168.10.0 255.255.255.0"
;push "route 192.168.20.0 255.255.255.0"
;client-config-dir ccd
;route 192.168.40.128 255.255.255.248
;client-config-dir ccd
;route 10.9.0.0 255.255.255.252
;learn-address ./script
;push "redirect-gateway"
;push "dhcp-option DNS 10.8.0.1"
;push "dhcp-option WINS 10.8.0.1"

client-to-client
duplicate-cn
keepalive 10 120
;tls-auth ta.key 0 # This file is secret
;cipher BF-CBC        # Blowfish (default)
;cipher AES-128-CBC   # AES
;cipher DES-EDE3-CBC  # Triple-DES
comp-lzo
;max-clients 100
;user nobody
;group nobody
persist-key
persist-tun
status openvpn-status.log
;log         openvpn.log
;log-append  openvpn.log
verb 3
;mute 20                                                                                
EOF_SERVERCONFFILE

docker build -t vpn-server .
if [ $? -ne 0 ] ; then
    fatal "can't build the docker"
fi

docker run -t --net=host --privileged -v /dev/net/:/dev/net/ vpn-server &
if [ $? -ne 0 ] ; then
    fatal "can't run the docker"
fi

sleep 10

APACHE_SITES="/etc/apache2/sites-available/"
APACHE_VPNHOST_CONF="/etc/apache2/sites-available/100-vpn_host.conf"

if [ ! -d $APACHE_SITES ] ; then
    fatal "directory not found, $APACHE_SITES"
fi

cat <<EOF_VHOST > $APACHE_VPNHOST_CONF
<VirtualHost 10.8.0.1>
  ServerAdmin webmaster@localhost
  DocumentRoot /var/www/html
  ErrorLog ${APACHE_LOG_DIR}/error_vpn.log
  CustomLog ${APACHE_LOG_DIR}/access_vpn.log combined
</VirtualHost>
EOF_VHOST

ln -sf $APACHE_VPNHOST_CONF /etc/apache2/sites-enabled
if [ $? -ne 0 ] ; then
    fatal "can't install apache vpn host"
fi

service apache2 restart

cd /var/www/html/
rm -Rf *


amount_of_deployed_clients=`ls -lR *.clientready | wc -l`

while [ ${amount_of_deployed_clients} -lt $amount_of_clients ]
do
    info_message "Waiting clients : ${amount_of_clients}"
    expected_clients=0
    interface=2
    while [ ${expected_clients} -lt ${amount_of_clients} ]
    do
	    if [ ! -e 10.8.0.${interface}.clientready ] ; then
            info_message "wget 10.8.0.${interface}/10.8.0.${interface}.clientready"
	        wget 10.8.0.${interface}/10.8.0.${interface}.clientready
	    fi
	    ((expected_clients++))
	    ((interface++))
    done
    amount_of_deployed_clients=`ls -lR *.clientready | wc -l`
    info_message "Deployed clients : ${amount_of_deployed_clients} / ${amount_of_clients}"
    sleep 2
done

info_message "The clients have been successfully deployed"

for myloop in `cat ${MYLOOPSFILE}` ; do
    echo "myloop=${myloop}"
   
    touch file${myloop}.toctoc

    MEGA_BYTE=$(expr 1024 '*' 1024)
    dd if=/dev/zero of=file${myloop}.toctoc bs=${MEGA_BYTE} count=${myloop}

    mv file${myloop}.toctoc file${myloop}

    amount_of_deployed_clients=`ls -lR *.clientdownload${myloop} | wc -l`
    
    info_message "Waiting for all the clients to download file${myloop}"

    while [ ${amount_of_deployed_clients} -lt ${amount_of_clients} ]
    do
        expected_clients=0
        interface=2
        while [ ${expected_clients} -lt ${amount_of_clients} ]
        do
	        if [ ! -e 10.8.0.${interface}.clientdownload${myloop} ] ; then
	            info_message "wget 10.8.0.${interface}/10.8.0.${interface}.clientdownload${myloop}"
	            wget 10.8.0.${interface}/10.8.0.${interface}.clientdownload${myloop}
	        fi
	        ((expected_clients++))
	        ((interface++))
        done
        
        amount_of_deployed_clients=`ls -lR *.clientdownload${myloop} | wc -l`
        info_message "Amount of downloads for file${myloop} : ${amount_of_deployed_clients} / ${amount_of_clients}"
        sleep 2
    done
    
    rm -f file${myloop}

done


info_message "Waiting for client time file"

amount_of_deployed_clients=`ls -lR *.clienttimefile | wc -l`
while [ ${amount_of_deployed_clients} -lt ${amount_of_clients} ]
do
    expected_clients=0
    interface=2

    while [ ${expected_clients} -lt ${amount_of_clients} ]
    do
	    if [ ! -e 10.8.0.${interface}.clienttimefile ] ; then
	        info_message "wget 10.8.0.${interface}/10.8.0.${interface}.clienttimefile"
	        wget 10.8.0.${interface}/10.8.0.${interface}.clienttimefile
	    fi
	    ((expected_clients++))
	    ((interface++))
    done
    
    amount_of_deployed_clients=`ls -lR *.clienttimefile | wc -l`
    info_message "Amount of time files : ${amount_of_deployed_clients} / ${amount_of_clients}"
    sleep 2
done

echo "#!/bin/bash " >> servertimefile.sh
echo -n "paste " >> servertimefile.sh

amount_of_deployed_clients=`ls -lR *.clienttimefile | wc -l`
counter_clients=0
interface=2
while [ ${counter_clients} -lt  ${amount_of_deployed_clients} ]
do
    echo -n "10.8.0.${interface}.clienttimefile " >> servertimefile.sh
    ((counter_clients++))
	((interface++))
done
echo -n " | pr -t -e3 " >> servertimefile.sh
echo " " >> servertimefile.sh
chmod +x servertimefile.sh
./servertimefile.sh > time.dat

exit $ERR_OK
