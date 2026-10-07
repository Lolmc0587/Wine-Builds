#!/usr/bin/env bash

########################################################################
##
## A script for Wine compilation focusing on ARM64/WoW64/FEX.
## Uses bubblewrap and an Ubuntu bootstrap.
##
## This script requires: git, wget, autoconf, xz, bubblewrap, cmake, ninja
##
########################################################################

# Prevent launching as root
if [ $EUID = 0 ] && [ -z "$ALLOW_ROOT" ]; then
	echo "Do not run this script as root!"
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

# Build FEX-Emu
export BUILD_FEX="true"

export WINE_BUILD_OPTIONS="--without-oss --disable-winemenubuilder --disable-tests"
export BUILD_DIR="${HOME}/build_wine"
export MAINDIR="/opt/chroots"
export BOOTSTRAP_ARM64="${MAINDIR}/jammy_arm64_chroot"

export scriptdir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

# export CC="gcc"
# export CXX="g++"
export CC="/opt/mingw/bin/clang"
export CXX="/opt/mingw/bin/clang++"

export LDFLAGS="-Wl,-O1,--sort-common,--as-needed"

# Mount /opt/mingw (toolchain) explicitly inside the bwrap container
build_with_bwrap () {
    BOOTSTRAP_PATH="${BOOTSTRAP_ARM64}"

    bwrap --ro-bind "${BOOTSTRAP_PATH}" / --dev /dev --ro-bind /sys /sys \
          --proc /proc --tmpfs /tmp --tmpfs /home --tmpfs /run --tmpfs /var \
          --tmpfs /mnt --tmpfs /media --tmpfs /opt --bind "${BUILD_DIR}" "${BUILD_DIR}" \
          --bind "${MAINDIR}/mingw" /opt/mingw \
          --setenv PATH "/opt/mingw/bin:/usr/local/bin:/bin:/sbin:/usr/bin:/usr/sbin" \
          "$@"
}

BWRAP64="build_with_bwrap"

if ! command -v git 1>/dev/null || ! command -v autoconf 1>/dev/null || ! command -v bwrap 1>/dev/null; then
	echo "Please install missing commands (git, autoconf, bwrap) and run again"
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
		cp -r "${CUSTOM_SRC_PATH}" wine
	fi

	WINE_VERSION="$(cat wine/VERSION | tail -c +14)"
	BUILD_NAME="${WINE_VERSION}-custom"
elif [ "$WINE_BRANCH" = "staging-tkg" ] || [ "$WINE_BRANCH" = "staging-tkg-fsync" ]; then
	if [ "$WINE_BRANCH" = "staging-tkg" ]; then
		git clone https://github.com/Kron4ek/wine-tkg wine
	else
		git clone https://github.com/Kron4ek/wine-tkg wine -b fsync
	fi

	WINE_VERSION="$(cat wine/VERSION | tail -c +14)"
	BUILD_NAME="${WINE_VERSION}-${WINE_BRANCH}"
elif [ "$WINE_BRANCH" = "proton" ]; then
	if [ -z "${PROTON_BRANCH}" ]; then
		git clone https://github.com/ValveSoftware/wine
	else
		git clone https://github.com/ValveSoftware/wine -b "${PROTON_BRANCH}"
	fi

 	patch -d wine -Np1 < "${scriptdir}/fix-proton-compilation-and-version-output.patch"

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
			upstream_commit="$(cat wine-staging-${WINE_VERSION}/staging/upstream-commit | head -c 7)"
			git -C wine checkout "${upstream_commit}"
			BUILD_NAME="${WINE_VERSION}-${upstream_commit}-staging"
		else
			if [ -n "${STAGING_VERSION}" ]; then
				WINE_VERSION="${STAGING_VERSION}"
			fi

			BUILD_NAME="${WINE_VERSION}-staging"
			wget -q --show-progress "https://github.com/wine-staging/wine-staging/archive/v${WINE_VERSION}.tar.gz"
			tar xf v"${WINE_VERSION}".tar.gz

			if [ ! -f v"${WINE_VERSION}".tar.gz ]; then
				git clone https://github.com/wine-staging/wine-staging wine-staging-"${WINE_VERSION}"
			fi
		fi

		if [ -f wine-staging-"${WINE_VERSION}"/patches/patchinstall.sh ]; then
			staging_patcher=("${BUILD_DIR}/wine-staging-${WINE_VERSION}/patches/patchinstall.sh"
							DESTDIR="${BUILD_DIR}/wine")
		else
			staging_patcher=("${BUILD_DIR}/wine-staging-${WINE_VERSION}/staging/patchinstall.py")
		fi

		cd wine || exit 1
		if [ -n "${STAGING_ARGS}" ]; then
			"${staging_patcher[@]}" ${STAGING_ARGS}
		else
			"${staging_patcher[@]}" --all
		fi

		if [ $? -ne 0 ]; then
			echo "Wine-Staging patches were not applied correctly!"
			exit 1
		fi

		cd "${BUILD_DIR}" || exit 1
	fi
fi

# Clone FEX if enabled
if [ "$BUILD_FEX" = "true" ]; then
    if [ ! -d fex ]; then
        echo "Downloading FEX-Emu source code..."
        git clone --recurse-submodules https://github.com/FEX-Emu/FEX.git fex
    fi
fi
cd "${BUILD_DIR}" || exit 1
patch -d wine*/ -Np1 < "${scriptdir}/0001-qcap-fix-Smart-Tee-preview-allocator-and-RGB32-negot.patch"
patch -d wine*/ -Np1 < "${scriptdir}/0002-qcap-fix-wow64-media-type-marshaling-in-v4l-backend.patch"

cd wine || exit 1
dlls/winevulkan/make_vulkan
tools/make_requests
tools/make_specfiles
autoreconf -f
cd "${BUILD_DIR}" || exit 1

if [ "${DO_NOT_COMPILE}" = "true" ]; then
	echo "DO_NOT_COMPILE is set to true. Exiting."
	exit
fi

if [ ! -d "${BOOTSTRAP_ARM64}" ]; then
	echo "Bootstrap is required for compilation!"
	exit 1
fi

# --- Start Building ---

# Clear strict cross-compiler overrides so Wine can auto-detect all of them
unset CROSSCC CROSSCXX CROSSCFLAGS CROSSCXXFLAGS

# Make sure the llvm-mingw bin directory is in your PATH
export PATH="${MAINDIR}/mingw/bin:$PATH"

mkdir -p "${BUILD_DIR}/wine-build"
cd "${BUILD_DIR}/wine-build" || exit

# Configure Wine to build ALL architectures for New WoW64
# PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig" \
${BWRAP64} "${BUILD_DIR}/wine/configure" \
    --prefix="${BUILD_DIR}/wine-${BUILD_NAME}-arm64" \
    --enable-archs=aarch64,i386,arm64ec \
    ${WINE_BUILD_OPTIONS}

# Build and install everything
${BWRAP64} make -j$(nproc) install

# --- FEX-Emu ---
if [ "$BUILD_FEX" = "true" ]; then
    echo
    echo "Building and installing FEX-Emu..."
    echo

    # Build FEX for WOW64 (x86 execution on ARM64)
    mkdir -p "${BUILD_DIR}/fex/build-wow64"
    cd "${BUILD_DIR}/fex/build-wow64" || exit 1
    ${BWRAP64} env -u CC -u CXX LDFLAGS="-static" cmake -G Ninja \
        -DCMAKE_INSTALL_PREFIX="${BUILD_DIR}/wine-${BUILD_NAME}-arm64" \
        -DCMAKE_INSTALL_LIBDIR="lib/wine/aarch64-windows" \
        -DCMAKE_TOOLCHAIN_FILE="../Data/CMake/toolchain_mingw.cmake" \
        -DMINGW_TRIPLE=aarch64-w64-mingw32 \
        -DENABLE_LTO=False \
        -DBUILD_TESTING=False \
        -DBUILD_FEXCONFIG=False \
        -DENABLE_JEMALLOC_GLIBC_ALLOC=False \
        -DTUNE_CPU=none ..
    ${BWRAP64} ninja
    ${BWRAP64} ninja install


    # Build FEX for ARM64EC (x86_64 execution on ARM64)
    mkdir -p "${BUILD_DIR}/fex/build-arm64ec"
    cd "${BUILD_DIR}/fex/build-arm64ec" || exit 1
    ${BWRAP64} env -u CC -u CXX LDFLAGS="-static" cmake -G Ninja \
        -DCMAKE_INSTALL_PREFIX="${BUILD_DIR}/wine-${BUILD_NAME}-arm64" \
        -DCMAKE_INSTALL_LIBDIR="lib/wine/arm64ec-windows" \
        -DCMAKE_TOOLCHAIN_FILE="../Data/CMake/toolchain_mingw.cmake" \
        -DMINGW_TRIPLE=arm64ec-w64-mingw32 \
        -DENABLE_LTO=False \
        -DBUILD_TESTING=False \
        -DBUILD_FEXCONFIG=False \
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

if touch "${scriptdir}/write_test"; then
	rm -f "${scriptdir}/write_test"
	result_dir="${scriptdir}"
else
	result_dir="${HOME}"
fi

export XZ_OPT="-9 -T 0"

# Only compress the arm64 prefix since ARM64EC and FEX are embedded inside
builds_list="wine-${BUILD_NAME}-arm64"

for build in ${builds_list}; do
	if [ -d "${build}" ]; then
		if [ -f wine/wine-tkg-config.txt ]; then
			cp wine/wine-tkg-config.txt "${build}"
		fi
		echo "Stripping debug symbols to reduce size..."

		${BWRAP64} find "${BUILD_DIR}/${build}/bin" -type f -exec strip --strip-unneeded {} + 2>/dev/null || true

		${BWRAP64} find "${BUILD_DIR}/${build}/lib" -name "*.so" -exec strip --strip-unneeded {} + 2>/dev/null || true

		${BWRAP64} find "${BUILD_DIR}/${build}/lib/wine" \( -name "*.dll" -o -name "*.exe" \) -exec llvm-strip --strip-unneeded {} + 2>/dev/null || true

		echo "Stripping completed."
		echo "Injecting MinGW runtime DLLs into Wine prefix..."

		# Inject AArch64 MinGW runtimes
		cp "${MAINDIR}/mingw/aarch64-w64-mingw32/bin/"*.dll "${BUILD_DIR}/wine-${BUILD_NAME}-arm64/lib/wine/aarch64-windows/"

		# Inject ARM64EC MinGW runtimes
		cp "${MAINDIR}/mingw/arm64ec-w64-mingw32/bin/"*.dll "${BUILD_DIR}/wine-${BUILD_NAME}-arm64/lib/wine/arm64ec-windows/"

        # Inject i386 (x86 WoW64) MinGW runtimes
        cp "${MAINDIR}/mingw/i686-w64-mingw32/bin/"*.dll "${BUILD_DIR}/wine-${BUILD_NAME}-arm64/lib/wine/i386-windows/"

        # Inject x86_64 MinGW runtimes
        cp "${MAINDIR}/mingw/x86_64-w64-mingw32/bin/"*.dll "${BUILD_DIR}/wine-${BUILD_NAME}-arm64/lib/wine/x86_64-windows/"

       echo "Symlinking FEX-Emu engines to New WoW64 JIT targets..."

		# Link 32-bit FEX engine
		cp "${BUILD_DIR}/wine-${BUILD_NAME}-arm64/lib/wine/aarch64-windows/libwow64fex.dll" \
		   "${BUILD_DIR}/wine-${BUILD_NAME}-arm64/lib/wine/aarch64-windows/xtajit.dll"

		# Link 64-bit FEX engine
		cp "${BUILD_DIR}/wine-${BUILD_NAME}-arm64/lib/wine/arm64ec-windows/libarm64ecfex.dll" \
		   "${BUILD_DIR}/wine-${BUILD_NAME}-arm64/lib/wine/aarch64-windows/xtajit64.dll"

		cp "${BUILD_DIR}/wine-${BUILD_NAME}-arm64/lib/wine/arm64ec-windows/libarm64ecfex.dll" \
		   "${BUILD_DIR}/wine-${BUILD_NAME}-arm64/lib/wine/arm64ec-windows/xtajit64.dll"

        echo "Testing Wine + FEX execution in headless mode..."

		# 1. Point to the newly built binaries
		export PATH="${BUILD_DIR}/wine-${BUILD_NAME}-arm64/bin:$PATH"
		export WINEPREFIX="${BUILD_DIR}/test-prefix"

		# 2. Disable debug spam and ensure no display is expected
		export WINEDEBUG=-all
		unset DISPLAY

		# 3. Initialize the prefix headlessly (creates the registry and folders)
		wine wineboot -u

		# 4. Execute a built-in Windows binary (cmd.exe)
		# Since cmd.exe is a Windows PE binary, this forces Wine to invoke FEX-Emu
		wine cmd.exe /c echo "Successfully executed Windows CMD via FEX on GitHub Actions!"

		if [ $? -eq 0 ]; then
		    echo "FEX-Emu integration test passed!"
		else
		    echo "FEX-Emu integration test FAILED!"
		    exit 1
		fi

		tar -Jcf "${build}.tar.xz" "${build}"
		mv "${build}.tar.xz" "${result_dir}"
	fi
done

rm -rf "${BUILD_DIR}"

echo "Done"
echo "The builds should be in ${result_dir}"
