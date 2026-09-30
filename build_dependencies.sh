#!/usr/bin/env bash

## A script for creating Ubuntu bootstraps for Wine compilation.
## debootstrap and perl are required
## root rights are required

if [ "$EUID" != 0 ]; then
    echo "This script requires root rights!"
    exit 1
fi

if ! command -v debootstrap 1>/dev/null || ! command -v perl 1>/dev/null; then
    echo "Please install debootstrap and perl and run the script again"
    exit 1
fi

export CHROOT_DISTRO="bionic"
export CHROOT_MIRROR="https://ports.ubuntu.com/ubuntu-ports/"

export MAINDIR=/opt/chroots
export CHROOT_ARM64="${MAINDIR}/${CHROOT_DISTRO}arm64_chroot"

# Toolchain configuration
export TOOLCHAIN_URL="https://github.com/mstorsjo/llvm-mingw/releases/download/20260922/llvm-mingw-20260922-ucrt-ubuntu-22.04-aarch64.tar.xz"
export TOOLCHAIN_DIR="/opt/mingw"

echo "Downloading and extracting llvm-mingw toolchain to the host..."
mkdir -p "${TOOLCHAIN_DIR}"
wget -q --show-progress -O llvm-mingw.tar.xz "${TOOLCHAIN_URL}"
tar xf llvm-mingw.tar.xz -C "${TOOLCHAIN_DIR}" --strip-components=1
rm llvm-mingw.tar.xz

prepare_chroot () {
    CHROOT_PATH="${CHROOT_ARM64}"

    echo "Unmount chroot directories. Just in case."
    umount -Rl "${CHROOT_PATH}" || true

    echo "Mount directories for chroot"
    mount --bind "${CHROOT_PATH}" "${CHROOT_PATH}"
    mount -t proc /proc "${CHROOT_PATH}"/proc
    mount --bind /sys "${CHROOT_PATH}"/sys
    mount --make-rslave "${CHROOT_PATH}"/sys
    mount --bind /dev "${CHROOT_PATH}"/dev
    mount --bind /dev/pts "${CHROOT_PATH}"/dev/pts
    mount --bind /dev/shm "${CHROOT_PATH}"/dev/shm
    mount --make-rslave "${CHROOT_PATH}"/dev

    rm -f "${CHROOT_PATH}/etc/resolv.conf"
    cp /etc/resolv.conf "${CHROOT_PATH}/etc/resolv.conf"

    # Bind toolchain into chroot so it can be used during preparation
    mkdir -p "${CHROOT_PATH}/opt/mingw"
    mount --bind "${TOOLCHAIN_DIR}" "${CHROOT_PATH}/opt/mingw"

    echo "Chrooting into ${CHROOT_PATH}"
    chroot "${CHROOT_PATH}" /usr/bin/env LANG=en_US.UTF-8 TERM=xterm PATH="/opt/mingw/bin:/bin:/sbin:/usr/bin:/usr/sbin" /opt/prepare_chroot.sh

    echo "Unmount chroot directories"
    umount -l "${CHROOT_PATH}/opt/mingw"
    umount -l "${CHROOT_PATH}"
    umount "${CHROOT_PATH}/proc"
    umount "${CHROOT_PATH}/sys"
    umount "${CHROOT_PATH}/dev/pts"
    umount "${CHROOT_PATH}/dev/shm"
    umount "${CHROOT_PATH}/dev"
}

create_build_scripts () {
    sdl2_version="2.32.10"
    faudio_version="23.03"
    vulkan_headers_version="1.4.352"
    vulkan_loader_version="1.4.352"
    spirv_headers_version="sdk-1.3.239.0"
    libpcap_version="1.10.4"
    libxkbcommon_version="1.13.1"
    meson_version="1.3.2"
    cmake_version="3.30.3"
    libglvnd_version="1.7.0"
    bison_version="3.8.2"
    wayland_version="1.24.0"
    wayland_protocols_version="1.47"
    gnutls_version="3.8.12"
    nettle_version="3.10.2"
    p11_kit_version="0.26.2"
    libgpg_error_version="1.59"
    libgcrypt_version="1.12.2"

    cat <<EOF > "${MAINDIR}/prepare_chroot.sh"
#!/bin/bash
set -e

apt-get update
apt-get -y install nano locales software-properties-common
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen

# Setup deb-src repositories
sed -i 's/^deb /deb-src /g' /etc/apt/sources.list > /tmp/sources-src.list
cat /tmp/sources-src.list >> /etc/apt/sources.list

apt-get update
apt-get -y upgrade
apt-get -y dist-upgrade

apt-get -y build-dep wine-development libsdl2 libvulkan1 python3
apt-get -y install wget git ninja-build pkg-config curl texinfo xmlto graphviz python3-pip
apt-get -y install libxpresent-dev libjxr-dev libusb-1.0-0-dev libgcrypt20-dev libpulse-dev libudev-dev libsane-dev libv4l-dev libkrb5-dev libgphoto2-dev liblcms2-dev libcapi20-dev libjpeg-dev samba-dev libffi-dev libpcsclite-dev libcups2-dev libxcb-xkb-dev libbz2-dev

apt-get -y purge libvulkan-dev libvulkan1 libsdl2-dev libsdl2-2.0-0 libpcap0.8-dev libpcap0.8 --purge --autoremove
apt-get -y purge *gstreamer* --purge --autoremove
apt-get -y clean
apt-get -y autoclean

export PATH="/usr/local/bin:/opt/mingw/bin:\${PATH}"

mkdir -p /opt/build_libs
cd /opt/build_libs

wget -O sdl.tar.gz https://www.libsdl.org/release/SDL2-${sdl2_version}.tar.gz
wget -O faudio.tar.gz https://github.com/FNA-XNA/FAudio/archive/${faudio_version}.tar.gz
wget -O vulkan-loader.tar.gz https://github.com/KhronosGroup/Vulkan-Loader/archive/v${vulkan_loader_version}.tar.gz
wget -O vulkan-headers.tar.gz https://github.com/KhronosGroup/Vulkan-Headers/archive/v${vulkan_headers_version}.tar.gz
wget -O spirv-headers.tar.gz https://github.com/KhronosGroup/SPIRV-Headers/archive/${spirv_headers_version}.tar.gz
wget -O libpcap.tar.gz https://www.tcpdump.org/release/libpcap-${libpcap_version}.tar.gz
wget -O libxkbcommon.tar.gz https://github.com/xkbcommon/libxkbcommon/archive/refs/tags/xkbcommon-${libxkbcommon_version}.tar.gz
wget -O cmake.tar.gz https://github.com/Kitware/CMake/releases/download/v${cmake_version}/cmake-${cmake_version}.tar.gz
wget -O libglvnd.tar.gz https://gitlab.freedesktop.org/glvnd/libglvnd/-/archive/v${libglvnd_version}/libglvnd-v${libglvnd_version}.tar.gz
wget -O bison.tar.xz https://ftp.gnu.org/gnu/bison/bison-${bison_version}.tar.xz
wget -O wayland.tar.xz https://gitlab.freedesktop.org/wayland/wayland/-/releases/${wayland_version}/downloads/wayland-${wayland_version}.tar.xz
wget -O wayland-protocols.tar.xz https://gitlab.freedesktop.org/wayland/wayland-protocols/-/releases/${wayland_protocols_version}/downloads/wayland-protocols-${wayland_protocols_version}.tar.xz
wget -O gnutls.tar.xz https://www.gnupg.org/ftp/gcrypt/gnutls/v3.8/gnutls-${gnutls_version}.tar.xz
wget -O nettle.tar.gz https://ftp.gnu.org/gnu/nettle/nettle-${nettle_version}.tar.gz
wget -O p11-kit.tar.xz https://github.com/p11-glue/p11-kit/releases/download/${p11_kit_version}/p11-kit-${p11_kit_version}.tar.xz
wget -O libgpg-error.tar.bz2 https://www.gnupg.org/ftp/gcrypt/libgpg-error/libgpg-error-${libgpg_error_version}.tar.bz2
wget -O libgcrypt.tar.bz2 https://www.gnupg.org/ftp/gcrypt/libgcrypt/libgcrypt-${libgcrypt_version}.tar.bz2

mkdir -p /usr/include/linux
wget -O /usr/include/linux/ntsync.h https://raw.githubusercontent.com/zen-kernel/zen-kernel/refs/heads/6.15/main/include/uapi/linux/ntsync.h
wget -O /usr/include/linux/userfaultfd.h https://raw.githubusercontent.com/zen-kernel/zen-kernel/refs/heads/6.15/main/include/uapi/linux/userfaultfd.h

git clone https://gitlab.freedesktop.org/gstreamer/gstreamer.git -b 1.22

# Extract archives
for f in *.tar.*; do tar xf "\$f"; done

# Install pip dependencies
pip3 install meson ninja setuptools

export CC=clang
export CXX=clang++
export CFLAGS="-O2"
export CXXFLAGS="-O2"

cd cmake-${cmake_version}
./bootstrap --parallel=\$(nproc)
make -j\$(nproc) install

cd ../SDL2-${sdl2_version} && mkdir build && cd build
cmake .. && make -j\$(nproc) && make install

cd ../../FAudio-${faudio_version} && mkdir build && cd build
cmake .. && make -j\$(nproc) && make install

cd ../../Vulkan-Headers-${vulkan_headers_version} && mkdir build && cd build
cmake .. && make -j\$(nproc) && make install

cd ../../Vulkan-Loader-${vulkan_loader_version} && mkdir build && cd build
cmake .. && make -j\$(nproc) && make install

cd ../../SPIRV-Headers-${spirv_headers_version} && mkdir build && cd build
cmake .. && make -j\$(nproc) && make install

cd ../../libpcap-${libpcap_version}
./configure && make -j\$(nproc) install

cd ../gstreamer
meson setup build
ninja -C build install

cd ../bison-${bison_version}
./configure && make -j\$(nproc) install

cd ../wayland-${wayland_version}
meson setup build && meson install -C build

cd ../wayland-protocols-${wayland_protocols_version}
meson setup build && meson install -C build

cd ../libxkbcommon-xkbcommon-${libxkbcommon_version}
meson setup build -Denable-docs=false && meson install -C build

cd ../libglvnd-v${libglvnd_version}
meson setup build && meson install -C build

cd ../nettle-${nettle_version}
./configure && make -j\$(nproc) install

cd ../p11-kit-${p11_kit_version}
meson setup build && meson install -C build

cd ../gnutls-${gnutls_version}
./configure --with-included-unistring --disable-doc && make -j\$(nproc) install

cd ../libgpg-error-${libgpg_error_version}
./configure && make -j\$(nproc) install

cd ../libgcrypt-${libgcrypt_version}
./configure && make -j\$(nproc) install

cd /opt && rm -r /opt/build_libs
EOF

    chmod +x "${MAINDIR}/prepare_chroot.sh"
    cp "${MAINDIR}/prepare_chroot.sh" "${CHROOT_ARM64}/opt"
}

mkdir -p "${MAINDIR}"

debootstrap --arch arm64 $CHROOT_DISTRO "${CHROOT_ARM64}" $CHROOT_MIRROR
create_build_scripts
prepare_chroot

rm "${CHROOT_ARM64}/opt/prepare_chroot.sh"

clear
echo "Done"
