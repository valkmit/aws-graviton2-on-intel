#!/bin/bash

apt-get -y update
apt-get -y install build-essential \
    python3 ninja-build pkg-config libglib2.0-dev git

mkdir -p /root/build
cd /root/build

/root/qemu-src/configure \
    --prefix="/root/qemu-install/" \
    --target-list="aarch64-linux-user" \
    --without-default-features \
    --without-default-devices \
    --static

make install -j$(nproc)