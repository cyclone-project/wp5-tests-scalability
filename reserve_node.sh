#!/bin/sh

echo "OarSub"
oarsub -I -l nodes=6,walltime=3 -t deploy

echo "KaDeploy3"
kadeploy3 -f $OAR_NODE_FILE -a myjessieserver.env -k
