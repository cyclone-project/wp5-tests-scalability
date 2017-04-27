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
ERR_CAT2=14
ERR_BUILD_DOCKER=15
ERR_RUN_DOCKER=16


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
  fatal "Usage $0 [server-IP]"
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

server_ip_address="$1"


apt-get -y update && apt-get -y upgrade && apt-get -y dist-upgrade
if [ $? -ne 0 ] ; then
    fatal "can't update or upgrade system"
fi

apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
if [ $? -ne 0 ] ; then
    fatal "can't add Docker GPG key"
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
    fatal "can't copy master archive "
fi

cd /tmp/
if [ $? -ne 0 ] ; then
    fatal "can't copy master archive "
fi

rm -Rf cnsmo-net-services-master
unzip master.zip
if [ $? -ne 0 ] ; then
    fatal "can't unzip the CNSMO archive"
fi

cd cnsmo-net-services-master/src/main/docker/vpn/client/
if [ $? -ne 0 ] ; then
    fatal "Error : can't change directory to cnsmo-net-services-master/src/main/docker/vpn/client/ "
fi

cat <<EOF_CLIENTCONF > client.conf
##############################################
# Sample client-side OpenVPN 2.0 config file #
# for connecting to multi-client server.     #
#                                            #
# This configuration can be used by multiple #
# clients, however each client should have   #
# its own cert and key files.                #
#                                            #
# On Windows, you might want to rename this  #
# file so it has a .ovpn extension           #
##############################################

# Specify that we are a client and that we
# will be pulling certain config file directives
# from the server.
client

# Use the same setting as you are using on
# the server.
# On most systems, the VPN will not function
# unless you partially or fully disable
# the firewall for the TUN/TAP interface.
dev tap
;dev tun

# Windows needs the TAP-Windows adapter name
# from the Network Connections panel
# if you have more than one.  On XP SP2,
# you may need to disable the firewall
# for the TAP adapter.
;dev-node MyTap

# Are we connecting to a TCP or
# UDP server?  Use the same setting as
# on the server.
;proto tcp
proto udp

# The hostname/IP and port of the server.
# You can have multiple remote entries
# to load balance between the servers.
remote $server_ip_address 1194
;remote my-server-2 1194

# Choose a random host from the remote
# list for load-balancing.  Otherwise
# try hosts in the order specified.
;remote-random

# Keep trying indefinitely to resolve the
# host name of the OpenVPN server.  Very useful
# on machines which are not permanently connected
# to the internet such as laptops.
resolv-retry infinite

# Most clients don't need to bind to
# a specific local port number.
nobind

# Downgrade privileges after initialization (non-Windows only)
;user nobody
;group nobody

# Try to preserve some state across restarts.
persist-key
persist-tun

# If you are connecting through an
# HTTP proxy to reach the actual OpenVPN
# server, put the proxy server/IP and
# port number here.  See the man page
# if your proxy server requires
# authentication.
;http-proxy-retry # retry on connection failures
;http-proxy [proxy server] [proxy port #]

# Wireless networks often produce a lot
# of duplicate packets.  Set this flag
# to silence duplicate packet warnings.
;mute-replay-warnings

# SSL/TLS parms.
# See the server config file for more
# description.  It's best to use
# a separate .crt/.key file pair
# for each client.  A single ca
# file can be used for all clients.
ca ca.crt
cert client.crt
key client.key

# Verify server certificate by checking
# that the certicate has the nsCertType
# field set to "server".  This is an
# important precaution to protect against
# a potential attack discussed here:
#  http://openvpn.net/howto.html#mitm
#
# To use this feature, you will need to generate
# your server certificates with the nsCertType
# field set to "server".  The build-key-server
# script in the easy-rsa folder will do this.
;ns-cert-type server

# If a tls-auth key is used on the server
# then every client must also have the key.
;tls-auth ta.key 1

# Select a cryptographic cipher.
# If the cipher option is used on the server
# then you must also specify it here.
;cipher x

# Enable compression on the VPN link.
# Don't enable this unless it is also
# enabled in the server config file.
comp-lzo

# Set log file verbosity.
verb 3

# Silence repeating messages
;mute 20
EOF_CLIENTCONF

if [ $? -ne 0 ] ; then
    fatal "can't write in the client.conf file"
fi

docker build -t vpn-client .
if [ $? -ne 0 ] ; then
    fatal "can't build the VPN-client"
fi

docker run -t --net=host --privileged -v /dev/net/:/dev/net/ vpn-client &
if [ $? -ne 0 ] ; then
    fatal "can't build the VPN-client"
fi

sleep 5

ip_address_of_tap0_interface=`ifconfig tap0 | grep "inet addr" | cut -d ':' -f 2 | cut -d ' ' -f 1`

APACHE_SITEs="/etc/apache2/sites-available/"
APACHE_VPNHOST_CONF="/etc/apache2/sites-available/100-vpn_host.conf"

if [ ! -d $APACHE_SITES ] ; then
    fatal "directory not found, $APACHE_SITES"
fi

cat <<EOF_VHOST > $APACHE_VPNHOST_CONF
<VirtualHost $ip_address_of_tap0_interface>
  ServerAdmin webmaster@localhost
  DocumentRoot /var/www/html
  ErrorLog ${APACHE_LOG_DIR}/error_vpn.log
  CustomLog ${APACHE_LOG_DIR}/access_vpn.log combined
</VirtualHost>
EOF_VHOST

ln -sf $APACHE_VPNHOST_CONF /etc/apache2/sites-enabled
if [ $? -ne 0 ] ; then
    fatal " can't install apache vpn host"
fi

service apache2 restart


cd /var/www/html/
rm -Rf *

touch $ip_address_of_tap0_interface.clientready
touch $ip_address_of_tap0_interface.txt

for myloop in `cat ${MYLOOPSFILE}` ; do
    echo "myloop=${myloop}"
    while [ ! -e file${myloop} ]
    do
        info_message "Waiting to download file ${myloop} of ${myloop} MB"
        (time -p wget --quiet 10.8.0.1/file${myloop}) > time${myloop}.txt 2>&1
        sleep 1
    done
    info_message "Done Downloading file${myloop}"
    touch $ip_address_of_tap0_interface.clientdownload${myloop}

#    (echo -n "${myloop} : " ; more time${myloop}.txt | grep real | awk -F " " "{print $2}" ) > timefile${myloop}.txt 2>&1
    (more time${myloop}.txt | grep real | awk -F ' ' '{print $2}' ) > timefile${myloop}.txt 2>&1
    cat timefile${myloop}.txt >> $ip_address_of_tap0_interface.txt
done


cp $ip_address_of_tap0_interface.txt $ip_address_of_tap0_interface.clienttimefile

exit $ERR_OK
