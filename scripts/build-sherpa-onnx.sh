#!/usr/bin/env bash
# Build sherpa-onnx xcframework for macOS (default: universal arm64+x86_64).
# Output: vendor/sherpa-onnx.xcframework
#
# Usage:
#   ./scripts/build-sherpa-onnx.sh
#   ./scripts/build-sherpa-onnx.sh --clean --reclone
#   ./scripts/build-sherpa-onnx.sh --version v1.12.23 --archs "arm64;x86_64"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENDOR_DIR="$PROJECT_ROOT/vendor"

SHERPA_VERSION="v1.12.23"
ARCHS="arm64;x86_64"
DEPLOYMENT_TARGET="15.0"
JOBS="$(sysctl -n hw.ncpu)"
CLEAN_BUILD=0
RECLONE_SOURCE=0

SHERPA_SRC="$VENDOR_DIR/sherpa-onnx-src"
BUILD_DIR="$VENDOR_DIR/sherpa-onnx-build"
OUTPUT="$VENDOR_DIR/sherpa-onnx.xcframework"

START_TS="$(date +%s)"

usage() {
    cat <<'EOF'
Build sherpa-onnx xcframework for TransFlow.

Options:
  --version <tag>          sherpa-onnx git tag to build (default: v1.12.23)
  --archs <list>           CMAKE_OSX_ARCHITECTURES (default: arm64;x86_64)
  --deployment-target <v>  CMAKE_OSX_DEPLOYMENT_TARGET (default: 15.0)
  --jobs <n>               Parallel build jobs (default: hw.ncpu)
  --output <path>          Output xcframework path
  --clean                  Remove build directory before building
  --reclone                Remove source directory and clone again
  -h, --help               Show this help
EOF
}

log() {
    printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

run() {
    log "$*"
    "$@"
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

assert_file() {
    [ -f "$1" ] || die "Required file not found: $1"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --version)
            [ $# -ge 2 ] || die "Missing value for --version"
            SHERPA_VERSION="$2"
            shift 2
            ;;
        --archs)
            [ $# -ge 2 ] || die "Missing value for --archs"
            ARCHS="$2"
            shift 2
            ;;
        --deployment-target)
            [ $# -ge 2 ] || die "Missing value for --deployment-target"
            DEPLOYMENT_TARGET="$2"
            shift 2
            ;;
        --jobs)
            [ $# -ge 2 ] || die "Missing value for --jobs"
            JOBS="$2"
            shift 2
            ;;
        --output)
            [ $# -ge 2 ] || die "Missing value for --output"
            OUTPUT="$2"
            shift 2
            ;;
        --clean)
            CLEAN_BUILD=1
            shift
            ;;
        --reclone)
            RECLONE_SOURCE=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Unknown option: $1 (use --help)"
            ;;
    esac
done

OUTPUT_TMP="${OUTPUT}.tmp"

for cmd in git cmake xcodebuild libtool lipo make sysctl; do
    require_cmd "$cmd"
done

ACTIVE_DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
if [ "$ACTIVE_DEV_DIR" = "/Library/Developer/CommandLineTools" ]; then
    if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
        export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
        log "Using DEVELOPER_DIR=$DEVELOPER_DIR"
    else
        die "xcodebuild is pointing to CommandLineTools. Install full Xcode or set DEVELOPER_DIR."
    fi
fi

log "=== Building sherpa-onnx xcframework ==="
log "Version: $SHERPA_VERSION"
log "Archs: $ARCHS"
log "Deployment target: $DEPLOYMENT_TARGET"
log "Output: $OUTPUT"

mkdir -p "$VENDOR_DIR"
mkdir -p "$(dirname "$OUTPUT")"

if [ "$RECLONE_SOURCE" -eq 1 ] && [ -d "$SHERPA_SRC" ]; then
    run rm -rf "$SHERPA_SRC"
fi

if [ ! -d "$SHERPA_SRC/.git" ]; then
    [ ! -e "$SHERPA_SRC" ] || die "Path exists but is not a git repo: $SHERPA_SRC (use --reclone)"
    run git clone --depth 1 --branch "$SHERPA_VERSION" \
        https://github.com/k2-fsa/sherpa-onnx.git "$SHERPA_SRC"
else
    CURRENT_TAG="$(git -C "$SHERPA_SRC" describe --tags --exact-match 2>/dev/null || true)"
    if [ "$CURRENT_TAG" != "$SHERPA_VERSION" ]; then
        if ! git -C "$SHERPA_SRC" diff --quiet || [ -n "$(git -C "$SHERPA_SRC" status --porcelain)" ]; then
            die "Existing source has local changes and is not at $SHERPA_VERSION. Use --reclone."
        fi
        run git -C "$SHERPA_SRC" fetch --tags origin
        run git -C "$SHERPA_SRC" checkout "$SHERPA_VERSION"
        run git -C "$SHERPA_SRC" reset --hard "$SHERPA_VERSION"
    else
        log "Source already at $SHERPA_VERSION: $SHERPA_SRC"
    fi
fi

if [ "$CLEAN_BUILD" -eq 1 ] && [ -d "$BUILD_DIR" ]; then
    run rm -rf "$BUILD_DIR"
fi

run cmake -S "$SHERPA_SRC" -B "$BUILD_DIR" \
    -DSHERPA_ONNX_ENABLE_BINARY=OFF \
    -DSHERPA_ONNX_BUILD_C_API_EXAMPLES=OFF \
    -DCMAKE_OSX_ARCHITECTURES="$ARCHS" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
    -DCMAKE_INSTALL_PREFIX="$BUILD_DIR/install" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DSHERPA_ONNX_ENABLE_PYTHON=OFF \
    -DSHERPA_ONNX_ENABLE_TESTS=OFF \
    -DSHERPA_ONNX_ENABLE_CHECK=OFF \
    -DSHERPA_ONNX_ENABLE_PORTAUDIO=OFF \
    -DSHERPA_ONNX_ENABLE_JNI=OFF \
    -DSHERPA_ONNX_ENABLE_C_API=ON \
    -DSHERPA_ONNX_ENABLE_WEBSOCKET=OFF

run cmake --build "$BUILD_DIR" --config Release --parallel "$JOBS"
run cmake --install "$BUILD_DIR" --config Release

if [ -f "$BUILD_DIR/install/include/cargs.h" ]; then
    run rm -f "$BUILD_DIR/install/include/cargs.h"
fi

MERGED_LIB="$BUILD_DIR/install/lib/libsherpa-onnx.a"
STATIC_LIBS=(
    "$BUILD_DIR/install/lib/libsherpa-onnx-c-api.a"
    "$BUILD_DIR/install/lib/libsherpa-onnx-core.a"
    "$BUILD_DIR/install/lib/libkaldi-native-fbank-core.a"
    "$BUILD_DIR/install/lib/libkissfft-float.a"
    "$BUILD_DIR/install/lib/libsherpa-onnx-fstfar.a"
    "$BUILD_DIR/install/lib/libsherpa-onnx-fst.a"
    "$BUILD_DIR/install/lib/libsherpa-onnx-kaldifst-core.a"
    "$BUILD_DIR/install/lib/libkaldi-decoder-core.a"
    "$BUILD_DIR/install/lib/libucd.a"
    "$BUILD_DIR/install/lib/libpiper_phonemize.a"
    "$BUILD_DIR/install/lib/libespeak-ng.a"
    "$BUILD_DIR/install/lib/libssentencepiece_core.a"
    "$BUILD_DIR/install/lib/libonnxruntime.a"
)

for lib in "${STATIC_LIBS[@]}"; do
    assert_file "$lib"
done

run libtool -static -o "$MERGED_LIB" "${STATIC_LIBS[@]}"
assert_file "$MERGED_LIB"

ARCH_INFO="$(lipo -info "$MERGED_LIB" 2>/dev/null || true)"
[ -n "$ARCH_INFO" ] || die "Unable to inspect merged library architectures: $MERGED_LIB"
ARCH_LIST="${ARCHS//;/ }"
for arch in $ARCH_LIST; do
    case "$ARCH_INFO" in
        *"$arch"*) ;;
        *) die "Merged library missing architecture: $arch ($ARCH_INFO)" ;;
    esac
done
log "Merged library architectures: $ARCH_INFO"

run rm -rf "$OUTPUT_TMP"
run xcodebuild -create-xcframework \
    -library "$MERGED_LIB" \
    -headers "$BUILD_DIR/install/include" \
    -output "$OUTPUT_TMP"

run rm -rf "$OUTPUT"
run mv "$OUTPUT_TMP" "$OUTPUT"

[ -d "$OUTPUT" ] || die "xcframework output missing: $OUTPUT"

ELAPSED="$(( $(date +%s) - START_TS ))"
log ""
log "=== Done ==="
log "xcframework: $OUTPUT"
log "elapsed: ${ELAPSED}s"
log ""
log "Next step: open TransFlow.xcodeproj and build the app."
