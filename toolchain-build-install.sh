#!/bin/bash

apt-get -y update
apt-get -y install build-essential libncurses-dev \
    file wget cpio unzip rsync bc python3

cd /root/buildroot-src
make

cd /x86_64
tar czf /root/buildroot-src/host.tar.gz ./host