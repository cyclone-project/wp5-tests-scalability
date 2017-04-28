#!/bin/sh


currentDir=`pwd`
cd $(dirname $0)
ROOTDIR=`pwd`
cd $currentDir

SCRIPTNAME="$0"
DATE_FORMAT='--rfc-3339=seconds'

MYLOOPSFILENAME="myloops"



#=============================================================================
#  Function  debug_message (Message part, ...)
#=============================================================================
debug_message ()
{
  [ "$VERBOSE" ]  ||  return
  echo  "$(date "$DATE_FORMAT")  ${SCRIPTNAME}  DEBUG: " "$@" | tee -a ${LOG_FILE}
}


#=============================================================================
#  Function  info_message (Message part, ...)
#=============================================================================
info_message ()
{
  echo  "$(date "$DATE_FORMAT")  ${SCRIPTNAME}  INFO: " "$@" | tee -a ${LOG_FILE}
}


#=============================================================================
#  Function  warning_message (Message part, ...)
#=============================================================================
warning_message ()
{
  echo  "$(date "$DATE_FORMAT")  ${SCRIPTNAME}  WARNING: " "$@" | tee -a ${LOG_FILE}
}

#=============================================================================
#  Function  warning_message (Message part, ...)
#=============================================================================
fatal ()
{
    echo  "$(date "$DATE_FORMAT")  ${SCRIPTNAME}  FATAL : " "$@" | tee -a ${LOG_FILE}
    exit 1
}


if [ -z "${OAR_JOBID}" ] ; then
  fatal "variable OAR_JOBID is not set"
fi

LOG_FILE="${ROOTDIR}/${OAR_JOBID}-deploy.log"
touch ${LOG_FILE}


if [ ! -r ${MYLOOPSFILENAME} ] ; then 
  fatal "Can't find ${MYLOOPSFILENAME}"
fi

if [ ! -s "$OAR_NODEFILE" ] ; then
  fatal "Env variable is not set: OAR_NODEFILE"
fi

NB_NODES=$(sort -u $OAR_NODEFILE | wc -l)
SERVER_NODE=$(sort -u $OAR_NODEFILE | tail -1)

if [ -z "$SERVER_NODE" ] ; then
  fatal "Can't find a server node"
fi

CLIENT_NODES_FILE="$(dirname $0)/$(basename $OAR_NODEFILE)-clientnodes"
sort -u $OAR_NODEFILE | grep -v ${SERVER_NODE} > ${CLIENT_NODES_FILE}
NB_CLIENTS=$(wc -l ${CLIENT_NODES_FILE} | cut -d ' ' -f 1)

LOGDIR=$(dirname $0)/$(basename $OAR_NODEFILE)-logs/
mkdir -p ${LOGDIR}
SERVER_LOG_FILE="${LOGDIR}/server-${SERVER_NODE}.log"
CLIENT_LOG_FILE="${LOGDIR}/client.log"
touch  ${SERVER_LOG_FILE}
touch  ${CLIENT_LOG_FILE}

info_message "Deploying server on ${SERVER_NODE}"
kadeploy3 -m ${SERVER_NODE} -a myjessieserver.env -k >> ${SERVER_LOG_FILE} 2>&1 &

info_message "Deploying clients using ${CLIENT_NODES_FILE}"
cat ${CLIENT_NODES_FILE}
kadeploy3 -f ${CLIENT_NODES_FILE} -a myjessieclient.env -k >> ${CLIENT_LOG_FILE} 2>&1 &

while ( true ) ; do
  grep "The deployment is successful on nodes" ${SERVER_LOG_FILE} > /dev/null 2>&1
  [ $? -eq 0 ] && break
  info_message "Server not ready; spleeping 30s"
  sleep 30
done

SERVER_SCRIPT_NAME="server.sh"
SERVER_SCRIPT="$(dirname $0)/${SERVER_SCRIPT_NAME}"
info_message "Copying script to server ${SERVER_SCRIPT}"
scp ${SERVER_SCRIPT} root@${SERVER_NODE}:
scp $(dirname $0)/server_get_ip.sh root@${SERVER_NODE}:
scp ${MYLOOPSFILENAME} root@${SERVER_NODE}:

SERVER_IP=$(ssh root@${SERVER_NODE} './server_get_ip.sh')
if [ -z "${SERVER_IP}" ] ; then
    fatal "SERVER_IP no set"
fi

info_message "Server IP : ${SERVER_IP}"
info_message "ssh root@${SERVER_NODE} ./${SERVER_SCRIPT_NAME} ${NB_CLIENTS}  ${SERVER_LOG_FILE}"
ssh root@${SERVER_NODE} "./${SERVER_SCRIPT_NAME} ${NB_CLIENTS}" >> ${SERVER_LOG_FILE} 2>&1 &

while ( true ) ; do
  grep "The deployment is successful on nodes" ${CLIENT_LOG_FILE} > /dev/null 2>&1
  [ $? -eq 0 ] && break
  info_message "Clients not ready; spleeping 30s"
  sleep 30
done

CLIENT_SCRIPT_NAME="client.sh"
CLIENT_SCRIPT="$(dirname $0)/${CLIENT_SCRIPT_NAME}"
info_message "Copying script to clients ${CLIENT_SCRIPT}"
for node in $(cat ${CLIENT_NODES_FILE} ) ; do 
  scp ${CLIENT_SCRIPT} root@$node:
  scp ${MYLOOPSFILENAME} root@${node}:

  NODE_LOG_FILE="${LOGDIR}/client-${node}.log"

  info_message "ssh root@${node} ./${CLIENT_SCRIPT_NAME} ${SERVER_IP} > ${NODE_LOG_FILE}"
  ssh root@${node} "./${CLIENT_SCRIPT_NAME} ${SERVER_IP} " > ${NODE_LOG_FILE} 2>&1 &
done

while ( true ) ; do
  wget http://${SERVER_NODE}/time.dat > /dev/null 2>&1
  [ $? -eq 0 ] && break
  info_message "Waiting http://${SERVER_NODE}/time.dat; sleeping 30s"
  sleep 30
done

RESULTSDIR=$(basename $OAR_NODEFILE)-result.d
mkdir -p ${RESULTSDIR}
cd ${RESULTSDIR}
scp -r root@${SERVER_NODE}:/var/www/html/* .
cd ..
