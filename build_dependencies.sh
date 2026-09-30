#!/bin/bash
set -e

# Prefix for all custom built dependencies
export PREFIX="/opt/wine-deps"
export PATH="${PREFIX}/bin:/usr/local/bin:/usr/bin:/bin:/sbin:/usr/sbin"
export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PREFIX}/lib/aarch64-linux-gnu/pkgconfig:${PREFIX}/share/pkgconfig"

mkdir -p "${PREFIX}/src"
mkdir -p "${PREFIX}/include/linux"

# Enable deb-src for build-dep
sudo sed -i 's/^# deb-src/deb-src/' /etc/apt/sources.list
sudo apt-get update

# Install system dependencies
sudo apt-get -y install software-properties-common build-essential pkg-config ninja-build \
    wget git curl texinfo bison flex \
    libxpresent-dev libjxr-dev libusb-1.0-0-dev libgcrypt20-dev libpulse-dev \
    libudev-dev libsane-dev libv4l-dev libkrb5-dev libgphoto2-dev liblcms2-dev \
    libcapi20-dev libjpeg-dev samba-dev libffi-dev libpcsclite-dev libcups2-dev \
    python3-pip libxcb-xkb-dev libbz2-dev graphviz xmlto

sudo apt-get -y build-dep wine-development libsdl2 libvulkan1

# Versions
sdl2_version="2.32.10"
faudio_version="23.03"
vulkan_headers_version="1.4.352"
vulkan_loader_version="1.4.352"
spirv_headers_version="sdk-1.3.239.0"
libpcap_version="1.10.4"
libxkbcommon_version="1.13.1"
libglvnd_version="1.7.0"
wayland_version="1.24.0"
wayland_protocols_version="1.47"
gnutls_version="3.8.12"
nettle_version="3.10.2"
p11_kit_version="0.26.2"
libgpg_error_version="1.59"
libgcrypt_version="1.12.2"

cd "${PREFIX}/src"

# Download custom headers
wget -O "${PREFIX}/include/linux/ntsync.h" https://raw.githubusercontent.com/zen-kernel/zen-kernel/refs/heads/6.15/main/include/uapi/linux/ntsync.h
wget -O "${PREFIX}/include/linux/userfaultfd.h" https://raw.githubusercontent.com/zen-kernel/zen-kernel/refs/heads/6.15/main/include/uapi/linux/userfaultfd.h

# CMake
pip3 install meson ninja

# SDL2
wget -c https://www.libsdl.org/release/SDL2-${sdl2_version}.tar.gz -O - | tar -xz
cd SDL2-${sdl2_version} && mkdir build && cd build
cmake .. -DCMAKE_INSTALL_PREFIX="${PREFIX}" && make -j$(nproc) install
cd ../..

# FAudio
wget -c https://github.com/FNA-XNA/FAudio/archive/${faudio_version}.tar.gz -O - | tar -xz
cd FAudio-${faudio_version} && mkdir build && cd build
cmake .. -DCMAKE_INSTALL_PREFIX="${PREFIX}" && make -j$(nproc) install
cd ../..

# Vulkan Headers & Loader
wget -c https://github.com/KhronosGroup/Vulkan-Headers/archive/v${vulkan_headers_version}.tar.gz -O - | tar -xz
cd Vulkan-Headers-${vulkan_headers_version} && mkdir build && cd build
cmake .. -DCMAKE_INSTALL_PREFIX="${PREFIX}" && make -j$(nproc) install
cd ../..

wget -c https://github.com/KhronosGroup/Vulkan-Loader/archive/v${vulkan_loader_version}.tar.gz -O - | tar -xz
cd Vulkan-Loader-${vulkan_loader_version} && mkdir build && cd build
cmake .. -DCMAKE_INSTALL_PREFIX="${PREFIX}" -DVULKAN_HEADERS_INSTALL_DIR="${PREFIX}" && make -j$(nproc) install
cd ../..

# SPIRV-Headers
wget -c https://github.com/KhronosGroup/SPIRV-Headers/archive/${spirv_headers_version}.tar.gz -O - | tar -xz
cd SPIRV-Headers-${spirv_headers_version} && mkdir build && cd build
cmake .. -DCMAKE_INSTALL_PREFIX="${PREFIX}" && make -j$(nproc) install
cd ../..

# libpcap
wget -c https://www.tcpdump.org/release/libpcap-${libpcap_version}.tar.gz -O - | tar -xz
cd libpcap-${libpcap_version}
./configure --prefix="${PREFIX}" && make -j$(nproc) install
cd ..

# Wayland
wget -c https://gitlab.freedesktop.org/wayland/wayland/-/releases/${wayland_version}/downloads/wayland-${wayland_version}.tar.xz -O - | tar -xJ
cd wayland-${wayland_version}
meson setup build --prefix="${PREFIX}" && meson install -C build
cd ..

# Wayland Protocols
wget -c https://gitlab.freedesktop.org/wayland/wayland-protocols/-/releases/${wayland_protocols_version}/downloads/wayland-protocols-${wayland_protocols_version}.tar.xz -O - | tar -xJ
cd wayland-protocols-${wayland_protocols_version}
meson setup build --prefix="${PREFIX}" && meson install -C build
cd ..

# libxkbcommon
wget -c https://github.com/xkbcommon/libxkbcommon/archive/refs/tags/xkbcommon-${libxkbcommon_version}.tar.gz -O - | tar -xz
cd libxkbcommon-xkbcommon-${libxkbcommon_version}
meson setup build --prefix="${PREFIX}" -Denable-docs=false && meson install -C build
cd ..

# libglvnd
wget -c https://gitlab.freedesktop.org/glvnd/libglvnd/-/archive/v${libglvnd_version}/libglvnd-v${libglvnd_version}.tar.gz -O - | tar -xz
cd libglvnd-v${libglvnd_version}
meson setup build --prefix="${PREFIX}" && meson install -C build
cd ..

# GStreamer
git clone https://gitlab.freedesktop.org/gstreamer/gstreamer.git -b 1.22
cd gstreamer
meson setup build --prefix="${PREFIX}" && meson install -C build
cd ..

# Nettle
wget -c https://ftp.gnu.org/gnu/nettle/nettle-${nettle_version}.tar.gz -O - | tar -xz
cd nettle-${nettle_version}
./configure --prefix="${PREFIX}" && make -j$(nproc) install
cd ..

# p11-kit
wget -c https://github.com/p11-glue/p11-kit/releases/download/${p11_kit_version}/p11-kit-${p11_kit_version}.tar.xz -O - | tar -xJ
cd p11-kit-${p11_kit_version}
meson setup build --prefix="${PREFIX}" && meson install -C build
cd ..

# GnuTLS
wget -c https://www.gnupg.org/ftp/gcrypt/gnutls/v3.8/gnutls-${gnutls_version}.tar.xz -O - | tar -xJ
cd gnutls-${gnutls_version}
./configure --prefix="${PREFIX}" --with-included-unistring --disable-doc && make -j$(nproc) install
cd ..

# libgpg-error
wget -c https://www.gnupg.org/ftp/gcrypt/libgpg-error/libgpg-error-${libgpg_error_version}.tar.bz2 -O - | tar -xj
cd libgpg-error-${libgpg_error_version}
./configure --prefix="${PREFIX}" && make -j$(nproc) install
cd ..

# libgcrypt
wget -c https://www.gnupg.org/ftp/gcrypt/libgcrypt/libgcrypt-${libgcrypt_version}.tar.bz2 -O - | tar -xj
cd libgcrypt-${libgcrypt_version}
./configure --prefix="${PREFIX}" && make -j$(nproc) install
cd ..

export TOOLCHAIN_URL="https://github.com/mstorsjo/llvm-mingw/releases/download/20260922/llvm-mingw-20260922-ucrt-ubuntu-22.04-aarch64.tar.xz"
export TOOLCHAIN_DIR="/opt/mingw"

# Check and download toolchain if it doesn't exist
if [ ! -d "${TOOLCHAIN_DIR}/bin" ]; then
    echo "Downloading and extracting llvm-mingw toolchain..."
    sudo mkdir -p "${TOOLCHAIN_DIR}"
    wget -q --show-progress -O llvm-mingw.tar.xz "${TOOLCHAIN_URL}"
    sudo tar xf llvm-mingw.tar.xz -C "${TOOLCHAIN_DIR}" --strip-components=1
    rm llvm-mingw.tar.xz
fi
# Cleanup sources to save artifact space
rm -rf "${PREFIX}/src"

echo "Dependencies built successfully at ${PREFIX}!"
