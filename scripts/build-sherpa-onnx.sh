#!/usr/bin/env bash
# Build sherpa-onnx xcframework for macOS (universal: arm64 + x86_64).
# Output: vendor/sherpa-onnx.xcframework
#
# Prerequisites: cmake, Xcode Command Line Tools
# Usage: ./scripts/build-sherpa-onnx.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENDOR_DIR="$PROJECT_ROOT/vendor"
SHERPA_VERSION="v1.12.23"
SHERPA_SRC="$VENDOR_DIR/sherpa-onnx-src"
BUILD_DIR="$VENDOR_DIR/sherpa-onnx-build"
OUTPUT="$VENDOR_DIR/sherpa-onnx.xcframework"

echo "=== Building sherpa-onnx xcframework ==="
echo "Version: $SHERPA_VERSION"
echo "Output:  $OUTPUT"

# 1. Clone source (shallow, pinned tag)
if [ ! -d "$SHERPA_SRC" ]; then
    echo ">>> Cloning sherpa-onnx $SHERPA_VERSION ..."
    git clone --depth 1 --branch "$SHERPA_VERSION" \
        https://github.com/k2-fsa/sherpa-onnx.git "$SHERPA_SRC"
else
    echo ">>> Source already exists at $SHERPA_SRC, skipping clone."
fi

# 2. Build with CMake (universal binary)
echo ">>> Configuring CMake ..."
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

cmake \
    -DSHERPA_ONNX_ENABLE_BINARY=OFF \
    -DSHERPA_ONNX_BUILD_C_API_EXAMPLES=OFF \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DCMAKE_INSTALL_PREFIX="$BUILD_DIR/install" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DSHERPA_ONNX_ENABLE_PYTHON=OFF \
    -DSHERPA_ONNX_ENABLE_TESTS=OFF \
    -DSHERPA_ONNX_ENABLE_CHECK=OFF \
    -DSHERPA_ONNX_ENABLE_PORTAUDIO=OFF \
    -DSHERPA_ONNX_ENABLE_JNI=OFF \
    -DSHERPA_ONNX_ENABLE_C_API=ON \
    -DSHERPA_ONNX_ENABLE_WEBSOCKET=OFF \
    "$SHERPA_SRC"

echo ">>> Building (this may take several minutes) ..."
make -j"$(sysctl -n hw.ncpu)"
make install

# Remove unneeded header
rm -fv "$BUILD_DIR/install/include/cargs.h"

# 3. Merge static libraries into a single archive
echo ">>> Merging static libraries ..."
libtool -static -o "$BUILD_DIR/install/lib/libsherpa-onnx.a" \
    "$BUILD_DIR/install/lib/libsherpa-onnx-c-api.a" \
    "$BUILD_DIR/install/lib/libsherpa-onnx-core.a" \
    "$BUILD_DIR/install/lib/libkaldi-native-fbank-core.a" \
    "$BUILD_DIR/install/lib/libkissfft-float.a" \
    "$BUILD_DIR/install/lib/libsherpa-onnx-fstfar.a" \
    "$BUILD_DIR/install/lib/libsherpa-onnx-fst.a" \
    "$BUILD_DIR/install/lib/libsherpa-onnx-kaldifst-core.a" \
    "$BUILD_DIR/install/lib/libkaldi-decoder-core.a" \
    "$BUILD_DIR/install/lib/libucd.a" \
    "$BUILD_DIR/install/lib/libpiper_phonemize.a" \
    "$BUILD_DIR/install/lib/libespeak-ng.a" \
    "$BUILD_DIR/install/lib/libssentencepiece_core.a" \
    "$BUILD_DIR/install/lib/libonnxruntime.a"

# 4. Create xcframework
# Requires Xcode (not just Command Line Tools). Use DEVELOPER_DIR if needed.
echo ">>> Creating xcframework ..."
rm -rf "$OUTPUT"

XCODEBUILD_CMD="xcodebuild"
if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

$XCODEBUILD_CMD -create-xcframework \
    -library "$BUILD_DIR/install/lib/libsherpa-onnx.a" \
    -headers "$BUILD_DIR/install/include" \
    -output "$OUTPUT"

echo ""
echo "=== Done! ==="
echo "xcframework: $OUTPUT"
echo ""
echo "Next steps:"
echo "  1. Open TransFlow.xcodeproj in Xcode"
echo "  2. Drag vendor/sherpa-onnx.xcframework into the project"
echo "  3. Ensure it is linked in Build Phases > Link Binary With Libraries"
