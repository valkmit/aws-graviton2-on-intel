# we are the base image ;)
FROM scratch
ADD ./rootfs /
CMD ["/x86_64/bin/qemu-aarch64", "-execve", "/bin/bash"]