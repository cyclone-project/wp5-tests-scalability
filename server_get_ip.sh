#!/bin/sh

ifconfig eth1| grep 'inet addr'| cut -c 21- | cut -d ' ' -f 1



