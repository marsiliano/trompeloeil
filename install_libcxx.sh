#!/usr/bin/env bash

TRUNK_VERSION="14.0.1"

set -e

# The pattern of clang --version is: clang version X.Y.Z (sometimes, see below).
COMPILER_VERSION_OUTPUT="$($CXX --version)"
arr=(${COMPILER_VERSION_OUTPUT// / })

COMPILER="${arr[0]}"
VERSION="${arr[2]}"

case $COMPILER in
    "clang")
        # Some Ubuntu clang builds are advertised as "just clang", but the
        # Version still follows the pattern: 3.6.2-svn240577-1~exp1
        # echo "Compiler is clang :)"
        arr2=(${VERSION//-/ })
        VERSION="${arr2[0]}"
        ;;
    "Ubuntu")
        # Ubuntu renames _some_ (not all) of its clang compilers, the pattern of
        # clang --version is then:
        # Ubuntu clang version 3.6.2-svn240577-1~exp1
        COMPILER="${arr[1]}"
        VERSION="${arr[3]}"
        arr2=(${VERSION//-/ })
        VERSION="${arr2[0]}"
        ;;
    *)
        echo "case did not match: compiler: ${COMPILER}"
        exit 1
        ;;
esac

if [ ${COMPILER} != "clang" ]; then
    echo "Error: trying to install libc++ for a compiler that is not clang: ${COMPILER}"
    exit 1
fi

if [ -z ${VERSION+x} ]; then
    echo "Malformed libc++ version - I give up."
    exit 4
fi

MAJOR=$(echo $VERSION | sed 's/\..*//')
if [ ${VERSION} == $TRUNK_VERSION ]; then
    echo "Fetching libc++ and libc++abi tip-of-trunk..."

    # Checkout LLVM sources
    git clone --depth=1 https://github.com/llvm-mirror/llvm.git llvm-source
    git clone --depth=1 https://github.com/llvm-mirror/libcxx.git llvm-source/projects/libcxx
    git clone --depth=1 https://github.com/llvm-mirror/libcxxabi.git llvm-source/projects/libcxxabi
else
    echo "Fetching libc++/libc++abi version: ${VERSION}..."
    if [ ${MAJOR} -ge 8 ]; then
        BASE_URL="https://github.com/llvm/llvm-project/releases/download/llvmorg-"
    else
        BASE_URL="https://releases.llvm.org/"
    fi
    LLVM_URL="${BASE_URL}${VERSION}/llvm-${VERSION}.src.tar.xz"
    LIBCXX_URL="${BASE_URL}${VERSION}/libcxx-${VERSION}.src.tar.xz"
    LIBCXXABI_URL="${BASE_URL}${VERSION}/libcxxabi-${VERSION}.src.tar.xz"
    echo wget $LLVM_URL
    echo wget $LIBCXX_URL
    echo wget $LIBCXXABI_URL
    wget $LLVM_URL
    wget $LIBCXX_URL
    wget $LIBCXXABI_URL
    mkdir llvm-source
    mkdir llvm-source/projects
    mkdir llvm-source/projects/libcxx
    mkdir llvm-source/projects/libcxxabi

    tar -xf llvm-${VERSION}.src.tar.xz -C llvm-source --strip-components=1
    tar -xf libcxx-${VERSION}.src.tar.xz -C llvm-source/projects/libcxx --strip-components=1
    tar -xf libcxxabi-${VERSION}.src.tar.xz -C llvm-source/projects/libcxxabi --strip-components=1
fi

TARGET=`pwd`/llvm
mkdir "${TARGET}"
mkdir llvm-build
cd llvm-build

# - libc++ versions < 4.x do not have the install-cxxabi and install-cxx targets
# - only ASAN is enabled for clang/libc++ versions < 4.x
if [[ $VERSION == *"3."* ]]; then
    cmake -DCMAKE_C_COMPILER=${CC} -DCMAKE_CXX_COMPILER=${CXX} \
          -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX="${TARGET}" \
          ../llvm-source
    if [[ $SANITIZER == "Address;Undefined" ]]; then
        ASAN_FLAGS="-fsanitize=address"
        cmake -DCMAKE_CXX_FLAGS="${ASAN_FLAGS}" -DCMAKE_EXE_LINKER_FLAGS="${ASAN_FLAGS}" ../llvm-source
    fi
    make cxx -j4 VERBOSE=1
    mkdir "${TARGET}/lib"
    mkdir "${TARGET}/include"
    cp -r lib/* "${TARGET}/lib"
    cp -r include/c++ "${TARGET}/include"
else
    cmake -DCMAKE_C_COMPILER=${CC} -DCMAKE_CXX_COMPILER=${CXX} \
          -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX="${TARGET}" \
          -DLIBCXX_ABI_UNSTABLE=ON \
          -DCMAKE_BUILD_WITH_INSTALL_RPATH=1 \
          -DLLVM_USE_SANITIZER=${SANITIZER} \
          ../llvm-source
    make cxx -j4 VERBOSE=1
    make install-cxxabi install-cxx
fi

exit 0
