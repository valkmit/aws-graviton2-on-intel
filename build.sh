#!/bin/bash

TARBALL_ROOTFS=""
TARBALL_BUILDROOT=""
BUILDROOT_CONFIG="buildroot-graviton2-config"
WORKDIR="./workdir"
DOCKER_TAG="graviton2-crossbuild"

function print_help() {
    echo "usage: $0"
    echo "  -r rootfs.tar.gz (required)"
    echo "  -b buildroot.tar.gz (optional)"
    echo "  -c $BUILDROOT_CONFIG (buildroot config, optional)"
    echo "  -w ./workdir/ (optional)"
    echo "  -t $DOCKER_TAG (docker tag, optional)"
}

# parse options
while getopts "h?r:b:w:t:" opt; do
    case "$opt" in
    h|\?)
        print_help
        exit 0
        ;;
    r)
        TARBALL_ROOTFS="$OPTARG"
        ;;
    b)
        TARBALL_BUILDROOT="$OPTARG"
        ;;
    c)
        BUILDROOT_CONFIG="$OPTARG"
        ;;
    w)
        WORKDIR="$OPTARG"
        ;;
    t)
        DOCKER_TAG="$OPTARG"
        ;;
    esac

    # do not allow empty arguments
    if [[ -z "$OPTARG" ]]; then
        echo "$opt cannot be empty"
        exit 1
    fi
done

# if we don't have a rootfs tarball, we can't proceed because we don't know
# where we should download one from
if [[ -z "$TARBALL_ROOTFS" ]]; then
    echo "Did not specify rootfs option: Try running $0 -h for help"
    exit 1
fi

# if we don't have a buildroot tarball, let's try to download the one that
# we know to work
if [[ -z "$TARBALL_BUILDROOT" ]]; then
    # default path for where we should download buildroot tarball
    buildroot_download_file="buildroot-2021.02.4.tar.gz"
    echo "did not specify buildroot tarball"

    # only download buildroot if we haven't already downloaded it previously
    if [[ -f "$buildroot_download_file" ]]; then
        echo "we found a local copy $buildroot_download_file"
    else
        echo "downloading buildroot to $buildroot_download_file..."
        wget https://buildroot.org/downloads/buildroot-2021.02.4.tar.gz \
            -O "$buildroot_download_file"
        if [[ $? -ne 0 ]]; then
            echo "failed to wget buildroot tarball"
            exit 1
        fi
    fi

    # one way or another, we have a buildroot tarball here
    TARBALL_BUILDROOT="$buildroot_download_file"
fi

# delete the old workdir, we don't know how stale it has become
rm -rf "$WORKDIR"

# build qemu under docker
qemu_install_dir="$WORKDIR/qemu-install"
mkdir -p "$qemu_install_dir"
cp qemu-build-install.sh "$qemu_install_dir"
docker run -it --rm \
    -v "$(realpath qemu):/root/qemu-src" \
    -v "$(realpath $qemu_install_dir):/root/qemu-install" \
    debian:10 \
    /bin/bash /root/qemu-install/qemu-build-install.sh

# sanity check that we have the qemu binary
qemu_user_static="$qemu_install_dir/bin/qemu-aarch64"
if [[ ! -f "$qemu_user_static" ]]; then
    echo "could not find file $qemu_user_static after build"
    exit 1
fi

# extract the buildroot source into the workdir
buildroot_src="$WORKDIR/buildroot-src"
mkdir -p "$buildroot_src"
tar xzf "$TARBALL_BUILDROOT" --strip-components=1 -C "$buildroot_src" 
cp "$BUILDROOT_CONFIG" "$buildroot_src/.config"
cp toolchain-build-install.sh "$buildroot_src/toolchain-build-install.sh"

# farm out to docker to actually build the toolchain
docker run -it --rm \
    -v "$(realpath $buildroot_src):/root/buildroot-src" \
    debian:10 \
    /bin/bash /root/buildroot-src/toolchain-build-install.sh

# sanity check that the toolchain is actually available
toolchain_tarball="$buildroot_src/host.tar.gz"
if [[ ! -f "$toolchain_tarball" ]]; then
    echo "could not find file $toolchain_tarball after build"
    exit 1
fi

# build the final rootfs

rootfs_dir="rootfs"
rm -rf "$rootfs_dir"
mkdir -p "$rootfs_dir"
tar xzf "$TARBALL_ROOTFS" -C "$rootfs_dir" # extract rootfs base

native_dir="$rootfs_dir/x86_64"
mkdir -p "$native_dir/bin"
cp "$qemu_user_static" "$native_dir/bin" # put static qemu into rootfs
tar zxf "$toolchain_tarball" -C "$native_dir" # extract toolchain into rootfs

# get all the native libraries that we need on here
# this looks complicated, but what's going on is we run ldd on every single
# executable within the toolchain, look for any that have leading /'s in the
# path, and bring in the host lib within the rootfs
required_host_libs=$(ldd ./rootfs/x86_64/host/bin/* 2>/dev/null \
    | grep "=>" \
    | awk '{ print $3 }' \
    | grep "^/" \
    | sort -n \
    | uniq -c \
    | awk '{ print $2 }')

# copy every required lib into the rootfs
mkdir -p "$native_dir/lib"
echo "$required_host_libs" | xargs -I{} /bin/sh -c "cp {} $native_dir/lib"
cp /lib64/ld-linux-x86-64.so.2 "$rootfs_dir/lib64" # special case

# load in the paths to the rootfs .bashrc
rootfs_bashrc="$rootfs_dir/root/.bashrc"
echo 'export PATH="$PATH:'"/x86_64/bin:/x86_64/host/bin"'"' >> \
    "$rootfs_bashrc"
echo 'export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:'\
"/x86_64/lib:/x86_64/host/lib"'"' >> "$rootfs_bashrc" # can't indent

# patch releasever var so yum can update, probably different for centos
if [[ -f "$rootfs_dir/etc/yum/vars/amazonlinux" ]]; then
    echo "2" > "$rootfs_dir/etc/yum/vars/releasever"
fi

echo "Done"

# if we supplied a tag, then build an option with -t
docker_tag_cmd=""
if [[ ! -z "$DOCKER_TAG" ]]; then
    docker_tag_cmd="-t $DOCKER_TAG"
fi

# now finally call out to docker to build
docker build $docker_tag_cmd .