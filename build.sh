#!/bin/bash

if [[ -z "$1" ]]; then
    echo "Usage: $0 <os>"
    echo "Supported OS values: linux, macos"
    exit 1
fi

# Check for NDK_TOOLCHAIN environment variable and abort if it is not set.
if [[ -z "${NDK_TOOLCHAIN}" ]]; then
    echo "Please specify the Android NDK environment variable \"NDK_TOOLCHAIN\"."
    exit 1
fi

# Prerequisites.
sudo apt install \
    golang \
    ninja-build \
    autogen \
    autoconf \
    libtool \
    build-essential \
    -y || exit 1

root="$(pwd)"

# Install protobuf compiler.
cd "src/protobuf" || exit 1
./autogen.sh
./configure
make -j"$(nproc)"
sudo make install
sudo ldconfig

# Go back.
cd "$root" || exit 1

# Apply patches.
for patch in patches/*.patch; do
    git apply "$patch" --whitespace=fix
done

# Define all the compilers, libraries and targets.
api="30"
os=$1
declare -A compilers
declare -A lib_arch
declare -A target_abi

if [[ "$os" == "linux" ]]; then
    compilers=(
        [x86_64]=x86_64-linux-android
        [arm64-v8a]=aarch64-linux-android
    )
    lib_arch=(
        [x86_64]=x86_64-linux-android
        [arm64-v8a]=aarch64-linux-android
    )
    target_abi=(
        [x86_64]=x86_64
        [arm64-v8a]=aarch64
    )
elif [[ "$os" == "macos" ]]; then # add macos support
    compilers=(
        [x86_64]=x86_64-linux-android
        [arm64-v8a]=aarch64-linux-android
    )
    lib_arch=(
        [x86_64]=x86_64-linux-android
        [arm64-v8a]=aarch64-linux-android
    )
    target_abi=(
        [x86_64]=x86_64
        [arm64-v8a]=aarch64
    )
else
    echo "Unsupported OS: $os"
    exit 1
fi

# Loop over all architectures
for architecture in "${!compilers[@]}"; do
    echo "Building for architecture: $architecture"

    # Each architecture gets its own build folder
    build_directory="$root/build-$architecture"
    bin_directory="$root/src/main/resources/$os/$architecture"

    # Create build folder
    mkdir -p "$build_directory"
    cd "$build_directory" || exit 1

    # Define the compiler architecture and compiler
    compiler_arch="${compilers[$architecture]}"
    c_compiler="$compiler_arch$api-clang"
    cxx_compiler="${c_compiler}++"

    # Copy libc.a to libpthread.a
    lib_path="$NDK_TOOLCHAIN/sysroot/usr/lib/${lib_arch[$architecture]}/$api/"
    cp -n "$lib_path/libc.a" "$lib_path/libpthread.a"

    # Build with CMake
    compiler_bin_directory="$NDK_TOOLCHAIN/bin/"
    cmake -GNinja \
        -DCMAKE_C_COMPILER="$compiler_bin_directory$c_compiler" \
        -DCMAKE_CXX_COMPILER="$compiler_bin_directory$cxx_compiler" \
        -DCMAKE_BUILD_WITH_INSTALL_RPATH=True \
        -DCMAKE_BUILD_TYPE=Release \
        -DANDROID_ABI="$architecture" \
        -DTARGET_ABI="${target_abi[$architecture]}" \
        -DPROTOC_PATH="/usr/local/bin/protoc" \
        -DCMAKE_SYSROOT="$NDK_TOOLCHAIN/sysroot" \
        .. || exit 1

    ninja || exit 1

    # Strip binary
    aapt_binary_path="$build_directory/cmake/aapt2"
    "$NDK_TOOLCHAIN/bin/llvm-strip" --strip-unneeded "$aapt_binary_path"

    # Move output
    mkdir -p "$bin_directory"
    mv "$aapt_binary_path" "$bin_directory"

    # Return to root
    cd "$root" || exit 1
done