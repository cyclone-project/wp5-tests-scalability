#!/bin/sh

#ifconfig eth0 | grep 'inet addr'| cut -c 21- | cut -d ' ' -f 1

ifconfig $(ifconfig| grep eth| cut -d ' ' -f 1) | grep 'inet addr'| cut -c 21- | cut -d ' ' -f 1


