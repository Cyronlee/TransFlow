#!/bin/bash
set -euo pipefail

# ============================================================================
# TransFlow DMG Packaging Script
# 使用 create-dmg 工具将 TransFlow.app 打包为 DMG 安装镜像
# ============================================================================

# ── 配置 ──────────────────────────────────────────────────────────────────────

APP_NAME="TransFlow"
SCHEME="TransFlow"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
XCODE_PROJECT="${PROJECT_DIR}/TransFlow/TransFlow.xcodeproj"
BUILD_DIR="${PROJECT_DIR}/build"
DMG_DIR="${BUILD_DIR}/dmg"
APP_PATH="${DMG_DIR}/${APP_NAME}.app"
DMG_OUTPUT="${BUILD_DIR}/${APP_NAME}.dmg"

# DMG 外观配置
DMG_VOLNAME="${APP_NAME}"
DMG_BACKGROUND="${PROJECT_DIR}/scripts/dmg/background.png"
DMG_WINDOW_POS_X=200
DMG_WINDOW_POS_Y=120
DMG_WINDOW_WIDTH=600
DMG_WINDOW_HEIGHT=400
DMG_ICON_SIZE=100
DMG_TEXT_SIZE=12
DMG_APP_ICON_X=170
DMG_APP_ICON_Y=190
DMG_APP_DROP_LINK_X=430
DMG_APP_DROP_LINK_Y=190

# Build 配置
CONFIGURATION="Release"
ARCH="$(uname -m)"  # arm64 或 x86_64

# ── 颜色输出 ─────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ── 参数解析 ─────────────────────────────────────────────────────────────────

SKIP_BUILD=false
CLEAN_BUILD=false
OPEN_DMG=false
CODESIGN_IDENTITY=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --open)
            OPEN_DMG=true
            shift
            ;;
        --codesign)
            CODESIGN_IDENTITY="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-build    跳过 Xcode build，直接打包已有的 .app"
            echo "  --clean         clean build（先清理再构建）"
            echo "  --open          打包完成后自动打开 DMG"
            echo "  --codesign ID   使用指定身份对 DMG 进行代码签名"
            echo "  -h, --help      显示帮助"
            exit 0
            ;;
        *)
            error "未知参数: $1（使用 --help 查看帮助）"
            ;;
    esac
done

# ── 前置检查 ─────────────────────────────────────────────────────────────────

info "检查依赖..."

if ! command -v create-dmg &> /dev/null; then
    error "create-dmg 未安装。请运行: brew install create-dmg"
fi

if ! command -v xcodebuild &> /dev/null; then
    error "xcodebuild 未找到。请安装 Xcode Command Line Tools"
fi

success "依赖检查通过"

# ── 清理 ─────────────────────────────────────────────────────────────────────

info "清理旧的构建产物..."
rm -rf "${DMG_DIR}"
rm -f "${DMG_OUTPUT}"
mkdir -p "${DMG_DIR}"

# ── 构建 ─────────────────────────────────────────────────────────────────────

if [ "$SKIP_BUILD" = true ]; then
    warn "跳过构建步骤"
    
    # 查找已有的 .app
    DERIVED_APP=$(find ~/Library/Developer/Xcode/DerivedData -name "${APP_NAME}.app" -path "*/Release/*" -type d 2>/dev/null | head -1)
    if [ -z "$DERIVED_APP" ]; then
        error "未找到已构建的 ${APP_NAME}.app，请先构建或去掉 --skip-build"
    fi
    info "使用已有构建: ${DERIVED_APP}"
    cp -R "${DERIVED_APP}" "${APP_PATH}"
else
    if [ "$CLEAN_BUILD" = true ]; then
        info "执行 clean build..."
        xcodebuild clean \
            -project "${XCODE_PROJECT}" \
            -scheme "${SCHEME}" \
            -configuration "${CONFIGURATION}" \
            -quiet
    fi

    info "构建 ${APP_NAME} (${CONFIGURATION}, ${ARCH})..."
    
    xcodebuild build \
        -project "${XCODE_PROJECT}" \
        -scheme "${SCHEME}" \
        -configuration "${CONFIGURATION}" \
        -arch "${ARCH}" \
        -derivedDataPath "${BUILD_DIR}/DerivedData" \
        -quiet \
        ONLY_ACTIVE_ARCH=NO
    
    # 复制 .app 到 DMG 准备目录
    BUILT_APP="${BUILD_DIR}/DerivedData/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
    if [ ! -d "${BUILT_APP}" ]; then
        error "构建完成但未找到 ${APP_NAME}.app: ${BUILT_APP}"
    fi
    
    cp -R "${BUILT_APP}" "${APP_PATH}"
    success "构建完成"
fi

# 验证 .app 存在
if [ ! -d "${APP_PATH}" ]; then
    error "${APP_NAME}.app 不存在: ${APP_PATH}"
fi

# ── 获取版本号 ───────────────────────────────────────────────────────────────

APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || echo "1.0.0")
APP_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || echo "1")
DMG_FINAL="${BUILD_DIR}/${APP_NAME}-${APP_VERSION}.dmg"

info "版本: ${APP_VERSION} (build ${APP_BUILD})"

# ── 创建 DMG ────────────────────────────────────────────────────────────────

info "创建 DMG 安装镜像..."

CREATE_DMG_ARGS=(
    --volname "${DMG_VOLNAME}"
    --window-pos "${DMG_WINDOW_POS_X}" "${DMG_WINDOW_POS_Y}"
    --window-size "${DMG_WINDOW_WIDTH}" "${DMG_WINDOW_HEIGHT}"
    --icon-size "${DMG_ICON_SIZE}"
    --text-size "${DMG_TEXT_SIZE}"
    --icon "${APP_NAME}.app" "${DMG_APP_ICON_X}" "${DMG_APP_ICON_Y}"
    --hide-extension "${APP_NAME}.app"
    --app-drop-link "${DMG_APP_DROP_LINK_X}" "${DMG_APP_DROP_LINK_Y}"
    --no-internet-enable
)

# 添加背景图（如果存在）
if [ -f "${DMG_BACKGROUND}" ]; then
    CREATE_DMG_ARGS+=(--background "${DMG_BACKGROUND}")
    info "使用背景图: ${DMG_BACKGROUND}"
else
    warn "未找到背景图: ${DMG_BACKGROUND}，将使用默认背景"
fi

# 添加代码签名（如果指定）
if [ -n "${CODESIGN_IDENTITY}" ]; then
    CREATE_DMG_ARGS+=(--codesign "${CODESIGN_IDENTITY}")
    info "代码签名: ${CODESIGN_IDENTITY}"
fi

# 添加 volume icon（如果存在 .icns）
VOLICON="${PROJECT_DIR}/scripts/dmg/volume-icon.icns"
if [ -f "${VOLICON}" ]; then
    CREATE_DMG_ARGS+=(--volicon "${VOLICON}")
fi

# 执行 create-dmg
# create-dmg 退出码: 0=成功, 2=DMG 已创建但某些美化步骤失败
set +e
create-dmg \
    "${CREATE_DMG_ARGS[@]}" \
    --hdiutil-retries 15 \
    "${DMG_OUTPUT}" \
    "${DMG_DIR}/"
CREATE_DMG_EXIT=$?
set -e

if [ ${CREATE_DMG_EXIT} -ne 0 ] && [ ${CREATE_DMG_EXIT} -ne 2 ]; then
    # 清理可能残留的临时 rw DMG
    rm -f "${BUILD_DIR}"/rw.*.dmg 2>/dev/null
    error "create-dmg 失败 (exit code: ${CREATE_DMG_EXIT})"
fi

if [ -f "${DMG_OUTPUT}" ]; then
    # 重命名为带版本号的文件名
    mv "${DMG_OUTPUT}" "${DMG_FINAL}"
    success "DMG 创建成功!"
elif ls "${BUILD_DIR}"/rw.*.dmg 1>/dev/null 2>&1; then
    # create-dmg 可能因 unmount 失败留下了 rw DMG，尝试手动转换
    warn "create-dmg 未生成最终 DMG，尝试手动转换..."
    RW_DMG=$(ls "${BUILD_DIR}"/rw.*.dmg | head -1)
    
    # 强制 detach 所有可能挂载的 DMG
    for dev in $(hdiutil info 2>/dev/null | grep "/dev/disk" | grep -v "/dev/disk0" | awk '{print $1}' | sort -u); do
        hdiutil detach "$dev" -force 2>/dev/null || true
    done
    sleep 2
    
    hdiutil convert "${RW_DMG}" -format UDZO -o "${DMG_FINAL}" -quiet
    rm -f "${RW_DMG}"
    success "DMG 转换成功!"
else
    error "DMG 创建失败，未找到任何输出文件"
fi

# ── 结果 ─────────────────────────────────────────────────────────────────────

DMG_SIZE=$(du -h "${DMG_FINAL}" | cut -f1 | xargs)
echo ""
echo "============================================"
echo -e "  ${GREEN}${APP_NAME} DMG 打包完成${NC}"
echo "  版本:   ${APP_VERSION} (${APP_BUILD})"
echo "  架构:   ${ARCH}"
echo "  大小:   ${DMG_SIZE}"
echo "  路径:   ${DMG_FINAL}"
echo "============================================"
echo ""

# 自动打开
if [ "$OPEN_DMG" = true ]; then
    info "打开 DMG..."
    open "${DMG_FINAL}"
fi
