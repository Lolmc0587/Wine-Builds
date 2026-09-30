#!/usr/bin/env bash

########################################################################
##
## A script for Wine compilation.
## By default it uses two Ubuntu bootstraps (x32 and x64), which it enters
## with bubblewrap (root rights are not required).
##
## This script requires: git, wget, autoconf, xz, bubblewrap, cmake, ninja
##
## You can change the environment variables below to your desired values.
##
########################################################################

# Prevent launching as root
if [ $EUID = 0 ] && [ -z "$ALLOW_ROOT" ]; then
	echo "Do not run this script as root!"
	echo
	echo "If you really need to run it as root and you know what you are doing,"
	echo "set the ALLOW_ROOT environment variable."

	exit 1
fi

export WINE_VERSION="${WINE_VERSION:-latest}"
export WINE_BRANCH="${WINE_BRANCH:-staging}"
export PROTON_BRANCH="${PROTON_BRANCH:-proton_11.0}"
export STAGING_VERSION="${STAGING_VERSION:-}"
export STAGING_ARGS="${STAGING_ARGS:-}"
export EXPERIMENTAL_WOW64="${EXPERIMENTAL_WOW64:-true}"
export CUSTOM_SRC_PATH=""
export DO_NOT_COMPILE="false"
export USE_CCACHE="false"

# Thêm biến môi trường cho phép build FEX-Emu
export BUILD_FEX="true"

export WINE_BUILD_OPTIONS="--without-oss --disable-winemenubuilder --disable-tests"

export BUILD_DIR="${HOME}"/build_wine
export BOOTSTRAP_X64=/opt/chroots/bionic64_chroot
export BOOTSTRAP_X32=/opt/chroots/bionic32_chroot

export scriptdir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

export CC="clang"
export CXX="clang++"

export CROSSCC_X32="i686-w64-mingw32-gcc"
export CROSSCXX_X32="i686-w64-mingw32-g++"
export CROSSCC_X64="x86_64-w64-mingw32-gcc"
export CROSSCXX_X64="x86_64-w64-mingw32-g++"

export CFLAGS_X32="-march=i686 -msse2 -mfpmath=sse -O3"
export CFLAGS_X64="-march=x86-64 -msse3 -mfpmath=sse -O3"
export LDFLAGS="-Wl,-O1,--sort-common,--as-needed"

export CROSSCFLAGS_X32="${CFLAGS_X32}"
export CROSSCFLAGS_X64="${CFLAGS_X64}"
export CROSSLDFLAGS="${LDFLAGS}"

if [ "$USE_CCACHE" = "true" ]; then
	export CC="ccache ${CC}"
	export CXX="ccache ${CXX}"

	export i386_CC="ccache ${CROSSCC_X32}"
	export x86_64_CC="ccache ${CROSSCC_X64}"

	export CROSSCC_X32="ccache ${CROSSCC_X32}"
	export CROSSCXX_X32="ccache ${CROSSCXX_X32}"
	export CROSSCC_X64="ccache ${CROSSCC_X64}"
	export CROSSCXX_X64="ccache ${CROSSCXX_X64}"

	if [ -z "${XDG_CACHE_HOME}" ]; then
		export XDG_CACHE_HOME="${HOME}"/.cache
	fi

	mkdir -p "${XDG_CACHE_HOME}"/ccache
	mkdir -p "${HOME}"/.ccache
fi

build_with_bwrap () {
	if [ "${1}" = "32" ]; then
		BOOTSTRAP_PATH="${BOOTSTRAP_X32}"
	else
		BOOTSTRAP_PATH="${BOOTSTRAP_X64}"
	fi

	if [ "${1}" = "32" ] || [ "${1}" = "64" ]; then
		shift
	fi

    bwrap --ro-bind "${BOOTSTRAP_PATH}" / --dev /dev --ro-bind /sys /sys \
		  --proc /proc --tmpfs /tmp --tmpfs /home --tmpfs /run --tmpfs /var \
		  --tmpfs /mnt --tmpfs /media --bind "${BUILD_DIR}" "${BUILD_DIR}" \
		  --bind-try "${XDG_CACHE_HOME}"/ccache "${XDG_CACHE_HOME}"/ccache \
		  --bind-try "${HOME}"/.ccache "${HOME}"/.ccache \
		  --setenv PATH "/opt/mingw/bin:/usr/local/bin:/bin:/sbin:/usr/bin:/usr/sbin" \
			"$@"
}

# Kiểm tra các command cần thiết
MISSING_EXECS=""
for exec in git autoconf wget xz bwrap; do
    if ! command -v "$exec" 1>/dev/null; then
        MISSING_EXECS="$MISSING_EXECS $exec"
    fi
done

if [ "$BUILD_FEX" = "true" ]; then
	for exec in cmake ninja; do
		if ! command -v "$exec" 1>/dev/null; then
			MISSING_EXECS="$MISSING_EXECS $exec"
		fi
	done
fi

if [ -n "$MISSING_EXECS" ]; then
	echo "Please install missing dependencies and run the script again:$MISSING_EXECS"
	exit 1
fi

if [ "${WINE_VERSION}" = "latest" ] || [ -z "${WINE_VERSION}" ]; then
	WINE_VERSION="$(wget -q -O - "https://raw.githubusercontent.com/wine-mirror/wine/master/VERSION" | tail -c +14)"
fi

if [ "$(echo "$WINE_VERSION" | cut -d "." -f2 | cut -c1)" = "0" ]; then
	WINE_URL_VERSION=$(echo "$WINE_VERSION" | cut -d "." -f 1).0
else
	WINE_URL_VERSION=$(echo "$WINE_VERSION" | cut --d "." -f 1).x
fi

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}" || exit 1

echo
echo "Downloading the source code and patches"
echo "Preparing Wine for compilation"
echo

if [ -n "${CUSTOM_SRC_PATH}" ]; then
	is_url="$(echo "${CUSTOM_SRC_PATH}" | head -c 6)"

	if [ "${is_url}" = "git://" ] || [ "${is_url}" = "https:" ]; then
		git clone "${CUSTOM_SRC_PATH}" wine
	else
		if [ ! -f "${CUSTOM_SRC_PATH}"/configure ]; then
			echo "CUSTOM_SRC_PATH is set to an incorrect or non-existent directory!"
			echo "Please make sure to use a directory with the correct Wine source code."
			exit 1
		fi

		cp -r "${CUSTOM_SRC_PATH}" wine
	fi

	WINE_VERSION="$(cat wine/VERSION | tail -c +14)"
	BUILD_NAME="${WINE_VERSION}"-custom
elif [ "$WINE_BRANCH" = "staging-tkg" ] || [ "$WINE_BRANCH" = "staging-tkg-fsync" ]; then
	if [ "$WINE_BRANCH" = "staging-tkg" ]; then
		git clone https://github.com/Kron4ek/wine-tkg wine
	else
		git clone https://github.com/Kron4ek/wine-tkg wine -b fsync
	fi

	WINE_VERSION="$(cat wine/VERSION | tail -c +14)"
	BUILD_NAME="${WINE_VERSION}"-"${WINE_BRANCH}"
elif [ "$WINE_BRANCH" = "proton" ]; then
	if [ -z "${PROTON_BRANCH}" ]; then
		git clone https://github.com/ValveSoftware/wine
	else
		git clone https://github.com/ValveSoftware/wine -b "${PROTON_BRANCH}"
	fi

 	patch -d wine -Np1 < "${scriptdir}"/fix-proton-compilation-and-version-output.patch

	WINE_VERSION="$(cat wine/VERSION | tail -c +14)-$(git -C wine rev-parse --short HEAD)"
	if [[ "${PROTON_BRANCH}" == "experimental_"* ]] || [ "${PROTON_BRANCH}" = "bleeding-edge" ]; then
		BUILD_NAME=proton-exp-"${WINE_VERSION}"
	else
		BUILD_NAME=proton-"${WINE_VERSION}"
	fi
else
	if [ "${WINE_VERSION}" = "git" ]; then
		git clone https://gitlab.winehq.org/wine/wine.git wine
		BUILD_NAME="${WINE_VERSION}-$(git -C wine rev-parse --short HEAD)"
	else
		BUILD_NAME="${WINE_VERSION}"

		wget -q --show-progress "https://dl.winehq.org/wine/source/${WINE_URL_VERSION}/wine-${WINE_VERSION}.tar.xz"

		tar xf "wine-${WINE_VERSION}.tar.xz"
		mv "wine-${WINE_VERSION}" wine
	fi

	if [ "${WINE_BRANCH}" = "staging" ]; then
		if [ "${WINE_VERSION}" = "git" ]; then
			git clone https://github.com/wine-staging/wine-staging wine-staging-"${WINE_VERSION}"

			upstream_commit="$(cat wine-staging-"${WINE_VERSION}"/staging/upstream-commit | head -c 7)"
			git -C wine checkout "${upstream_commit}"
			BUILD_NAME="${WINE_VERSION}-${upstream_commit}-staging"
		else
			if [ -n "${STAGING_VERSION}" ]; then
				WINE_VERSION="${STAGING_VERSION}"
			fi

			BUILD_NAME="${WINE_VERSION}"-staging

			wget -q --show-progress "https://github.com/wine-staging/wine-staging/archive/v${WINE_VERSION}.tar.gz"
			tar xf v"${WINE_VERSION}".tar.gz

			if [ ! -f v"${WINE_VERSION}".tar.gz ]; then
				git clone https://github.com/wine-staging/wine-staging wine-staging-"${WINE_VERSION}"
			fi
		fi

		if [ -f wine-staging-"${WINE_VERSION}"/patches/patchinstall.sh ]; then
			staging_patcher=("${BUILD_DIR}"/wine-staging-"${WINE_VERSION}"/patches/patchinstall.sh
							DESTDIR="${BUILD_DIR}"/wine)
		else
			staging_patcher=("${BUILD_DIR}"/wine-staging-"${WINE_VERSION}"/staging/patchinstall.py)
		fi

		cd wine || exit 1
		if [ -n "${STAGING_ARGS}" ]; then
			"${staging_patcher[@]}" ${STAGING_ARGS}
		else
			"${staging_patcher[@]}" --all
		fi

		if [ $? -ne 0 ]; then
			echo
			echo "Wine-Staging patches were not applied correctly!"
			exit 1
		fi

		cd "${BUILD_DIR}" || exit 1
	fi
fi

# Clone FEX nếu được kích hoạt
if [ "$BUILD_FEX" = "true" ]; then
    if [ ! -d fex ]; then
        echo "Downloading FEX-Emu source code..."
        git clone --recurse-submodules https://github.com/FEX-Emu/FEX.git fex
    fi
fi

patch -d wine*/ -Np1 < 0001-qcap-fix-Smart-Tee-preview-allocator-and-RGB32-negot.patch
patch -d wine*/ -Np1 < 0002-qcap-fix-wow64-media-type-marshaling-in-v4l-backend.patch

if [ ! -d wine ]; then
	clear
	echo "No Wine source code found!"
	echo "Make sure that the correct Wine version is specified."
	exit 1
fi

cd wine || exit 1
dlls/winevulkan/make_vulkan
tools/make_requests
tools/make_specfiles
autoreconf -f
cd "${BUILD_DIR}" || exit 1

if [ "${DO_NOT_COMPILE}" = "true" ]; then
	clear
	echo "DO_NOT_COMPILE is set to true"
	echo "Force exiting"
	exit
fi

if [ ! -d "${BOOTSTRAP_X64}" ] || [ ! -d "${BOOTSTRAP_X32}" ]; then
	clear
	echo "Bootstraps are required for compilation!"
	exit 1
fi

BWRAP64="build_with_bwrap 64"
BWRAP32="build_with_bwrap 32"

export CROSSCC="${CROSSCC_X64}"
export CROSSCXX="${CROSSCXX_X64}"
export CFLAGS="${CFLAGS_X64}"
export CXXFLAGS="${CFLAGS_X64}"
export CROSSCFLAGS="${CROSSCFLAGS_X64}"
export CROSSCXXFLAGS="${CROSSCFLAGS_X64}"

mkdir "${BUILD_DIR}"/build64
cd "${BUILD_DIR}"/build64 || exit
${BWRAP64} "${BUILD_DIR}"/wine/configure --enable-win64 ${WINE_BUILD_OPTIONS} --prefix "${BUILD_DIR}"/wine-"${BUILD_NAME}"-amd64
${BWRAP64} make -j$(nproc)

export CROSSCC="${CROSSCC_X32}"
export CROSSCXX="${CROSSCXX_X32}"
export CFLAGS="${CFLAGS_X32}"
export CXXFLAGS="${CFLAGS_X32}"
export CROSSCFLAGS="${CROSSCFLAGS_X32}"
export CROSSCXXFLAGS="${CROSSCFLAGS_X32}"

mkdir "${BUILD_DIR}"/build32-tools
cd "${BUILD_DIR}"/build32-tools || exit
PKG_CONFIG_LIBDIR="/usr/local/lib/pkgconfig:/usr/local/lib/i386-linux-gnu/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig" ${BWRAP32} "${BUILD_DIR}"/wine/configure ${WINE_BUILD_OPTIONS} --prefix "${BUILD_DIR}"/wine-"${BUILD_NAME}"-x86
${BWRAP32} make -j$(nproc) install

export CFLAGS="${CFLAGS_X64}"
export CXXFLAGS="${CFLAGS_X64}"
export CROSSCFLAGS="${CROSSCFLAGS_X64}"
export CROSSCXXFLAGS="${CROSSCFLAGS_X64}"

mkdir "${BUILD_DIR}"/build32
cd "${BUILD_DIR}"/build32 || exit
PKG_CONFIG_LIBDIR="/usr/local/lib/pkgconfig:/usr/local/lib/i386-linux-gnu/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig" ${BWRAP32} "${BUILD_DIR}"/wine/configure --with-wine64="${BUILD_DIR}"/build64 --with-wine-tools="${BUILD_DIR}"/build32-tools ${WINE_BUILD_OPTIONS} --prefix "${BUILD_DIR}"/wine-${BUILD_NAME}-amd64
${BWRAP32} make -j$(nproc) install

export CROSSCC="${CROSSCC_X64}"
export CROSSCXX="${CROSSCXX_X64}"
export CFLAGS="${CFLAGS_X64}"
export CXXFLAGS="${CFLAGS_X64}"
export CROSSCFLAGS="${CROSSCFLAGS_X64}"
export CROSSCXXFLAGS="${CROSSCFLAGS_X64}"

cd "${BUILD_DIR}"/build64 || exit
${BWRAP64} make -j$(nproc) install

# Biên dịch và cài đặt FEX-Emu
if [ "$BUILD_FEX" = "true" ]; then
    echo
    echo "Building and installing FEX-Emu..."
    echo

    # Biên dịch FEX cho WOW64 (x86 trên ARM64)
    mkdir -p "${BUILD_DIR}/fex/build-wow64"
    cd "${BUILD_DIR}/fex/build-wow64" || exit 1
    # Bỏ biến CC và CXX để CMake tự động nhận trình biên dịch chéo qua MINGW_TRIPLE
    ${BWRAP64} env -u CC -u CXX cmake -G Ninja \
        -DCMAKE_INSTALL_PREFIX="${BUILD_DIR}/wine-${BUILD_NAME}-amd64" \
        -DCMAKE_INSTALL_LIBDIR="lib/wine/aarch64-windows" \
        -DMINGW_TRIPLE=aarch64-w64-mingw32 \
        -DENABLE_LTO=False \
        -DBUILD_TESTING=False \
        -DENABLE_JEMALLOC_GLIBC_ALLOC=False \
        -DTUNE_CPU=none ..
    ${BWRAP64} ninja
    ${BWRAP64} ninja install

    # Biên dịch FEX cho ARM64EC (x86_64 trên ARM64)
    mkdir -p "${BUILD_DIR}/fex/build-arm64ec"
    cd "${BUILD_DIR}/fex/build-arm64ec" || exit 1
    ${BWRAP64} env -u CC -u CXX cmake -G Ninja \
        -DCMAKE_INSTALL_PREFIX="${BUILD_DIR}/wine-${BUILD_NAME}-amd64" \
        -DCMAKE_INSTALL_LIBDIR="lib/wine/arm64ec-windows" \
        -DMINGW_TRIPLE=arm64ec-w64-mingw32 \
        -DENABLE_LTO=False \
        -DBUILD_TESTING=False \
        -DENABLE_JEMALLOC_GLIBC_ALLOC=False \
        -DTUNE_CPU=none ..
    ${BWRAP64} ninja
    ${BWRAP64} ninja install

    cd "${BUILD_DIR}" || exit 1
fi

echo
echo "Compilation complete"
echo "Creating and compressing archives..."

cd "${BUILD_DIR}" || exit

if touch "${scriptdir}"/write_test; then
	rm -f "${scriptdir}"/write_test
	result_dir="${scriptdir}"
else
	result_dir="${HOME}"
fi

export XZ_OPT="-9 -T 0"

builds_list="wine-${BUILD_NAME}-x86 wine-${BUILD_NAME}-amd64"

if [ "${EXPERIMENTAL_WOW64}" = "true" ]; then
    # Nhờ FEX đã được cài thẳng vào thư mục amd64,
    # nó cũng sẽ được copy nguyên vẹn sang thư mục amd64-wow64 tại bước này.
	cp -r wine-${BUILD_NAME}-amd64 wine-${BUILD_NAME}-amd64-wow64
	builds_list="${builds_list} wine-${BUILD_NAME}-amd64-wow64"
fi

for build in ${builds_list}; do
	if [ -d "${build}" ]; then
		if [ -f wine/wine-tkg-config.txt ]; then
			cp wine/wine-tkg-config.txt "${build}"
		fi

		if [ "${build}" = "wine-${BUILD_NAME}-amd64-wow64" ]; then
  			if [ -f "${build}"/bin/wine64 ]; then
				rm -f "${build}"/bin/wine "${build}"/bin/wine-preloader
				cp "${build}"/bin/wine64 "${build}"/bin/wine
			fi

	   		rm -rf "${build}"/lib/wine/i386-unix
		fi

		tar -Jcf "${build}".tar.xz "${build}"
		mv "${build}".tar.xz "${result_dir}"
	fi
done

rm -rf "${BUILD_DIR}"

echo
echo "Done"
echo "The builds should be in ${result_dir}"
