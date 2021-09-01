# Prebuilt images available on Docker Hub

https://hub.docker.com/repository/docker/valkmit/aws-graviton2-on-intel

## What is this?

An Arm filesystem based off an AWS Graviton 2 system. All binaries are emulated
under Qemu, **EXCEPT** for a custom toolchain built with Buildroot. The
toolchain is run natively, allowing for up to _20x_ faster compile times than
when emulated.

```
# file $(which bash)
/usr/bin/bash: ELF 64-bit LSB executable, ARM aarch64, version 1 (SYSV), dynamically linked (uses shared libs), for GNU/Linux 3.7.0, BuildID[sha1]=03b374959d488851f8b6ef51a6a16e55eaedea98, stripped

# file $(realpath $(which aarch64-linux-gcc))
/x86_64/host/bin/toolchain-wrapper: ELF 64-bit LSB shared object, x86-64, version 1 (SYSV), dynamically linked (uses shared libs), for GNU/Linux 3.2.0, BuildID[sha1]=9c88d4609953b73d518a95e44ebc93d642a8174e, stripped
```

## Usage

If you wish to build the Docker image from source, you must run `./build.sh`.
At a minimum, you must provide the rootfs as a .tar.gz with -r. The script
will download buildroot if it is not provided with -b. For a prebuilt image,
please visit the corresponding Docker hub page (link provided above).

The only requirement to build is Docker - both Qemu and the toolchain are
built in Docker containers based on Debian 10.

All of the native cross compile tools are available prefixed with
`aarch64-linux`. For example, `aarch64-linux-gcc`, or `aarch64-linux-g++`.
To observe how the toolchain is configured, you may view
buildroot-graviton2-config.

Spin up an image quickly to play around with the compilers:

```
docker run -it --rm valkmit/aws-graviton2-on-intel
```

## Justification

When compiling for a target architecture different from the host architecture,
developers have roughly two options

1. Set up a cross toolchain, which has fast performance, but makes it very
difficult to automatically satisfy complex dependencies. For a sufficiently
large project, this could mean compiling dozens of projects by hand using the
newly built cross toolchain

2. Emulate the target system, which makes dependency satisfaction easier,
since a native package manager can be used, but slows down compile times -
the compiler has to be emulated, too!

This project is designed to give developers the best of both worlds - the
ease of using the target system's package manager (in this case, Yum configured
with all of Amazon's aarch64 repos) - and the speed of native compilers.

Long story short, a native cross-compiler is transplanted onto the Gravon2
Arm filesystem. This project could probably be extended for other systems, too.

## Isn't a Docker container configured with binfmt-misc superior?

Normally, yes. However, binfmt-misc currently doesn't have namespace support
(though this is in the pipeline!) This means that if you choose to go the
binfmt-misc route, you must run a privileged container. **This project does
not require a privileged Docker container**.

The lack of requirement of privileged container means that you may use this
on public build systems that do not have Arm support, and expect much better
performance.

## Credits

Lots of back and forth with gh:MelloJello
