# Build + test environment: Buildroot host deps, QEMU (virt + raspi4b), test tools.
FROM debian:trixie

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential gcc g++ make patch perl python3 rsync bc cpio unzip file \
        wget ca-certificates git libncurses-dev xz-utils bzip2 gzip ccache \
        qemu-system-arm qemu-utils \
        ffmpeg openssh-client sshpass curl fdisk e2fsprogs mtools dosfstools binutils device-tree-compiler \
        python3-pytest python3-paramiko python3-requests \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -u 1000 builder \
    && mkdir -p /work && chown builder:builder /work \
    && git config --system --add safe.directory '*'

USER builder
ENV BR2_DL_DIR=/work/dl BR2_CCACHE_DIR=/work/ccache
WORKDIR /work
